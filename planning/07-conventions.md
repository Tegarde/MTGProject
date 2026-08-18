# 07 — Conventions

Applies to every component. Read before writing code.

---

## 1. Repository layout

```
planning/                    these docs
tools/catalog_builder/       Python builder
.github/workflows/           CI
app/                         Flutter app
manifest.json                catalog pointer, committed by CI
```

## 2. Python (`tools/`)

- **Python 3.9+**, standard library only. Do not add a `requirements.txt`. If a dependency ever
  becomes genuinely unavoidable, document why in `03-catalog-builder.md`.
- `from __future__ import annotations` at the top of every module, so `list[str]` style hints work
  on 3.9.
- Type-hint all function signatures.
- Format and lint with `ruff` (line length 100). It is not a runtime dependency, so it is not
  vendored — run it locally.
- Scripts are executable modules with a `main()` and an `if __name__ == "__main__":` guard.
- Use `argparse`, never `sys.argv` parsing by hand.
- Log progress to stderr with counts, not progress bars — the output is read in CI logs.
- Fail loudly. A builder that publishes a bad catalog is worse than one that crashes.

## 3. Dart / Flutter (`app/`)

- Follow `flutter_lints`; keep `analysis_options.yaml` at the defaults plus
  `prefer_single_quotes` and `require_trailing_commas`.
- `models/` contains plain Dart classes with **no** framework imports — no `flutter`, no `sqlite3`,
  no `cloud_firestore`. They must be constructible in a plain Dart test.
- Every model gets `fromRow` (SQLite) and/or `fromFirestore`/`toFirestore` factories. Never let a
  raw `Map` escape the data layer.
- Data access goes through DAOs (catalog) or repositories (Firestore). Widgets never issue queries.
- Prefer `const` constructors everywhere they are possible.
- Async work that touches the database in a loop belongs in an isolate.

## 4. Naming

| Thing | Convention | Example |
|---|---|---|
| Dart files | `snake_case.dart` | `card_detail_screen.dart` |
| Dart classes | `PascalCase` | `CollectionEntry` |
| Python files | `snake_case.py` | `build_catalog.py` |
| SQLite tables/columns | `snake_case` | `default_printing_id` |
| Firestore fields | `camelCase` | `printingId` |
| Scryfall IDs in code | `printingId` (per-printing), `oracleId` (per-card) | never bare `id` |

The SQLite/Firestore casing split is deliberate: it matches each platform's idiom, and the mismatch
is confined to the model factory methods.

## 5. Secrets

- **Never commit:** Android keystores, `google-services.json` with a production config, service
  account JSON, GitHub PATs, API keys.
- The client app has no secrets to protect beyond the Firebase config, which is public by design —
  security comes from Firestore rules, not from hiding the config.
- CI uses the automatically provided `GITHUB_TOKEN`. Do not create a PAT for the catalog workflow.
- **Never embed a token in the app to trigger a GitHub workflow.** See `01-architecture.md` §5.

## 6. External API etiquette

Every request to Scryfall, from any component:

```
User-Agent: MTGCollectionTracker/1.0
Accept: */*
```

Rate limits: 2 req/s for `/cards/*` search endpoints, 10 req/s elsewhere on `api.scryfall.com`,
unmetered on `*.scryfall.io`. Back off for 30 seconds on an HTTP 429 — never retry immediately.

The app makes **no** calls to `api.scryfall.com` at all. Only the builder does.

## 7. Git

- Conventional commits: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`.
- The catalog `.sqlite` and `.sqlite.gz` files are build artifacts — gitignore them. They are
  distributed through GitHub Releases, not the repository.
- `manifest.json` **is** committed; CI updates it.

## 8. Testing

- **Builder:** run against `--limit 5000` and assert the validation checks in
  `03-catalog-builder.md` §6 pass. Add unit tests for the multi-face and missing-`oracle_id`
  parsing quirks in §5 — those are where bugs live.
- **App:** unit-test model factories and pure logic (deck legality, owned-vs-needed aggregation,
  FTS query escaping, natural sort). Widget tests for the bootstrap state machine. No integration
  tests against live Firebase.

## 9. Things that will be tempting and are wrong

- Putting card data in Firestore. It does not fit in the free tier — this is why the architecture
  exists.
- Calling `api.scryfall.com` from the app "just for this one lookup". The catalog has it.
- Storing image URLs in the catalog. They are derived; storing them adds ~10 MB.
- Adding prices. They are stale in 24 hours and force daily rebuilds.
- Casting `power`, `toughness`, or `collector_number` to a number. They contain `*`, `1+*`, `12a`.
- Using `colors` where `color_identity` is required, in Commander deck validation.
- Writing to Firestore on every keystroke or quantity tap. Debounce.
