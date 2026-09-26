#!/usr/bin/env python3
"""Preview build/web with the response headers needed by KataGo WASM."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class StaticHeaders(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1] / "build" / "web"
    if not (root / "index.html").is_file():
        parser.error("Run flutter build web --release first.")
    server = ThreadingHTTPServer(
        ("127.0.0.1", args.port), partial(StaticHeaders, directory=str(root))
    )
    print(f"EasyPlay: http://localhost:{server.server_port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
