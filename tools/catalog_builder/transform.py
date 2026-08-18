"""Transform Scryfall card objects into catalog rows.

Pure functions, no I/O, so the awkward cases documented in
``planning/03-catalog-builder.md`` §5 can be unit tested directly.
"""

from __future__ import annotations

import json
from typing import Any, Optional

# Layouts where the physical card has a distinct back face with its own image.
# split/flip/adventure have multiple faces but only one printed side.
TWO_SIDED_LAYOUTS = {"transform", "modal_dfc", "double_faced_token", "reversible_card", "art_series"}

_IMAGE_STATUS_RANK = {"highres_scan": 0, "lowres": 1, "placeholder": 2, "missing": 3}
_SET_TYPE_RANK = {"core": 0, "expansion": 0, "masters": 1, "draft_innovation": 1, "commander": 2}


def _json_list(value: Any) -> Optional[str]:
    return json.dumps(value, separators=(",", ":")) if value else None


def _bool(value: Any) -> int:
    return 1 if value else 0


def _released_ordinal(released_at: Optional[str]) -> int:
    """'2024-03-15' -> 20240315. Unknown dates sort oldest."""
    if not released_at:
        return 0
    try:
        return int(released_at.replace("-", ""))
    except ValueError:
        return 0


def resolve_oracle_id(card: dict[str, Any]) -> Optional[str]:
    """Cards with layout 'reversible_card' carry oracle_id on each face, not the root."""
    oracle_id = card.get("oracle_id")
    if oracle_id:
        return oracle_id
    for face in card.get("card_faces") or []:
        if face.get("oracle_id"):
            return face["oracle_id"]
    return None


def printing_rank(card: dict[str, Any]) -> tuple:
    """Sort key for choosing a card's default printing. Lower is better.

    Ordering, per planning/02-catalog-schema.md §2: image quality, then a plain
    non-promo printing, then a core/expansion set, then most recent.
    """
    return (
        _IMAGE_STATUS_RANK.get(card.get("image_status", ""), 4),
        _bool(card.get("promo")),
        _bool(card.get("variation")),
        _bool(card.get("digital")),
        _bool(card.get("oversized")),
        _bool(card.get("textless")),
        _SET_TYPE_RANK.get(card.get("set_type", ""), 3),
        -_released_ordinal(card.get("released_at")),
        card.get("collector_number", ""),
    )


def has_back_image(card: dict[str, Any]) -> bool:
    faces = card.get("card_faces") or []
    if card.get("layout") not in TWO_SIDED_LAYOUTS:
        return False
    return len(faces) >= 2 and bool(faces[1].get("image_uris"))


def to_printing_row(card: dict[str, Any], oracle_id: str) -> tuple:
    """Slim per-printing row. Deliberately carries no rules text and no image URLs."""
    return (
        card["id"],
        oracle_id,
        card["set"],
        card.get("collector_number", ""),
        card.get("rarity", "common"),
        json.dumps(card.get("finishes") or ["nonfoil"], separators=(",", ":")),
        card.get("lang", "en"),
        card.get("artist"),
        card.get("released_at"),
        card.get("image_status", "missing"),
        card.get("border_color"),
        card.get("frame"),
        _bool(card.get("promo")),
        _bool(card.get("full_art")),
        _bool(card.get("textless")),
        _bool(card.get("variation")),
        _bool(card.get("oversized")),
        _bool(card.get("digital")),
        _bool(card.get("booster")),
        _bool(has_back_image(card)),
    )


def to_card_row(card: dict[str, Any], oracle_id: str, default_printing_id: str) -> tuple:
    """Oracle-level row.

    For multi-faced layouts several of these fields are absent at the root and
    live on the faces instead; that is expected and handled by card_faces.
    """
    faces = card.get("card_faces") or []
    return (
        oracle_id,
        card.get("name", ""),
        card.get("mana_cost"),
        float(card.get("cmc") or 0.0),
        card.get("type_line"),
        card.get("oracle_text"),
        card.get("power"),
        card.get("toughness"),
        card.get("loyalty"),
        card.get("defense"),
        _json_list(card.get("colors")),
        json.dumps(card.get("color_identity") or [], separators=(",", ":")),
        _json_list(card.get("keywords")),
        _json_list(card.get("produced_mana")),
        card.get("layout", "normal"),
        json.dumps(card.get("legalities") or {}, separators=(",", ":")),
        _bool(card.get("reserved")),
        _bool(card.get("game_changer")),
        card.get("edhrec_rank"),
        len(faces),
        default_printing_id,
    )


def to_face_rows(card: dict[str, Any], oracle_id: str) -> list[tuple]:
    rows = []
    for index, face in enumerate(card.get("card_faces") or []):
        rows.append(
            (
                oracle_id,
                index,
                face.get("name", ""),
                face.get("mana_cost"),
                face.get("type_line"),
                face.get("oracle_text"),
                face.get("power"),
                face.get("toughness"),
                face.get("loyalty"),
                face.get("defense"),
                _json_list(face.get("colors")),
                _bool(face.get("image_uris")),
            )
        )
    return rows


def to_set_row(mtg_set: dict[str, Any]) -> tuple:
    return (
        mtg_set["code"],
        mtg_set["id"],
        mtg_set.get("name", ""),
        mtg_set.get("set_type", "expansion"),
        mtg_set.get("released_at"),
        int(mtg_set.get("card_count") or 0),
        mtg_set.get("parent_set_code"),
        mtg_set.get("block_code"),
        mtg_set.get("block"),
        _bool(mtg_set.get("digital")),
        _bool(mtg_set.get("foil_only")),
        _bool(mtg_set.get("nonfoil_only")),
        mtg_set.get("icon_svg_uri"),
    )


def to_migration_row(migration: dict[str, Any]) -> tuple:
    return (
        migration["id"],
        migration.get("performed_at", ""),
        migration.get("migration_strategy", ""),
        migration.get("old_scryfall_id", ""),
        migration.get("new_scryfall_id"),
        migration.get("note"),
    )


def image_url(scryfall_id: str, size: str = "normal", face: str = "front") -> str:
    """Derived image URL. Verified against the live CDN; see 02-catalog-schema.md §5."""
    ext = "png" if size == "png" else "jpg"
    return (
        f"https://cards.scryfall.io/{size}/{face}/"
        f"{scryfall_id[0]}/{scryfall_id[1]}/{scryfall_id}.{ext}"
    )
