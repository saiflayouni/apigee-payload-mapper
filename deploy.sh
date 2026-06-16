#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load .env if present (so users don't need to export manually)
[ -f "$SCRIPT_DIR/.env" ] && source "$SCRIPT_DIR/.env"
BUNDLE="$SCRIPT_DIR/proxy-bundle.zip"
IMAGE="gcr.io/apigee-release/hybrid/apigee-emulator:1.9.2"
CONTAINER="payload-mapper"
APIGEE_ORG="hybrid"
APIGEE_ENV="test"
MGMT="http://localhost:8081"
RUNTIME="http://localhost:8999"

# ── 0. Gemini API key (self-healing remap on a broken static mapping) ──────

GEMINI_KEY="${GEMINI_API_KEY:-disabled}"
mkdir -p "$SCRIPT_DIR/apiproxy/resources/properties"
echo "gemini_api_key=$GEMINI_KEY" > "$SCRIPT_DIR/apiproxy/resources/properties/config.properties"

if [ "$GEMINI_KEY" = "disabled" ]; then
  echo "ℹ  GEMINI_API_KEY not set — Gemini self-healing remap disabled (static-fallback only)"
  echo "   To enable: export GEMINI_API_KEY=your_key && bash deploy.sh"
else
  echo "✓ Gemini API key configured (self-healing remap enabled)"
fi

# ── 1. Build proxy bundle (SDLC format) ─────────────────────────────────────

echo "▶ Building proxy bundle..."
SDLC_TMP="$(mktemp -d)/sdlc"
SDLC_ROOT="$SDLC_TMP/src/main/apigee"
PROXY_SRC="$SCRIPT_DIR/apiproxy"

mkdir -p \
  "$SDLC_ROOT/environments/test" \
  "$SDLC_ROOT/apiproxies/payload-mapper/apiproxy/policies" \
  "$SDLC_ROOT/apiproxies/payload-mapper/apiproxy/proxies" \
  "$SDLC_ROOT/apiproxies/payload-mapper/apiproxy/targets" \
  "$SDLC_ROOT/apiproxies/payload-mapper/apiproxy/resources/jsc" \
  "$SDLC_ROOT/apiproxies/payload-mapper/apiproxy/resources/properties"

echo '{"proxies": [{"name": "payload-mapper"}]}' \
  > "$SDLC_ROOT/environments/test/deployments.json"

DEST="$SDLC_ROOT/apiproxies/payload-mapper/apiproxy"
cp "$PROXY_SRC/payload-mapper.xml"                 "$DEST/"
cp "$PROXY_SRC/policies/"*.xml                     "$DEST/policies/"
cp "$PROXY_SRC/proxies/default.xml"                "$DEST/proxies/"
cp "$PROXY_SRC/targets/default.xml"                "$DEST/targets/"
cp "$PROXY_SRC/resources/jsc/"*.js                  "$DEST/resources/jsc/"
cp "$PROXY_SRC/resources/properties/config.properties" "$DEST/resources/properties/"

(cd "$SDLC_TMP" && zip -r "$BUNDLE" src/ -q)
echo "✓ Bundle built ($(du -h "$BUNDLE" | cut -f1))"

# ── 2. Start emulator (separate container/ports from the loop-detector demo) ─

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  echo "✓ Emulator already running"
else
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "▶ Restarting existing container..."
    docker start "$CONTAINER"
  else
    echo "▶ Starting emulator..."
    docker run -d \
      --name "$CONTAINER" \
      -p 8081:8080 \
      -p 8999:8998 \
      -e APIGEE_ORG="$APIGEE_ORG" \
      -e APIGEE_ENV="$APIGEE_ENV" \
      -e LISTEN_ADDRESS=127.0.0.1 \
      -e GOOGLE_APPLICATION_CREDENTIALS="" \
      -e microkernel_installType=hybrid \
      -e microkernel_application=emulator \
      "$IMAGE"
  fi
fi

# ── 3. Wait for emulator to be ready ────────────────────────────────────────

echo -n "⏳ Waiting for emulator"
READY=false
for i in $(seq 1 60); do
  if curl -sf "$MGMT/v1/emulator/version" > /dev/null 2>&1; then
    READY=true
    break
  fi
  echo -n "."
  sleep 2
