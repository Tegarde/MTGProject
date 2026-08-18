# Scryfall API Summary — for MTG Collection Tracker Planning

Source: https://scryfall.com/docs/api (reviewed 2026-08-18)

This document summarizes everything relevant from the Scryfall API docs needed to design
a personal app that:
1. On first boot, fetches **all** Magic cards once and stores them in a local database.
2. On every subsequent boot, checks for **new sets** and syncs only what's new/changed.
3. Never needs to hit the live API repeatedly for normal collection-tracking use.

---

## 1. Basics & Access Rules

- **Base URL:** `https://api.scryfall.com` — HTTPS only (TLS 1.2+), UTF-8 responses.
- **Required headers on every request:**
  - `User-Agent`: must identify your app (e.g. `MTGCollectionTracker/1.0`) — don't let your HTTP library set a default one.
  - `Accept`: any value works (`*/*` is fine).
- **Formats:** Most endpoints return `json` by default; some support `csv`, `text`, or `image` (returns an HTTP 302 redirect to an image file).
- **Usage/legal restrictions** (Wizards of the Coast Fan Content Policy):
  - Can't paywall access to Scryfall data (end-users must be able to access it free/anonymously if you build a service around it).
  - Can't imply Scryfall endorsement or misuse the Scryfall name/logo.
  - Can't simply repackage/proxy raw Scryfall data without adding value.
  - Image usage restrictions: don't crop out copyright/artist name, don't distort/blur/recolor, don't add your own watermarks.
  - None of this is a blocker for a personal-use collection tracker, but worth remembering if it's ever shared.

## 2. Rate Limits (critical — drives the whole sync design)

| Endpoint(s) | Limit |
|---|---|
| `/cards/search`, `/cards/named`, `/cards/random`, `/cards/collection` | 2 req/sec (500ms between calls) |
| `/cards/manifest` | 10 req/minute |
| All other API methods (e.g. `/sets`, `/migrations`, `/bulk-data`) | 10 req/sec (100ms) |
| Files on `*.scryfall.io` (images, bulk data downloads) | **No rate limit** |

- Exceeding limits → HTTP 429, then a 30-second lockout; repeated abuse risks a permanent ban.
- Scryfall explicitly recommends caching data locally / using Bulk Data instead of looping through `/cards/search` for large numbers of cards. This directly validates the planned architecture.
- Prices update once every 24h; gameplay data (rules text, mana costs, etc.) changes infrequently — weekly or per-set-release syncing is "most likely sufficient" per Scryfall's own guidance.

## 3. Bulk Data — primary mechanism for the initial full import

- `GET /bulk-data` — lists all available bulk files as `bulk_data` objects (List response).
- `GET /bulk-data/:id` or `GET /bulk-data/:type` — fetch metadata for one file.
- Each file is a **gzipped JSONL** (`.jsonl.gz`, NOT `.tar.gz`) hosted on `data.scryfall.io` (no rate limit), regenerated roughly every 12–24 hours, with a timestamped filename each time.
- Should be streamed/decompressed line-by-line rather than loaded fully into memory (most languages support streaming gzip + line reads).

`bulk_data` object fields: `id`, `uri`, `type`, `name`, `description`, `updated_at`, `jsonl_download_uri`, `compressed_size`.

Available `type`s:

| Type | Size (approx) | Description |
|---|---|---|
| `oracle_cards` | ~23 MB | One card per Oracle ID (single representative printing per unique card) |
| `unique_artwork` | ~36 MB | One card per unique artwork |
| `default_cards` | ~74 MB | Every card object, in English or the only available language |
| `all_cards` | ~374 MB | Every printing, every language (most complete) |
| `rulings` | ~5 MB | All rulings, linked via `oracle_id` |
| `art_tags` | ~12 MB | Community illustration tags (Tagger project) |
| `oracle_tags` | ~5.6 MB | Community oracle/gameplay tags (Tagger project) |

**Recommendation for initial import:** use `default_cards` (or `all_cards` if every language/printing variant matters) as the source for "store every distinct card."

Bulk data is only regenerated every 12–24h — for anything needing fresher data than that, use the live card endpoints (still respecting rate limits) or `/cards/manifest`.

## 4. Detecting New Sets / Driving Incremental Sync

- `GET /sets` — lists all Set objects (paginated `List`). Small/cheap call, fine to run every boot.
- `GET /sets/:code` — get a single set by its 3–6 letter code.
- `GET /sets/:id` — get a single set by Scryfall UUID.

**Set object fields:**

