"""Tiny visit counter that stores its state in /data, to show persistent volumes."""

import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

COUNT_FILE = Path("/data/count")
GREETING = os.environ.get("GREETING", "Hello")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        count = int(COUNT_FILE.read_text()) + 1 if COUNT_FILE.exists() else 1
        COUNT_FILE.write_text(str(count))
        body = f"{GREETING}! This page has been visited {count} times.\n".encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