done
echo ""

if [ "$READY" = false ]; then
  echo "✗ Emulator did not start within 120s"
  docker logs "$CONTAINER" --tail 20
  exit 1
fi
echo "✓ Emulator ready"

# ── 4. Deploy proxy bundle ───────────────────────────────────────────────────

echo "▶ Deploying proxy bundle..."
RESPONSE=$(curl -sf -X POST \
  "$MGMT/v1/emulator/deploy?environment=$APIGEE_ENV" \
  -H "Content-Type: application/octet-stream" \
  --data-binary "@$BUNDLE")

REVISION=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('revision','?'))" 2>/dev/null || echo "?")
echo "✓ Deployed revision $REVISION"

# ── 5. Smoke test ────────────────────────────────────────────────────────────

echo "▶ Smoke testing..."

OK_RESPONSE=$(curl -s "$RUNTIME/payload-mapper" \
  -H "Content-Type: application/json" \
  --data-binary "@$SCRIPT_DIR/mocks/payload-ok.json")
OK_METHOD=$(echo "$OK_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('mapping_method','?'))" 2>/dev/null || echo "?")

if [ "$OK_METHOD" != "static" ]; then
  echo "✗ Unchanged payload did not map statically (got mapping_method=$OK_METHOD)"
  echo "$OK_RESPONSE"
  exit 1
fi
echo "✓ Unmodified payload → static mapping"

DRIFTED_RESPONSE=$(curl -s "$RUNTIME/payload-mapper" \
  -H "Content-Type: application/json" \
  --data-binary "@$SCRIPT_DIR/mocks/payload-drifted.json")
DRIFTED_METHOD=$(echo "$DRIFTED_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('mapping_method','?'))" 2>/dev/null || echo "?")

if [ "$GEMINI_KEY" = "disabled" ]; then
  if [ "$DRIFTED_METHOD" != "static_unvalidated_fallback" ]; then
    echo "✗ Drifted payload did not fail open as expected (got mapping_method=$DRIFTED_METHOD)"
    echo "$DRIFTED_RESPONSE"
    exit 1
  fi
  echo "✓ Drifted payload → static mapping broke, failed open (no Gemini key)"
else
  if [ "$DRIFTED_METHOD" != "gemini_self_healed" ]; then
    echo "✗ Drifted payload was not self-healed (got mapping_method=$DRIFTED_METHOD)"
    echo "$DRIFTED_RESPONSE"
    exit 1
  fi
  echo "✓ Drifted payload → static mapping broke, Gemini self-healed it"
  echo "$DRIFTED_RESPONSE" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'  transformed_payload = {json.dumps(d[\"transformed_payload\"])}')
print(f'  confidence={d[\"audit\"].get(\"confidence\")}  notes={d[\"audit\"].get(\"notes\")}')
"
fi

echo ""
if [ "$GEMINI_KEY" = "disabled" ]; then
  echo "🚀 Demo ready! (static mapping + fail-open fallback)"
else
  echo "🚀 Demo ready! (static mapping + Gemini self-healing remap active)"
fi
echo "   Runtime : $RUNTIME/payload-mapper"
echo "   Org/Env : $APIGEE_ORG / $APIGEE_ENV"

# ── 6. Start UI server ───────────────────────────────────────────────────────

UI_PORT=3001

if lsof -ti tcp:$UI_PORT > /dev/null 2>&1; then
  echo "✓ UI server already running"
else
  echo "▶ Starting UI server..."
  cd "$SCRIPT_DIR" && python3 server.py > /tmp/apigee-payload-mapper-ui.log 2>&1 &
  UI_PID=$!
  sleep 1
  if kill -0 "$UI_PID" 2>/dev/null; then
    echo "✓ UI server started (pid $UI_PID)"
  else
    echo "✗ UI server failed to start — check /tmp/apigee-payload-mapper-ui.log"
  fi
fi

echo ""
echo "   Open: http://localhost:$UI_PORT"

if command -v open > /dev/null 2>&1; then
  open "http://localhost:$UI_PORT"
elif command -v xdg-open > /dev/null 2>&1; then
  xdg-open "http://localhost:$UI_PORT"
fi
