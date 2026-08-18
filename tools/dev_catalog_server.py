"""Serves a locally built catalog so the app's bootstrap can be tested on device.

The stdlib's ``http.server`` ignores ``Range``, which makes it impossible to
exercise the resume path the app relies on; GitHub Releases, where the catalog
actually lives, supports ranges. This adds just enough of that to be
representative.

Usage::

    python tools/dev_catalog_server.py
    flutter run --dart-define=MANIFEST_URL=http://10.0.2.2:8000/manifest.json

The manifest is rewritten on the fly so its ``url`` points back at this server.
"""

from __future__ import annotations

import argparse
import json
import re
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

RANGE_RE = re.compile(r"^bytes=(\d+)-(\d*)$")
CHUNK = 64 * 1024


class RangeHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, root: Path, host_url: str, **kwargs):
        self._root = root
        self._host_url = host_url
        super().__init__(*args, directory=str(root), **kwargs)

    def do_GET(self) -> None:  # noqa: N802 - stdlib naming
        if self.path == "/manifest.json":
            return self._serve_manifest()

        path = Path(self.translate_path(self.path))
        header = self.headers.get("Range")
        match = RANGE_RE.match(header) if header else None
        if not path.is_file() or match is None:
            return super().do_GET()

        size = path.stat().st_size
        start = int(match.group(1))
        end = int(match.group(2)) if match.group(2) else size - 1
        if start >= size:
            self.send_response(416)
            self.send_header("Content-Range", f"bytes */{size}")
            self.end_headers()
            return

        end = min(end, size - 1)
        length = end - start + 1

        self.send_response(206)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()

        with path.open("rb") as handle:
            handle.seek(start)
            remaining = length
            while remaining > 0:
                block = handle.read(min(CHUNK, remaining))
                if not block:
                    break
                self.wfile.write(block)
                remaining -= len(block)

    def _serve_manifest(self) -> None:
        manifest = json.loads((self._root / "manifest.json").read_text())
        manifest["url"] = f"{self._host_url}/{Path(manifest['url']).name}"
        body = json.dumps(manifest).encode()

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default="build/serve", help="directory to serve")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument(
        "--host-url",
        default="http://10.0.2.2:8000",
        help="how the device reaches this server (10.0.2.2 is the emulator's host)",
    )
    args = parser.parse_args()

    root = Path(args.root).resolve()
    if not (root / "manifest.json").is_file():
        raise SystemExit(f"no manifest.json in {root}")

    handler = partial(RangeHandler, root=root, host_url=args.host_url.rstrip("/"))
    server = ThreadingHTTPServer(("0.0.0.0", args.port), handler)
    print(f"serving {root} on port {args.port}, advertising {args.host_url}")
    server.serve_forever()


if __name__ == "__main__":
    main()
