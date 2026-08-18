"""Unit tests for the transform layer.

Covers the Scryfall data quirks listed in planning/03-catalog-builder.md §5 —
these are where the bugs are.

Run:  python -m unittest discover tools/catalog_builder
"""

from __future__ import annotations

import json
import unittest

import transform


def card(**overrides):
    base = {
        "id": "7673784e-db4b-43a1-8d55-1bb9fc1e284f",
        "oracle_id": "4457ed35-7c10-48c8-9776-456485fdf070",
        "name": "Lightning Bolt",
        "layout": "normal",
        "set": "lea",
        "set_type": "core",
        "collector_number": "161",
        "rarity": "common",
        "lang": "en",
        "cmc": 1.0,
        "color_identity": ["R"],
        "legalities": {"modern": "legal"},
        "image_status": "highres_scan",
        "finishes": ["nonfoil"],
        "released_at": "1993-08-05",
    }
    base.update(overrides)
    return base


class ResolveOracleId(unittest.TestCase):
    def test_uses_root_when_present(self):
        self.assertEqual(
            transform.resolve_oracle_id(card()), "4457ed35-7c10-48c8-9776-456485fdf070"
        )

    def test_falls_back_to_face_for_reversible_cards(self):
        # layout 'reversible_card' has no root oracle_id; it lives on each face.
        c = card(layout="reversible_card", card_faces=[{"oracle_id": "face-oracle"}, {}])
        c.pop("oracle_id")
        self.assertEqual(transform.resolve_oracle_id(c), "face-oracle")

    def test_returns_none_when_unresolvable(self):
        c = card()
        c.pop("oracle_id")
        self.assertIsNone(transform.resolve_oracle_id(c))


class NonNumericFields(unittest.TestCase):
    def test_star_power_survives_as_text(self):
        row = transform.to_card_row(card(power="1+*", toughness="*"), "o", "p")
        columns = dict(zip(transform_card_columns(), row))
        self.assertEqual(columns["power"], "1+*")
        self.assertEqual(columns["toughness"], "*")

    def test_alphanumeric_collector_number_survives(self):
        row = transform.to_printing_row(card(collector_number="101★"), "o")
        self.assertEqual(row[3], "101★")


class MultiFace(unittest.TestCase):
    def test_transform_card_has_back_image(self):
        c = card(
            layout="transform",
            card_faces=[
                {"name": "Delver of Secrets", "image_uris": {"normal": "..."}},
                {"name": "Insectile Aberration", "image_uris": {"normal": "..."}},
            ],
        )
        self.assertTrue(transform.has_back_image(c))
        self.assertEqual(transform.to_printing_row(c, "o")[-1], 1)

    def test_split_card_is_one_physical_side(self):
        # Fire // Ice has two faces but only one printed side, so no back image.
        c = card(layout="split", card_faces=[{"name": "Fire"}, {"name": "Ice"}])
        self.assertFalse(transform.has_back_image(c))
        self.assertEqual(transform.to_printing_row(c, "o")[-1], 0)

    def test_face_rows_are_indexed_in_order(self):
        c = card(
            layout="modal_dfc",
            card_faces=[
                {"name": "Front", "mana_cost": "{B}", "image_uris": {}},
                {"name": "Back", "mana_cost": ""},
            ],
        )
        rows = transform.to_face_rows(c, "o")
        self.assertEqual([r[1] for r in rows], [0, 1])
        self.assertEqual([r[2] for r in rows], ["Front", "Back"])

    def test_face_count_recorded_on_card(self):
        c = card(layout="split", card_faces=[{"name": "Fire"}, {"name": "Ice"}])
        columns = dict(zip(transform_card_columns(), transform.to_card_row(c, "o", "p")))
        self.assertEqual(columns["face_count"], 2)

    def test_single_faced_card_has_no_faces(self):
        self.assertEqual(transform.to_face_rows(card(), "o"), [])


class DefaultPrintingRank(unittest.TestCase):
    def test_prefers_highres_over_placeholder(self):
        good = transform.printing_rank(card(image_status="highres_scan"))
        bad = transform.printing_rank(card(image_status="placeholder"))
        self.assertLess(good, bad)

    def test_prefers_non_promo(self):
        plain = transform.printing_rank(card(promo=False))
        promo = transform.printing_rank(card(promo=True))
        self.assertLess(plain, promo)

    def test_prefers_more_recent_release(self):
        newer = transform.printing_rank(card(released_at="2024-01-01"))
        older = transform.printing_rank(card(released_at="1993-08-05"))
        self.assertLess(newer, older)

    def test_missing_release_date_sorts_last(self):
        dated = transform.printing_rank(card(released_at="1993-08-05"))
        undated = transform.printing_rank(card(released_at=None))
        self.assertLess(dated, undated)


class MissingFields(unittest.TestCase):
    def test_optional_fields_default_safely(self):
        sparse = {
            "id": "abcdef00-0000-0000-0000-000000000000",
            "name": "Nameless",
            "set": "xxx",
            "lang": "en",
            "layout": "normal",
            "color_identity": [],
            "legalities": {},
        }
        row = transform.to_printing_row(sparse, "o")
        self.assertEqual(row[4], "common")  # rarity default
        self.assertEqual(json.loads(row[5]), ["nonfoil"])  # finishes default
        self.assertEqual(row[9], "missing")  # image_status default

        columns = dict(zip(transform_card_columns(), transform.to_card_row(sparse, "o", "p")))
        self.assertEqual(columns["cmc"], 0.0)
        self.assertIsNone(columns["colors"])
        self.assertEqual(columns["color_identity"], "[]")


class ImageUrl(unittest.TestCase):
    def test_matches_verified_cdn_pattern(self):
        self.assertEqual(
            transform.image_url("7673784e-db4b-43a1-8d55-1bb9fc1e284f"),
            "https://cards.scryfall.io/normal/front/7/6/"
            "7673784e-db4b-43a1-8d55-1bb9fc1e284f.jpg",
        )

    def test_png_uses_png_extension(self):
        self.assertTrue(transform.image_url("abcdef00-1111", "png").endswith(".png"))

    def test_back_face(self):
        self.assertIn("/back/", transform.image_url("abcdef00-1111", "normal", "back"))


def transform_card_columns():
    import schema

    return schema.CARD_COLUMNS


if __name__ == "__main__":
    unittest.main()
