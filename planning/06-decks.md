# 06 — Deck Building

Depends on the catalog (`02-catalog-schema.md`), the collection (`04-firestore-model.md` §3), and
the deck document shape (`04-firestore-model.md` §4). Build this **after** collection sync works.

---

## 1. Scope

A deck is a named list of cards with quantities, split across three boards. Decks reference cards
by `oracleId` — a deck is a list of *cards*, not of specific printings. An optional `printingId`
records which printing the user intends to use, purely for display.

Decks are **independent of the collection**. Adding a card to a deck does not require owning it;
the app shows what is owned versus needed rather than blocking.

## 2. Formats

```dart
enum DeckFormat { standard, pioneer, modern, legacy, vintage, commander, pauper, brawl, casual }
```

Format drives legality checks and deck-size rules:

| Format | Deck size | Copy limit | Commander |
|---|---|---|---|
| commander | exactly 100 incl. commander | 1 (except basic lands) | 1, or 2 with Partner |
| brawl | exactly 60 incl. commander | 1 | 1 |
| standard/pioneer/modern/legacy/vintage/pauper | 60+ | 4 | — |
| casual | any | unenforced | — |

Basic lands (`type_line` contains `Basic Land`) are exempt from every copy limit.

## 3. Legality

`cards.legalities` is a JSON object mapping format name to `legal`, `not_legal`, `restricted`, or
`banned`. Parse it and check against the deck's format.

Commander adds a rule the `legalities` field does not cover: **every card's `color_identity` must
be a subset of the commander's `color_identity`**. Use `cards.color_identity`, not `cards.colors` —
they differ, and this is the single most common deck-builder bug. A card with `{R}` in its rules
text but no red mana symbol in its cost still has red colour identity.

Legality issues are shown as **warnings, not blocks**. This is a personal tracker; the user may be
building something for a format the app does not model.

## 4. Screens

**Deck list** — name, format, colour identity pips, card count, last updated. From the deck
summaries stream.

**Deck editor**

- Board tabs: Main / Side / Maybe.
- Grouped by card type (Creature, Instant, Sorcery, Artifact, Enchantment, Planeswalker, Land)
  with subtotals.
- Rows show quantity stepper, name, mana cost, and an owned indicator.
- Add cards through the same search widget as the main search screen.
- Commander slot for commander/brawl formats, with a validity check that the chosen card is a
  legendary creature or explicitly says it can be a commander.

**Deck stats panel**

- Mana curve histogram by `cmc` (lands excluded).
- Colour breakdown from `color_identity`.
- Type breakdown.
- Average `cmc`.
- All computed client-side from the catalog. No stored aggregates.

## 5. Owned vs. needed

The feature that ties decks to the collection.

For each deck entry, sum the quantities of all collection entries sharing that `oracleId` —
**any printing counts**, since a Lightning Bolt from any set plays the same. Compare against the
deck's required quantity.

```
needed = max(0, deckQuantity - ownedQuantity)
```

Show a per-deck summary ("You own 87 of 100 cards") and a "Missing cards" view listing the
shortfall. Cards can be owned by several entries at once (different finishes or conditions), so
always aggregate before comparing.

Because collection entries denormalize `oracleId` (see `04-firestore-model.md` §3), this is a
client-side group-by over already-loaded data — no extra reads.

## 6. Saving

The card list is an array inside the deck document, so any edit rewrites the whole document.
Therefore:

- **Debounce saves by ~1 second** rather than writing on every quantity tap. A 4-copy adjustment
  should cost one write, not four.
- Keep the working deck in memory and flush on debounce, on navigating away, and on app pause.
- Set `updatedAt` on every write.
- Recompute `colorIdentity` on save so the deck list can render pips without loading full decks.

Against a 20k writes/day quota this is comfortable, but unthrottled per-keystroke writes are not.

## 7. Deliberately out of scope for v1

- Import/export in any text format
- Playtest / sample-hand simulation
- Price totals for missing cards
- Deck sharing or public links
- Suggestions or auto-build
