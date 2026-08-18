"""Pre-publish validation. A build that fails any check must not be released."""

from __future__ import annotations

import random
import sqlite3
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

from transform import image_url

HEADERS = {"User-Agent": "MTGCollectionTracker/1.0", "Accept": "*/*"}

# Expected magnitudes, per planning/02-catalog-schema.md §6. These are regression
# guards: a build far outside them means the source data or the transform broke.
BOUNDS = {
    "cards": (20_000, 60_000),
    "printings": (80_000, 200_000),
    "sets": (700, 2_000),
}
GZIP_BOUNDS_MB = (8, 40)
IMAGE_SAMPLE = 25


class ValidationError(Exception):
    pass


def _count(conn: sqlite3.Connection, table: str) -> int:
    return conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]


def check_counts(conn: sqlite3.Connection, failures: list[str]) -> None:
    for table, (low, high) in BOUNDS.items():
        n = _count(conn, table)
        if not low <= n <= high:
            failures.append(f"{table} has {n} rows, expected between {low} and {high}")


def check_integrity(conn: sqlite3.Connection, failures: list[str]) -> None:
    """Foreign keys are not declared in the schema (for insert speed), so verify here."""
    orphan_cards = conn.execute(
        "SELECT COUNT(*) FROM printings p "
        "LEFT JOIN cards c ON c.oracle_id = p.oracle_id WHERE c.oracle_id IS NULL"
    ).fetchone()[0]
    if orphan_cards:
        failures.append(f"{orphan_cards} printings reference a missing card")

    orphan_sets = conn.execute(
        "SELECT COUNT(*) FROM printings p "
        "LEFT JOIN sets s ON s.code = p.set_code WHERE s.code IS NULL"
    ).fetchone()[0]
    if orphan_sets:
        failures.append(f"{orphan_sets} printings reference a missing set")

    bad_default = conn.execute(
        "SELECT COUNT(*) FROM cards c "
        "LEFT JOIN printings p ON p.scryfall_id = c.default_printing_id "
        "WHERE p.scryfall_id IS NULL"
    ).fetchone()[0]
    if bad_default:
        failures.append(f"{bad_default} cards have a default_printing_id that does not exist")


def check_fts(conn: sqlite3.Connection, failures: list[str]) -> None:
    cards = _count(conn, "cards")
    indexed = conn.execute("SELECT COUNT(*) FROM cards_fts").fetchone()[0]
    if cards != indexed:
        failures.append(f"cards_fts has {indexed} rows but cards has {cards}")
    try:
        conn.execute("SELECT rowid FROM cards_fts WHERE cards_fts MATCH ? LIMIT 1", ('"bolt"*',))
    except sqlite3.Error as exc:
        failures.append(f"cards_fts is not queryable: {exc}")


def check_gzip_size(path: Path, failures: list[str]) -> None:
    size_mb = path.stat().st_size / (1 << 20)
    low, high = GZIP_BOUNDS_MB
    if not low <= size_mb <= high:
        failures.append(f"compressed catalog is {size_mb:.1f} MB, expected {low}-{high} MB")


def check_images(conn: sqlite3.Connection, failures: list[str], sample: int = IMAGE_SAMPLE) -> None:
    """Spot-check that derived image URLs actually resolve on the CDN."""
    rows = conn.execute(
        "SELECT scryfall_id FROM printings WHERE image_status != 'missing'"
    ).fetchall()
    if not rows:
        failures.append("no printings with images to spot-check")
        return

    for scryfall_id in (r[0] for r in random.sample(rows, min(sample, len(rows)))):
        url = image_url(scryfall_id, "small")
        req = urllib.request.Request(url, headers=HEADERS, method="HEAD")
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                if resp.status != 200:
                    failures.append(f"image URL returned {resp.status}: {url}")
        except urllib.error.HTTPError as exc:
            failures.append(f"image URL returned {exc.code}: {url}")
        except urllib.error.URLError as exc:
            failures.append(f"image URL unreachable ({exc.reason}): {url}")
        time.sleep(0.2)  # stay polite even though the CDN is unmetered


def validate(
    conn: sqlite3.Connection,
    gzip_path: "Path | None" = None,
    *,
    partial: bool = False,
    skip_images: bool = False,
) -> None:
    """Raise ValidationError describing every problem found, not just the first."""
    failures: list[str] = []

    check_integrity(conn, failures)
    check_fts(conn, failures)

    if partial:
        print("  partial build: skipping row-count and size thresholds", file=sys.stderr)
    else:
        check_counts(conn, failures)
        if gzip_path is not None:
            check_gzip_size(gzip_path, failures)

    if skip_images:
        print("  skipping image spot-check", file=sys.stderr)
    else:
        check_images(conn, failures)

    if failures:
        raise ValidationError(
            "catalog failed validation:\n" + "\n".join(f"  - {f}" for f in failures)
        )
