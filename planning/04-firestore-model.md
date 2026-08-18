# 04 — Firestore Data Model

Firestore stores **only** the user's personal data: which cards they own, and their decks. The card
catalog must never be written here — see `00-overview.md` §4.

Plan: **Firebase Spark (free)**. Limits that matter: 1 GiB stored, 50k document reads/day,
20k writes/day, 20k deletes/day.

---

## 1. Collection layout

```
users/{uid}
├── profile              (single document, user settings)
├── collection/{entryId} (one document per owned printing+finish+condition)
└── decks/{deckId}       (one document per deck, card list embedded)
```

Everything is nested under `users/{uid}` so a single security rule covers the whole tree.

## 2. `users/{uid}/profile`

```jsonc
{
  "displayName": "Bruno",
  "createdAt":   "<timestamp>",
  "settings": {
    "defaultCondition": "NM",
    "hideDigitalCards": true,
    "lastMigrationApplied": "2026-07-02"   // see 02-catalog-schema.md §4
  }
}
```

## 3. `users/{uid}/collection/{entryId}`

One document per *distinct* thing owned. Two copies of the same printing in the same finish and
condition are **one document with `quantity: 2`**, not two documents.

```jsonc
{
  "printingId": "7673784e-db4b-43a1-8d55-1bb9fc1e284f",  // scryfall_id
  "oracleId":   "4457ed35-7c10-48c8-9776-456485fdf070",  // denormalized for deck queries
  "setCode":    "clu",                                    // denormalized for grouping/filtering
  "name":       "Lightning Bolt",                         // denormalized for offline sort/display
  "quantity":   4,
  "finish":     "nonfoil",       // nonfoil | foil | etched
  "language":   "en",
  "condition":  "NM",            // NM | LP | MP | HP | DMG
  "notes":      "",
  "orphaned":   false,           // set true if a migration deleted this printing
  "addedAt":    "<timestamp>",
  "updatedAt":  "<timestamp>"
}
```

**`entryId`** is a deterministic composite: `{printingId}_{finish}_{condition}_{language}`. This
makes "add 1 more of this exact card" an idempotent `set(..., merge: true)` with an increment,
instead of a query-then-write. It also makes accidental duplicates structurally impossible.

**Why the denormalized fields.** `name`, `setCode`, and `oracleId` are all available in the local
catalog, so strictly they are redundant. They are duplicated anyway because it lets the collection
list render, sort, and group without opening the catalog — which matters on first launch before the
catalog has finished downloading. The cost is a few dozen bytes per document.

### Indexes

Single-field indexes are automatic and sufficient for v1. Composite indexes are only needed if a
query filters and orders on different fields — add them reactively when Firestore's error message
gives you the creation link, rather than pre-creating them.

## 4. `users/{uid}/decks/{deckId}`

The card list is an **array inside the deck document**, not a subcollection.

```jsonc
{
  "name":      "Mono-Red Burn",
  "format":    "modern",
  "notes":     "",
  "coverPrintingId": "7673784e-…",
  "colorIdentity": ["R"],       // computed on save, for list display
  "createdAt": "<timestamp>",
  "updatedAt": "<timestamp>",
  "cards": [
    {
      "oracleId":   "4457ed35-…",
      "printingId": "7673784e-…",   // optional; the specific printing the user wants
      "name":       "Lightning Bolt",
      "quantity":   4,
      "board":      "main"           // main | side | maybe
    }
  ],
  "commanderOracleIds": []           // 0-2 entries, commander/brawl only
}
```

**Why an array and not a subcollection.** A 100-card Commander deck is ~100 entries at ~150 bytes
each — about 15 KB, far under Firestore's 1 MiB document limit. Embedding means loading a deck is
**one read** instead of 100, which matters a lot against a 50k reads/day quota. The tradeoff is
that every deck edit rewrites the whole document, but a deck is edited by one person at a time so
there is no contention.

Do **not** apply this pattern to `collection` — that can reach thousands of entries and would blow
the document limit.

## 5. Read/write budget

The Spark quotas are generous for a single user, but the app should still be built to respect them:

| Operation | Cost |
|---|---|
| Open the app, load collection | 1 read per entry, **first time only** |
| Subsequent launches | Reads served from Firestore's local persistence; only changed docs cost a read |
| Add a card | 1 write |
| Open a deck | 1 read |
| Save a deck | 1 write |

**Enable Firestore offline persistence** (`Settings(persistenceEnabled: true)`, with unlimited
cache size). Beyond enabling offline browsing, it is what keeps daily reads near zero — the SDK
only fetches documents whose `updatedAt` changed.

Never attach a `snapshots()` listener to the whole collection on a screen that rebuilds often; use
a single app-level listener, or `get()` with `Source.cache` where live updates are not needed.

## 6. Security rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

Deny-by-default covers everything else. Deploy these **before** the first write — a new Firestore
database in test mode is world-writable and expires after 30 days.

## 7. Authentication

Firebase Auth with **Google Sign-In** as the primary provider and **anonymous** as a fallback so
the app is usable before signing in. Offer account linking so an anonymous user's data survives
signing in later.

## 8. The Windows problem — read this before writing any Firebase code

Firebase's official Flutter documentation states plainly:

> **Caution:** Firebase on Windows is not intended for production use cases, only local development
> workflows.

`firebase_auth`, `cloud_firestore`, and `firebase_storage` all list Windows support as **beta**.

**Mitigation, which is mandatory:** every Firebase call goes behind an interface. No widget, no
view model, and no business logic may import `cloud_firestore` or `firebase_auth` directly.

```dart
abstract class CollectionRepository {
  Stream<List<CollectionEntry>> watchAll();
  Future<void> upsert(CollectionEntry entry);
  Future<void> updateQuantity(String entryId, int quantity);
  Future<void> remove(String entryId);
}

abstract class DeckRepository {
  Stream<List<DeckSummary>> watchAll();
  Future<Deck?> load(String deckId);
  Future<void> save(Deck deck);
  Future<void> delete(String deckId);
}

abstract class AuthService {
  Stream<AppUser?> authStateChanges();
  Future<AppUser> signInWithGoogle();
  Future<AppUser> signInAnonymously();
  Future<void> signOut();
}
```

Ship a `FirestoreCollectionRepository` implementation using the official plugins. If the Windows
beta proves unstable, a `RestCollectionRepository` can be written against the
[Firestore REST API](https://firebase.google.com/docs/firestore/use-rest-api) and the
[Auth REST API](https://firebase.google.com/docs/reference/rest/auth) — both fully supported plain
HTTPS — and swapped in through dependency injection with **no UI changes**.

Choose the implementation at startup based on `defaultTargetPlatform`, not with conditional imports
scattered through the codebase.

## 9. What never goes in Firestore

- Card names, rules text, mana costs, type lines *(catalog)*
- Set data *(catalog)*
- Images or image URLs *(derived; files live in the CDN and the local disk cache)*
- Prices *(out of scope entirely)*

Putting the catalog in Firestore would need ~113k writes for the initial import alone — nearly six
days at the free tier's 20k/day — and would exceed the 1 GiB storage limit once per-document
overhead is counted. This is the constraint the entire architecture is designed around.
