"""Scryfall API access: bulk data discovery, sets, migrations, downloads.

Every request to ``api.scryfall.com`` carries an identifying User-Agent, as the
API requires, and is throttled to stay inside the documented 10 req/s limit.
Downloads from ``data.scryfall.io`` are unmetered and are not throttled.
"""

from __future__ import annotations

import gzip
import json
import shutil
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Iterator

API_BASE = "https://api.scryfall.com"
USER_AGENT = "MTGCollectionTracker/1.0"
HEADERS = {"User-Agent": USER_AGENT, "Accept": "*/*"}

# Documented limit for /bulk-data, /sets, /migrations is 10 req/s.
_API_INTERVAL = 0.12
_last_call = 0.0


def _throttle() -> None:
    global _last_call
    wait = _API_INTERVAL - (time.monotonic() - _last_call)
    if wait > 0:
        time.sleep(wait)
    _last_call = time.monotonic()


def get_json(url: str, *, retries: int = 3) -> dict[str, Any]:
    """GET a JSON document, backing off properly on HTTP 429."""
    for attempt in range(retries):
        _throttle()
        req = urllib.request.Request(url, headers=HEADERS)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as exc:
            if exc.code == 429:
                # Scryfall imposes a 30 second lockout; retrying sooner risks a ban.
                print("  rate limited, sleeping 30s", file=sys.stderr)
                time.sleep(30)
                continue
            if exc.code >= 500 and attempt < retries - 1:
                time.sleep(2**attempt)
                continue
            raise
        except urllib.error.URLError:
            if attempt < retries - 1:
                time.sleep(2**attempt)
                continue
            raise
    raise RuntimeError(f"exhausted retries for {url}")


def paginate(url: str) -> Iterator[dict[str, Any]]:
    """Yield every item from a paginated Scryfall List response."""
    while url:
        payload = get_json(url)
        for item in payload.get("data", []):
            yield item
        url = payload.get("next_page") if payload.get("has_more") else None


def find_bulk_source(bulk_type: str = "default_cards") -> dict[str, Any]:
    """Return the bulk_data object for the requested dataset type."""
    payload = get_json(f"{API_BASE}/bulk-data")
    for entry in payload.get("data", []):
        if entry.get("type") == bulk_type:
            return entry
    available = sorted(e.get("type", "?") for e in payload.get("data", []))
    raise SystemExit(f"bulk type {bulk_type!r} not found; available: {available}")


def download(url: str, dest: Path) -> Path:
    """Download to disk before parsing.

    Downloading first, rather than parsing straight off the socket, means a slow
    transform cannot time out the HTTP connection, and a failed run can be retried
    without re-fetching.
    """
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=120) as resp:
        total = int(resp.headers.get("Content-Length") or 0)
        done = 0
        step = max(total // 10, 1) if total else 8 << 20
        next_mark = step
        with dest.open("wb") as fh:
            while True:
                chunk = resp.read(1 << 20)
                if not chunk:
                    break
                fh.write(chunk)
                done += len(chunk)
                if done >= next_mark:
                    pct = f" ({done * 100 // total}%)" if total else ""
                    print(f"  downloaded {done >> 20} MiB{pct}", file=sys.stderr)
                    next_mark += step
    print(f"  downloaded {done >> 20} MiB total -> {dest.name}", file=sys.stderr)
    return dest


def iter_jsonl(path: Path) -> Iterator[dict[str, Any]]:
    """Stream a (possibly gzipped) JSONL file one object at a time.

    The decompressed default_cards file is ~500 MB, so it is never fully read
    into memory.
    """
    with path.open("rb") as raw:
        is_gzip = raw.read(2) == b"\x1f\x8b"

    opener = gzip.open if is_gzip else open
    with opener(path, "rb") as fh:  # type: ignore[operator]
        for line in fh:
            line = line.strip().rstrip(b",")
            # Tolerate a JSON-array wrapper in case Scryfall serves .json rather
            # than .jsonl for a given dataset.
            if not line or line in (b"[", b"]"):
                continue
            yield json.loads(line)


def gzip_file(src: Path, dest: Path) -> Path:
    with src.open("rb") as fin, gzip.open(dest, "wb", compresslevel=9) as fout:
        shutil.copyfileobj(fin, fout, length=1 << 20)
    return dest
