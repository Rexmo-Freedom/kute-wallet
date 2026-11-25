#!/usr/bin/env python3
"""Serves a Kute web build (build/web) locally, with the cache headers the
service worker's update flow relies on.

  flutter build web --release && dart run tool/web_pwa_stamp.dart
  python3 tool/web_serve.py --port 5173            # or: ... path/to/build

`python3 -m http.server` sends Last-Modified and no Cache-Control, so a
browser may call a cached flutter_bootstrap.js "fresh" for minutes (10% of
the file's age) and keep starting the previous build after a reload.

Production hosting must send the same headers:
  - index.html (and the root /), flutter_bootstrap.js, sw.js, manifest.json,
    version.json:  Cache-Control: no-cache
    (sw.js and flutter_bootstrap.js carry the build id: they must always be
    revalidated; never a max-age, never a CDN cache without purge)
  - every other file: Cache-Control: no-cache too. Flutter's web build has
    no content-hashed file names (main.dart.js, canvaskit/, assets/ keep
    their names across builds), so nothing may be cached long-lived; the
    service worker keeps its own copy of the app shell for fast and
    offline starts. Should hashed files ever appear (a name carrying a
    hash, e.g. app.3f9a1c2e.js), those, and only those, may be
    `Cache-Control: public, max-age=31536000, immutable`.
  - plus the security headers index.html asks for: the Content-Security-
    Policy as a header with `frame-ancestors 'none'`, and
    `Referrer-Policy: no-referrer`.
No new dependencies: the standard library only.
"""

import argparse
import functools
import http.server
import os
import re
import sys

# Files whose name carries a content hash (none in today's Flutter build).
HASHED = re.compile(r"\.[0-9a-f]{8,}\.(js|mjs|wasm|css|png|svg|woff2?|ttf|otf)$")


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".js": "text/javascript",
        ".mjs": "text/javascript",
        ".wasm": "application/wasm",
        ".json": "application/json",
    }

    def end_headers(self):
        path = self.path.split("?", 1)[0].split("#", 1)[0]
        if HASHED.search(path):
            self.send_header("Cache-Control", "public, max-age=31536000, immutable")
        else:
            self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, format, *args):
        pass  # quiet: one line at start is enough


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("root", nargs="?", default="build/web")
    parser.add_argument("--port", type=int, default=5173)
    parser.add_argument("--bind", default="127.0.0.1")
    args = parser.parse_args()
    if not os.path.isfile(os.path.join(args.root, "index.html")):
        sys.exit(f"No web build at {args.root} (run flutter build web).")
    handler = functools.partial(Handler, directory=args.root)
    server = http.server.ThreadingHTTPServer((args.bind, args.port), handler)
    print(f"Serving {os.path.abspath(args.root)} at http://localhost:{args.port}/ "
          "(Cache-Control: no-cache, so a reload always sees the newest build)",
          flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
