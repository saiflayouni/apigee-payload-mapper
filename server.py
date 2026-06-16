#!/usr/bin/env python3
"""
Demo UI server — serves index.html and streams SSE events from the Apigee emulator.
Usage: python3 server.py
"""

import json
import time
import urllib.request
import urllib.error
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
from urllib.parse import urlparse, parse_qs
from pathlib import Path

PROXY_URL = "http://localhost:8999/payload-mapper"
MOCKS_DIR = Path(__file__).parent / "mocks"

MOCKS = {
    "ok": json.loads((MOCKS_DIR / "payload-ok.json").read_text()),
    "drifted": json.loads((MOCKS_DIR / "payload-drifted.json").read_text()),
}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/":
            self._serve_file("index.html", "text/html; charset=utf-8")
        elif path == "/api/run":
            mode = parse_qs(urlparse(self.path).query).get("mode", ["ok"])[0]
            self._stream(mode)
        else:
            self.send_response(404); self.end_headers()

    def _serve_file(self, name, ctype):
        try:
            data = open(name, "rb").read()
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", len(data))
            self.end_headers()
            self.wfile.write(data)
        except FileNotFoundError:
            self.send_response(404); self.end_headers()

    def _stream(self, mode):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()

        def emit(evt, data):
            try:
                self.wfile.write(f"event: {evt}\ndata: {json.dumps(data)}\n\n".encode())
                self.wfile.flush()
                return True
            except BrokenPipeError:
                return False

        try:
            _run(mode, emit)
        except Exception as ex:
            emit("error", {"message": str(ex)})


def _run(mode, emit):
    source = MOCKS.get(mode, MOCKS["ok"])

    if not emit("source", {"payload": source}):
        return
    time.sleep(0.5)

    body = json.dumps(source).encode()
    req = urllib.request.Request(PROXY_URL, data=body)
    req.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            result = json.loads(resp.read().decode())
    except Exception as ex:
        emit("error", {"message": f"Could not reach Apigee proxy: {ex}"})
        return

    method = result.get("mapping_method")
    audit = result.get("audit", {})
    static_valid = method == "static"

    if not emit("static_result", {
        "valid": static_valid,
        "missing_fields": audit.get("static_mapping_missing_fields", []),
    }):
        return
    time.sleep(0.7)

    if not static_valid:
        if not emit("gemini_check", {}):
            return
        time.sleep(1.0)

        if method == "gemini_self_healed":
            if not emit("gemini_result", {
                "confidence": audit.get("confidence"),
                "notes": audit.get("notes"),
            }):
                return
        else:
            if not emit("gemini_failed", {"alert": audit.get("alert")}):
                return
        time.sleep(0.4)

    emit("done", {
        "mapping_method": method,
        "transformed_payload": result.get("transformed_payload"),
    })


class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True


if __name__ == "__main__":
    server = ThreadedHTTPServer(("localhost", 3001), Handler)
    print("┌─────────────────────────────────────┐")
    print("│  Demo UI → http://localhost:3001    │")
    print("│  Ctrl-C to stop                     │")
    print("└─────────────────────────────────────┘")
    server.serve_forever()
