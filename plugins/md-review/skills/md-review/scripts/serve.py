#!/usr/bin/env python3
# plugins/md-review/skills/md-review/scripts/serve.py
"""md-review local server. Usage: serve.py <file.md>

Serves the single-page app from ../assets and exposes a tiny JSON API over docstore.
Bound to 127.0.0.1 on a random port. Shuts down after 30 min idle or POST /api/done.
"""
import json, os, sys, threading, webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.normpath(os.path.join(HERE, "..", "assets"))
sys.path.insert(0, HERE)
from docstore import read_doc, save_doc, ConflictError  # noqa: E402

IDLE_SECONDS = 30 * 60
CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".mjs": "text/javascript; charset=utf-8",
}


class _IdleTimer:
    def __init__(self, seconds, on_timeout):
        self.seconds, self.on_timeout, self.timer = seconds, on_timeout, None
        self.reset()

    def reset(self):
        if self.timer:
            self.timer.cancel()
        self.timer = threading.Timer(self.seconds, self.on_timeout)
        self.timer.daemon = True
        self.timer.start()


class Handler(BaseHTTPRequestHandler):
    target = None       # absolute path of the .md, set by build_server
    idle = None         # _IdleTimer, set by build_server

    def _bump(self):
        if Handler.idle:
            Handler.idle.reset()

    def _json(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _asset(self, name):
        path = os.path.normpath(os.path.join(ASSETS, name))
        if not path.startswith(ASSETS + os.sep) or not os.path.isfile(path):
            self.send_error(404)
            return
        with open(path, "rb") as f:
            body = f.read()
        ext = os.path.splitext(path)[1]
        self.send_response(200)
        self.send_header("Content-Type", CONTENT_TYPES.get(ext, "application/octet-stream"))
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self._bump()
        if self.path == "/":
            self._asset("index.html")
        elif self.path == "/api/doc":
            self._json(200, read_doc(Handler.target))
        else:
            self._asset(self.path.lstrip("/").split("?")[0])

    def do_POST(self):
        self._bump()
        if self.path == "/api/save":
            length = int(self.headers.get("Content-Length", 0))
            data = json.loads(self.rfile.read(length) or b"{}")
            try:
                res = save_doc(
                    Handler.target,
                    data["markdown"],
                    data.get("baseHash", ""),
                    force=bool(data.get("force")),
                )
                self._json(200, res)
            except ConflictError as e:
                self._json(409, {"ok": False, "error": "conflict", "hash": e.current_hash})
        elif self.path == "/api/done":
            self._json(200, {"ok": True})
            threading.Thread(target=self.server.shutdown, daemon=True).start()
        else:
            self.send_error(404)

    def log_message(self, *args):  # keep the terminal quiet
        pass


def build_server(target, idle_seconds=IDLE_SECONDS):
    Handler.target = os.path.abspath(target)
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    Handler.idle = _IdleTimer(
        idle_seconds,
        lambda: threading.Thread(target=server.shutdown, daemon=True).start(),
    )
    return server


def main():
    if len(sys.argv) < 2:
        print("usage: serve.py <file.md>", file=sys.stderr)
        sys.exit(2)
    target = os.path.abspath(sys.argv[1])
    if not os.path.isfile(target):
        print(f"no such file: {target}", file=sys.stderr)
        sys.exit(2)
    server = build_server(target)
    port = server.server_address[1]
    url = f"http://127.0.0.1:{port}/"
    print(json.dumps({"url": url, "port": port, "file": target}))
    sys.stdout.flush()
    try:
        webbrowser.open(url)
    except Exception:
        pass
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
