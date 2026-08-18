# 00 — Project Overview

**Project:** MTG Collection Tracker — a personal Magic: The Gathering collection manager.

**Audience for these docs:** AI coding agents implementing the project. Read `01-architecture.md`
next, then the doc for whichever component you are building.

---

## 1. Goal

A single-user app that lets one person catalogue the Magic cards they physically own, browse and
search the full card database offline, and build decks from that collection. It runs on **Android**
and **Windows** from one Flutter codebase.

## 2. Core idea

The full Magic card database (~110k printings) is **not** fetched from the Scryfall API at runtime.
Instead:

1. A scheduled **Python builder** downloads Scryfall's bulk data once a week, transforms it into a
   compact **SQLite catalog file**, and publishes it to GitHub Releases.
2. The app **downloads that catalog file once** and reads it locally. Searching, browsing, and
   picking a printing are all local SQLite queries — instant, offline, and zero API calls.
3. Only the user's **personal data** (which cards they own, and their decks) lives in the cloud,
   in Firestore. That data is tiny — a few thousand small documents at most.

This keeps the app free to run forever, fast, and compliant with Scryfall's explicit guidance to
cache locally rather than loop over the API.

## 3. Non-goals for v1

Deliberately out of scope. Do not implement these unless asked:

- **Card prices / collection value.** Scryfall calls its prices "dangerously stale after 24h" and
  including them would force daily catalog rebuilds.
- **Multi-user / sharing.** Single user, one Firebase account.
- **Card scanning** via camera or barcode.
- **CSV import/export** from other collection tools.
- **Wishlist / want list.**
- **Non-English card images.** Language is recorded on a collection entry, but the catalog holds
  English printings only.
- **iOS, macOS, Linux, web** builds.

## 4. Hard constraints

| Constraint | Consequence |
|---|---|
| Everything must stay on free tiers | No always-on server. Firebase stays on the Spark plan. |
| Firestore Spark: 20k writes/day, 50k reads/day, 1 GiB | Card catalog must **never** go in Firestore. |
| Scryfall rate limits (2 req/s search, 10 req/s other) | Only the builder talks to the API, and it uses bulk files. |
| `*.scryfall.io` files are unmetered | Card images are always fetched from there, never proxied. |
| Firebase on Windows is officially beta | All Firebase access must sit behind an interface — see `04-firestore-model.md` §6. |

## 5. Component map

| Component | Language | Location | Doc |
|---|---|---|---|
| Catalog builder | Python 3.9+ | `tools/catalog_builder/` | `03-catalog-builder.md` |
| Catalog CI workflow | YAML | `.github/workflows/` | `03-catalog-builder.md` §7 |
| Catalog file format | SQLite | *(build artifact)* | `02-catalog-schema.md` |
| Mobile + desktop app | Dart / Flutter | `app/` | `05-flutter-app.md` |
| Cloud data model | Firestore | *(Firebase console)* | `04-firestore-model.md` |
| Deck feature | Dart / Flutter | `app/` | `06-decks.md` |

## 6. Reference material

- `scryfall-api-summary.md` — condensed Scryfall API documentation. The bulk-data, set, and
  card-object sections drive the builder.
- Official API docs: <https://scryfall.com/docs/api>

## 7. Build order

Phases are ordered by dependency. `02-catalog-schema.md` is the contract between the builder and
the app, so it must be settled before either side is written.

1. **P0** — Planning docs *(this folder)*
2. **P1** — Catalog builder + CI workflow
3. **P2** — Flutter shell, catalog download and open
4. **P3** — Browse, search, card images
5. **P4** — Firebase auth + collection sync
6. **P5** — Decks
7. **P6** — Windows and Android packaging