| Field | Notes |
|---|---|
| `id` | Scryfall UUID, stable |
| `code` | 3–6 letter set code (unofficial sets often start with `p`/`t`) |
| `mtgo_code` / `arena_code` | May differ from `code` |
| `name` | English set name |
| `set_type` | See enum below |
| `released_at` | Release/first-print date |
| `block_code` / `block` | Block grouping, if any |
| `parent_set_code` | For promo/token sets tied to a parent set |
| `card_count` | Number of cards in the set |
| `digital` | True if video-game-only |
| `foil_only` / `nonfoil_only` | |
| `icon_svg_uri` | Download and cache locally rather than hotlinking (Scryfall may change it) |
| `search_uri` | Ready-made `/cards/search` URI to paginate that set's cards |

`set_type` values: `core`, `expansion`, `masters`, `eternal`, `alchemy`, `masterpiece`, `arsenal`, `from_the_vault`, `spellbook`, `premium_deck`, `duel_deck`, `draft_innovation`, `treasure_chest`, `commander`, `planechase`, `archenemy`, `vanguard`, `funny`, `starter`, `box`, `promo`, `token`, `memorabilia`, `minigame`.

**Sync strategy:** on every boot after the first, call `/sets`, diff against the sets already stored locally (by `code`/`id`, compare `card_count`/`released_at` too in case a set grows), and for anything new:
- Either re-download the relevant bulk file if `updated_at` is newer than your last sync, **or**
- Query `/cards/search?q=e:<code>&unique=prints` directly for just that set's cards (cheap — a set is small, and this respects the 2/sec limit).

- `GET /cards/manifest` (marked **NEW** in the docs; rate limit 10/min) — intended to let you detect what's changed on Scryfall without re-downloading full bulk files. Useful for a lighter-weight "anything changed since last sync?" check; exact response schema wasn't confirmed from the docs during this research pass — verify the live page before relying on it.

## 5. Card Migrations — keeping the local DB consistent long-term

`GET /migrations` — paginated `List` of `migration` objects. Since cards are stored by Scryfall `id`, and Scryfall occasionally corrects mistakes (duplicate entries, cards that never actually got printed, mis-mapped prints), this endpoint is how you keep a long-lived local copy from accumulating stale/wrong rows.

**Migration strategies:**

| Strategy | Meaning |
|---|---|
| `merge` | Replace `old_scryfall_id` with `new_scryfall_id` everywhere in your records |
| `delete` | `old_scryfall_id` is invalid/discarded with no replacement — purge or flag it |

**Migration object fields:** `id`, `uri`, `performed_at`, `migration_strategy`, `old_scryfall_id`, `new_scryfall_id` (nullable, only for merges), `note`, `metadata` (human-readable context: original `name`, `set_code`, `lang`, `collector_number`, etc.).

**Recommendation:** on each incremental sync (or periodically), fetch `/migrations` and apply any migrations newer than the last check to the local DB (update foreign keys / collection entries pointing at merged/deleted card IDs).

## 6. Card Object — the core data model to persist

Cards are Scryfall's most complex object. Fields are grouped as follows.

### Identity fields
- `id` — Scryfall UUID, unique **per printing**.
- `oracle_id` — stable across reprints of the same card; groups all printings of one card. (Absent for `reversible_card` layout — appears per-face instead.)
- `lang` — language code for this printing.
- External IDs (all optional/nullable): `arena_id`, `mtgo_id`, `mtgo_foil_id`, `multiverse_ids[]`, `tcgplayer_id`, `tcgplayer_etched_id`, `cardmarket_id`, `resource_id`.
- `uri`, `scryfall_uri`, `rulings_uri`, `prints_search_uri` — links back to the API/site.

### Gameplay fields
`name`, `mana_cost`, `cmc`, `type_line`, `oracle_text`, `power`/`toughness`/`loyalty`/`defense`, `colors`, `color_identity`, `color_indicator`, `keywords[]`, `legalities` (per-format: `legal`/`not_legal`/`restricted`/`banned`), `reserved` (Reserved List flag), `game_changer` (Commander Game Changer list), `produced_mana`, `edhrec_rank`, `penny_rank`, `hand_modifier`/`life_modifier` (Vanguard cards).

### Print fields (unique per specific printing)
`set`/`set_id`/`set_name`/`set_type`, `collector_number`, `rarity` (`common`/`uncommon`/`rare`/`special`/`mythic`/`bonus`), `artist`/`artist_ids[]`, `released_at`, `image_uris` (`small`/`normal`/`large`/`png`/`art_crop`/`border_crop`/`thumb`/etc. — see Card Imagery docs), `finishes[]` (`nonfoil`/`foil`/`etched`), `prices` (`usd`/`usd_foil`/`usd_etched`/`eur`/`eur_foil`/`eur_etched`/`tix` — **daily estimates only, "dangerously stale after 24h," not for storefronts**), `frame`, `frame_effects[]`, `border_color`, `promo`/`promo_types[]`, `full_art`, `variation`/`variation_of`, `security_stamp`, `watermark`, `related_uris`, `purchase_uris`, `flavor_text`/`flavor_name`, `card_back_id`, `digital`, `oversized`, `textless`, `story_spotlight`, `content_warning`, `image_status`, `highres_image`, `booster`, `reprint`.

