#!/usr/bin/env python3
"""
Apigee X — Self-Healing Semantic Payload Mapper — GDE Demo

  python demo.py            # full before → after
  python demo.py before     # static mapping on an unmodified payload
  python demo.py after      # partner drifts the schema, Gemini self-heals
"""

import sys
import json
import urllib.request
import urllib.error
from pathlib import Path

PROXY_URL = "http://localhost:8999/payload-mapper"
MOCKS_DIR = Path(__file__).parent / "mocks"

R = "\033[31m"; G = "\033[32m"; Y = "\033[33m"
C = "\033[36m"; W = "\033[1m";  X = "\033[0m"

BANNER = f"""
{W}╔══════════════════════════════════════════════════════════╗
║    Apigee X — Self-Healing Semantic Payload Mapper        ║
║    Static mapping breaks silently. Gemini fixes it live.  ║
╚══════════════════════════════════════════════════════════╝{X}
"""


def _call(payload):
    body = json.dumps(payload).encode()
    req = urllib.request.Request(PROXY_URL, data=body)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        print(f"  {R}HTTP {e.code}{X}: {e.reason}")
        return None
    except Exception as ex:
        print(f"  {R}Error:{X} {ex}")
        print("  Is the emulator running? Try: bash deploy.sh")
        return None


def _print_result(source, result):
    if result is None:
        return
    method = result.get("mapping_method")
    color = {"static": G, "gemini_self_healed": C, "static_unvalidated_fallback": R}.get(method, Y)

    print(f"\n{W}── source payload ───────────────────────────────────────{X}")
    print(f"  {json.dumps(source, indent=2)}")
    print(f"\n{W}── Apigee response ──────────────────────────────────────{X}")
    print(f"  mapping_method     : {color}{method}{X}")
    print(f"  transformed_payload: {json.dumps(result.get('transformed_payload'), indent=2)}")

    audit = result.get("audit", {})
    if method == "gemini_self_healed":
        print(f"  confidence         : {C}{audit.get('confidence')}{X}")
        print(f"  notes              : {Y}{audit.get('notes')}{X}")
        print(f"  fields it healed   : {audit.get('static_mapping_missing_fields')}")
    elif method == "static_unvalidated_fallback":
        print(f"  {R}alert              : {audit.get('alert')}{X}")
    print(f"{W}────────────────────────────────────────────────────────{X}\n")


def before():
    print(f"{W}━━━  Unmodified payload — static mapping just works  ━━━{X}")
    print(f"{Y}Core banking system sends the format the mapping expects.{X}")
    source = json.loads((MOCKS_DIR / "payload-ok.json").read_text())
    result = _call(source)
    _print_result(source, result)
    if result and result.get("mapping_method") == "static":
        print(f"{G}✓  Static AssignMessage-style mapping succeeded. No AI needed.{X}\n")


def after():
    print(f"{W}━━━  Partner renames every field — static mapping breaks  ━━━{X}")
    print(f"{Y}Same target schema expected, but the source field names changed.{X}")
    print(f"{Y}Today this fails silently. With Apigee + Gemini, it self-heals.{X}")
    source = json.loads((MOCKS_DIR / "payload-drifted.json").read_text())
    result = _call(source)
    _print_result(source, result)

    if not result:
        return
    method = result.get("mapping_method")
    if method == "gemini_self_healed":
        print(f"{G}✓  Gemini inferred the new field mapping from semantics alone — "
              f"0 downtime, 0 manual XSLT fix.{X}\n")
    elif method == "static_unvalidated_fallback":
        print(f"{R}✗  No GEMINI_API_KEY set — static mapping failed open with an alert "
              f"instead of silently shipping broken data.{X}")
        print(f"   To see the self-heal: export GEMINI_API_KEY=your_key && bash deploy.sh\n")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "both"
    print(BANNER)

    if mode in ("before", "both"):
        before()

    if mode == "both":
        print(f"  Press {W}Enter{X} to see the partner break the schema...", end="")
        input()
        print()

    if mode in ("after", "both"):
        after()
