"""Build the MTG catalog SQLite file from Scryfall bulk data.

Usage:
    python build_catalog.py --out build/
    python build_catalog.py --out build/ --limit 5000 --skip-images   # fast dev run

See planning/03-catalog-builder.md for the full specification.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sqlite3
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

import schema
import scryfall
import transform
from validate import ValidationError, validate

BATCH_SIZE = 5_000
REPO_ROOT = Path(__file__).resolve().parents[2]


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def require_fts5(conn: sqlite3.Connection) -> None:
    options = {row[0] for row in conn.execute("PRAGMA compile_options")}
    if "ENABLE_FTS5" not in options:
        raise SystemExit(
            "This Python's bundled SQLite lacks FTS5 support.\n"
            "Install `pysqlite3-binary` and import it as sqlite3, or use a Python\n"
            "build with FTS5 enabled (official CPython builds have it)."
        )


def create_database(path: Path) -> sqlite3.Connection:
    if path.exists():
        path.unlink()
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    # Autocommit mode: transactions are managed explicitly below, so that VACUUM
    # (which cannot run inside a transaction) is not tripped up by the driver's
    # implicit BEGIN.
    conn.isolation_level = None
    require_fts5(conn)
    # Safe to disable durability: the output is a disposable build artifact and a
    # crashed build is simply rerun.
    conn.executescript(
        "PRAGMA journal_mode = OFF;"
        "PRAGMA synchronous = OFF;"
        "PRAGMA temp_store = MEMORY;"
        "PRAGMA cache_size = -64000;"
    )
    conn.executescript(schema.TABLES)
    return conn


def load_sets(conn: sqlite3.Connection) -> int:
    log("fetching sets...")
    rows = [transform.to_set_row(s) for s in scryfall.paginate(f"{scryfall.API_BASE}/sets")]
    conn.executemany(schema.insert_sql("sets", schema.SET_COLUMNS), rows)
    log(f"  {len(rows)} sets")
    return len(rows)


def load_migrations(conn: sqlite3.Connection) -> int:
    log("fetching migrations...")
    rows = [
        transform.to_migration_row(m)
        for m in scryfall.paginate(f"{scryfall.API_BASE}/migrations")
    ]
    conn.executemany(schema.insert_sql("migrations", schema.MIGRATION_COLUMNS), rows)
    log(f"  {len(rows)} migrations")
    return len(rows)


def load_cards(conn: sqlite3.Connection, jsonl: Path, limit: Optional[int]) -> dict[str, int]:
    """Stream printings into the DB, accumulating oracle-level data in memory.

    Only oracle-level rows (~31k) are buffered; printings are flushed in batches
    so the ~500 MB decompressed source is never held in memory.
    """
    log("transforming cards...")
    printing_sql = schema.insert_sql("printings", schema.PRINTING_COLUMNS)

    printing_batch: list[tuple] = []
    oracle_cards: dict[str, dict[str, Any]] = {}
    best_rank: dict[str, tuple] = {}
    best_printing: dict[str, str] = {}

    seen = 0
    skipped = 0
    started = time.monotonic()

    for card in scryfall.iter_jsonl(jsonl):
        oracle_id = transform.resolve_oracle_id(card)
        if not oracle_id:
            skipped += 1
            continue

        printing_batch.append(transform.to_printing_row(card, oracle_id))
        seen += 1

        # Keep the first sighting of each oracle card for its rules text...
        if oracle_id not in oracle_cards:
            oracle_cards[oracle_id] = card

        # ...but keep comparing printings so the best default image wins.
        rank = transform.printing_rank(card)
        if oracle_id not in best_rank or rank < best_rank[oracle_id]:
            best_rank[oracle_id] = rank
            best_printing[oracle_id] = card["id"]

        if len(printing_batch) >= BATCH_SIZE:
            conn.executemany(printing_sql, printing_batch)
            printing_batch.clear()
            log(f"  {seen} printings, {len(oracle_cards)} cards")

        if limit and seen >= limit:
            log(f"  stopping early at --limit {limit}")
            break

    if printing_batch:
        conn.executemany(printing_sql, printing_batch)

    log(f"writing {len(oracle_cards)} oracle cards...")
    card_rows = []
    face_rows = []
    for oracle_id, card in oracle_cards.items():
        card_rows.append(transform.to_card_row(card, oracle_id, best_printing[oracle_id]))
        face_rows.extend(transform.to_face_rows(card, oracle_id))

    conn.executemany(schema.insert_sql("cards", schema.CARD_COLUMNS), card_rows)
    conn.executemany(schema.insert_sql("card_faces", schema.FACE_COLUMNS), face_rows)

    elapsed = time.monotonic() - started
    log(f"  {seen} printings, {len(card_rows)} cards, {len(face_rows)} faces in {elapsed:.1f}s")
    if skipped:
        log(f"  skipped {skipped} rows with no resolvable oracle_id")

    return {
        "printings": seen,
        "cards": len(card_rows),
        "faces": len(face_rows),
        "skipped_no_oracle_id": skipped,
    }


def finalize(conn: sqlite3.Connection) -> None:
    log("building indexes and FTS...")
    conn.executescript(schema.INDEXES)
    conn.executescript(schema.FTS)


def write_meta(conn: sqlite3.Connection, values: dict[str, Any]) -> None:
    conn.executemany(
        "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)",
        [(k, str(v)) for k, v in values.items()],
    )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_manifest(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    log(f"wrote {path}")


def parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build the MTG catalog SQLite file.")
    parser.add_argument("--out", type=Path, default=Path("build"), help="output directory")
    parser.add_argument(
        "--bulk-type",
        default="default_cards",
        help="Scryfall bulk dataset (default_cards, all_cards, oracle_cards)",
    )
    parser.add_argument(
        "--catalog-version",
        type=int,
        default=int(os.environ.get("CATALOG_VERSION", "1")),
        help="monotonic catalog version, normally supplied by CI",
    )
    parser.add_argument(
        "--repo",
        default=os.environ.get("GITHUB_REPOSITORY", "Tegarde/MTGProject"),
        help="owner/repo used to build the release download URL",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=REPO_ROOT / "manifest.json",
        help="where to write manifest.json (defaults to the repository root)",
    )
    parser.add_argument("--limit", type=int, help="stop after N printings (dev only)")
    parser.add_argument("--skip-images", action="store_true", help="skip the image spot-check")
    parser.add_argument(
        "--keep-source", action="store_true", help="do not delete the downloaded bulk file"
    )
    return parser.parse_args(argv)


def main(argv: Optional[list[str]] = None) -> int:
    args = parse_args(argv)
    out_dir: Path = args.out
    out_dir.mkdir(parents=True, exist_ok=True)

    sqlite_path = out_dir / f"catalog-v{args.catalog_version}.sqlite"
    gzip_path = out_dir / f"catalog-v{args.catalog_version}.sqlite.gz"
    source_path = out_dir / "source.jsonl.gz"

    log(f"locating bulk dataset {args.bulk_type!r}...")
    bulk = scryfall.find_bulk_source(args.bulk_type)
    log(f"  {bulk['name']} updated {bulk['updated_at']} ({bulk['compressed_size'] >> 20} MiB)")

    download_uri = bulk.get("jsonl_download_uri") or bulk["download_uri"]
    if not source_path.exists():
        scryfall.download(download_uri, source_path)
    else:
        log(f"  reusing existing {source_path.name}")

    conn = create_database(sqlite_path)
    try:
        conn.execute("BEGIN")
        set_count = load_sets(conn)
        load_migrations(conn)
        stats = load_cards(conn, source_path, args.limit)
        finalize(conn)

        write_meta(
            conn,
            {
                "schema_version": schema.SCHEMA_VERSION,
                "catalog_version": args.catalog_version,
                "built_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "scryfall_bulk_updated_at": bulk["updated_at"],
                "source_bulk_type": args.bulk_type,
                "card_count": stats["cards"],
                "printing_count": stats["printings"],
                "set_count": set_count,
                "partial": 1 if args.limit else 0,
            },
        )
        conn.commit()

        log("optimizing...")
        conn.executescript("PRAGMA optimize; VACUUM;")

        log("compressing...")
        scryfall.gzip_file(sqlite_path, gzip_path)

        log("validating...")
        validate(conn, gzip_path, partial=bool(args.limit), skip_images=args.skip_images)
    except ValidationError as exc:
        log(str(exc))
        return 1
    finally:
        conn.close()

    raw_mb = sqlite_path.stat().st_size / (1 << 20)
    gz_mb = gzip_path.stat().st_size / (1 << 20)
    log(f"catalog: {raw_mb:.1f} MB raw, {gz_mb:.1f} MB compressed")

    if args.limit:
        log("partial build - manifest not written, do not publish this catalog")
        return 0

    tag = f"catalog-v{args.catalog_version}"
    write_manifest(
        args.manifest,
        {
            "catalog_version": args.catalog_version,
            "schema_version": schema.SCHEMA_VERSION,
            "url": f"https://github.com/{args.repo}/releases/download/{tag}/{gzip_path.name}",
            "compressed_size": gzip_path.stat().st_size,
            "sha256": sha256(gzip_path),
            "built_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "scryfall_bulk_updated_at": bulk["updated_at"],
            "card_count": stats["cards"],
            "printing_count": stats["printings"],
            "set_count": set_count,
        },
    )

    if not args.keep_source:
        source_path.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