### Multi-face cards
Split / flip / transform / modal-DFC cards are a **single card object** with a `card_faces[]` array of Card Face objects, each with its own `name`, `mana_cost`, `oracle_text`, `power`/`toughness`, `colors`, `image_uris` (present per-face only when the card is double-sided; otherwise `image_uris` lives on the parent object).

### Related cards
`all_parts[]` — lightweight `related_card` objects (`id`, `component` = `token`/`meld_part`/`meld_result`/`combo_piece`, `name`, `type_line`, `uri`) for cards closely tied to this one (tokens it makes, meld pairs, combo pieces referenced by name).

**Schema implication:** a `cards` table keyed by Scryfall `id`, with `oracle_id` indexed for grouping reprints, a child `card_faces` table for multi-face cards, and a `related_cards` join table.

## 7. Other Endpoints (secondary — not needed for the bulk sync, but useful for later features)

- `POST /cards/collection` — batch lookup up to 75 cards per call by `id`/`mtgo_id`/`multiverse_id`/`oracle_id`/`illustration_id`/`name`/`name+set`/`collector_number+set`. Rate limit 2/sec. Returns a `List` with `not_found[]` for unmatched entries. Useful later for reconciling an import list against the API if ever needed (though with the full local DB this shouldn't be necessary).
- `GET /cards/named?exact=` or `?fuzzy=` — single-card lookup by name (2/sec), designed for bots — not needed once the local DB exists.
- `GET /cards/search` — Scryfall's full search syntax via `q`, plus `unique` (`cards`/`art`/`prints`), `order`, `dir`, `include_extras`, `include_multilingual`, `include_variations`, `page`. 2/sec limit. Useful for fetching a single new set's cards during incremental sync.
- `GET /cards/autocomplete`, `/cards/random`, `/cards/:code/:number(/:lang)`, `/cards/multiverse/:id`, `/cards/mtgo/:id`, `/cards/arena/:id`, `/cards/tcgplayer/:id`, `/cards/cardmarket/:id`, `/cards/:id` — various single-card lookups, all secondary to the bulk-import approach.
- `GET /cards/:id/rulings` (Rulings) — also available in bulk as the `rulings` bulk file.
- `GET /card-symbols` — mana symbol metadata/appearance.
- `GET /catalogs/*` — word lists (card names, artist names, etc.), also derivable from bulk data.
- `GET /tags` — Tagger community tags; also available as `art_tags`/`oracle_tags` bulk files.

## 8. Shared Response Types

**List object** (wraps paginated results):
```json
{
  "object": "list",
  "data": [ /* ... */ ],
  "has_more": false,
  "next_page": "https://api.scryfall.com/...?page=2",
  "total_cards": 123,
  "warnings": [ "..." ]
}
```

**Error object** (standard for 4xx/5xx responses):
```json
{
  "object": "error",
  "code": "bad_request",
  "status": 400,
  "details": "All of your terms were ignored.",
  "type": null,
  "warnings": [ "..." ]
}
```

## 9. Implications for This App's Design

1. **First boot (full import):**
   - Download the `default_cards` (or `all_cards`) bulk JSONL file via `/bulk-data` → `jsonl_download_uri` (no rate limit on `data.scryfall.io`).
   - Stream-decompress and parse line-by-line; upsert each card into the local DB keyed by `id`, indexed by `oracle_id`.
   - Also pull `/sets` (store all sets with their `code`/`id`/`released_at`/`card_count`) and the `rulings` bulk file.
2. **Every subsequent boot (incremental sync):**
   - Call `/sets`; diff against locally stored sets (new `code`, or changed `card_count`/`released_at`) to detect new releases.
   - For each new/changed set, either re-pull the relevant bulk file (if its `updated_at` is newer than the last full sync) or call `/cards/search?q=e:<code>&unique=prints` directly (well within the 2/sec limit given a set's small card count).
   - Call `/migrations` for anything newer than the last check and apply `merge`/`delete` operations to keep local card references valid.
3. **Normal runtime (collection tracking):** no live API calls needed at all — everything is served from the local database, consistent with Scryfall's own guidance and the unrestricted `*.scryfall.io` file hosting.
4. **Rate-limit safety net:** even though the sync design minimizes API calls, the app should still enforce local throttling (≥500ms between `/cards/search` calls, ≥100ms for other endpoints) and back off on HTTP 429 rather than retrying immediately.
