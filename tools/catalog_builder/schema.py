"""SQL schema for the MTG catalog.

This module is the executable mirror of ``planning/02-catalog-schema.md``.
Any change here is a breaking change and must bump ``SCHEMA_VERSION``.
"""

from __future__ import annotations

SCHEMA_VERSION = 1

# Tables are created before the bulk insert; indexes and FTS are created after,
# because building an index incrementally over 113k inserts is far slower than
# building it once at the end.
TABLES = """
CREATE TABLE meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE sets (
    code             TEXT PRIMARY KEY,
    scryfall_id      TEXT NOT NULL,
    name             TEXT NOT NULL,
    set_type         TEXT NOT NULL,
    released_at      TEXT,
    card_count       INTEGER NOT NULL,
    parent_set_code  TEXT,
    block_code       TEXT,
    block            TEXT,
    digital          INTEGER NOT NULL,
    foil_only        INTEGER NOT NULL,
    nonfoil_only     INTEGER NOT NULL,
    icon_svg_uri     TEXT
);

CREATE TABLE cards (
    oracle_id            TEXT PRIMARY KEY,
    name                 TEXT NOT NULL,
    mana_cost            TEXT,
    cmc                  REAL NOT NULL,
    type_line            TEXT,
    oracle_text          TEXT,
    power                TEXT,
    toughness            TEXT,
    loyalty              TEXT,
    defense              TEXT,
    colors               TEXT,
    color_identity       TEXT NOT NULL,
    keywords             TEXT,
    produced_mana        TEXT,
    layout               TEXT NOT NULL,
    legalities           TEXT NOT NULL,
    reserved             INTEGER NOT NULL,
    game_changer         INTEGER NOT NULL,
    edhrec_rank          INTEGER,
    face_count           INTEGER NOT NULL,
    default_printing_id  TEXT NOT NULL
);

CREATE TABLE card_faces (
    oracle_id    TEXT NOT NULL,
    face_index   INTEGER NOT NULL,
    name         TEXT NOT NULL,
    mana_cost    TEXT,
    type_line    TEXT,
    oracle_text  TEXT,
    power        TEXT,
    toughness    TEXT,
    loyalty      TEXT,
    defense      TEXT,
    colors       TEXT,
    has_image    INTEGER NOT NULL,
    PRIMARY KEY (oracle_id, face_index)
);

CREATE TABLE printings (
    scryfall_id       TEXT PRIMARY KEY,
    oracle_id         TEXT NOT NULL,
    set_code          TEXT NOT NULL,
    collector_number  TEXT NOT NULL,
    rarity            TEXT NOT NULL,
    finishes          TEXT NOT NULL,
    lang              TEXT NOT NULL,
    artist            TEXT,
    released_at       TEXT,
    image_status      TEXT NOT NULL,
    border_color      TEXT,
    frame             TEXT,
    promo             INTEGER NOT NULL,
    full_art          INTEGER NOT NULL,
    textless          INTEGER NOT NULL,
    variation         INTEGER NOT NULL,
    oversized         INTEGER NOT NULL,
    digital           INTEGER NOT NULL,
    booster           INTEGER NOT NULL,
    two_sided_image   INTEGER NOT NULL
);

CREATE TABLE migrations (
    id                TEXT PRIMARY KEY,
    performed_at      TEXT NOT NULL,
    strategy          TEXT NOT NULL,
    old_scryfall_id   TEXT NOT NULL,
    new_scryfall_id   TEXT,
    note              TEXT
);
"""

INDEXES = """
CREATE INDEX idx_sets_released     ON sets (released_at DESC);
CREATE INDEX idx_sets_type         ON sets (set_type);
CREATE INDEX idx_cards_name        ON cards (name COLLATE NOCASE);
CREATE INDEX idx_cards_cmc         ON cards (cmc);
CREATE INDEX idx_cards_edhrec      ON cards (edhrec_rank);
CREATE INDEX idx_printings_oracle  ON printings (oracle_id);
CREATE INDEX idx_printings_set     ON printings (set_code, collector_number);
CREATE INDEX idx_printings_rarity  ON printings (rarity);
CREATE INDEX idx_printings_artist  ON printings (artist COLLATE NOCASE);
CREATE INDEX idx_migrations_old    ON migrations (old_scryfall_id);
"""

# External-content FTS5: the text is not duplicated on disk, the index points
# back at rows in `cards` via rowid.
FTS = """
CREATE VIRTUAL TABLE cards_fts USING fts5 (
    name,
    oracle_text,
    type_line,
    content = 'cards',
    content_rowid = 'rowid',
    tokenize = "unicode61 remove_diacritics 2"
);

INSERT INTO cards_fts (rowid, name, oracle_text, type_line)
    SELECT rowid, name, oracle_text, type_line FROM cards;
"""

CARD_COLUMNS = (
    "oracle_id", "name", "mana_cost", "cmc", "type_line", "oracle_text",
    "power", "toughness", "loyalty", "defense", "colors", "color_identity",
    "keywords", "produced_mana", "layout", "legalities", "reserved",
    "game_changer", "edhrec_rank", "face_count", "default_printing_id",
)

FACE_COLUMNS = (
    "oracle_id", "face_index", "name", "mana_cost", "type_line", "oracle_text",
    "power", "toughness", "loyalty", "defense", "colors", "has_image",
)

PRINTING_COLUMNS = (
    "scryfall_id", "oracle_id", "set_code", "collector_number", "rarity",
    "finishes", "lang", "artist", "released_at", "image_status", "border_color",
    "frame", "promo", "full_art", "textless", "variation", "oversized",
    "digital", "booster", "two_sided_image",
)

SET_COLUMNS = (
    "code", "scryfall_id", "name", "set_type", "released_at", "card_count",
    "parent_set_code", "block_code", "block", "digital", "foil_only",
    "nonfoil_only", "icon_svg_uri",
)

MIGRATION_COLUMNS = (
    "id", "performed_at", "strategy", "old_scryfall_id", "new_scryfall_id", "note",
)


def insert_sql(table: str, columns: "tuple[str, ...]") -> str:
    placeholders = ", ".join("?" * len(columns))
    return f"INSERT OR REPLACE INTO {table} ({', '.join(columns)}) VALUES ({placeholders})"
