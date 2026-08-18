# 08 — Dev/testing notes and known issues

Engineering log for local catalog-bootstrap testing on the Android emulator. Read this before
debugging the download path again — most of it has already been ruled out.

---

## 1. Local dev catalog server

`tools/dev_catalog_server.py` serves a locally built catalog with `Range` support (the stdlib
`http.server` ignores `Range`, which the app's resume logic needs to be tested):

```
python tools/dev_catalog_server.py
flutter run --dart-define=MANIFEST_URL=http://10.0.2.2:8000/manifest.json
```

`10.0.2.2` is the emulator's alias for the host's loopback address. The manifest's `url` field is
rewritten on the fly to point back at whichever host/port the server was told to advertise.

## 2. Emulator RAM

The `Medium_Phone` AVD's default RAM (~2 GB) is not enough — the low-memory killer kills the app
mid-download. Launch with at least 4 GB:

```
emulator -avd Medium_Phone -memory 4096
```

## 3. Catalog bootstrap: retry on checksum mismatch

`CatalogBootstrap._install` (`app/lib/data/catalog/catalog_bootstrap.dart`) retries the *entire*
download-and-verify cycle up to `_maxDownloads` (3) times if the SHA-256 doesn't match the
manifest, discarding the archive and starting fresh each time. This is worthwhile regardless of the
issue below — real mobile networks can deliver corrupted bytes with a `200`/`206` and no transport
error, and resuming a partial download cannot repair bytes that are already wrong.

This was validated end-to-end: forced to fail 3 times in a row, the app correctly surfaced a typed
`ManifestException` with a working "Try again" button.

## 4. Known issue: emulator corrupts large downloads (unresolved)

Downloading the ~25 MB `catalog-v1.sqlite.gz` to this AVD is unreliable — the transfer completes
(right byte count) but a handful of bytes are silently wrong, so the SHA-256 fails. It reproduces
on the actual app, and the corrupted bytes are different every time.

**Ruled out** by direct testing:

- **The dev server** — 4 consecutive full downloads fetched directly from the host (no
  emulator/adb involved) all hashed correctly.
- **The Dart/`http` download code** — a raw on-device `nc` fetch, bypassing Dart entirely,
  reproduces the same kind of corruption.
- **SLIRP specifically (`10.0.2.2`)** — routing the same request through `adb reverse tcp:8000
  tcp:8000` to `127.0.0.1` (a completely different transport that doesn't touch the emulator's
  virtual NAT) reproduces it too.
- **Stale emulator state** — reproduces even immediately after a full cold boot
  (`-no-snapshot-load -no-snapshot-save`).

**Leading theory:** a bug in this emulator build's virtual-NIC/data-relay path under sustained
large transfers, shared by both SLIRP and `adb reverse` because both are ultimately serviced by the
same emulator process. Not yet tried: a physical device, a different AVD system image/API level, or
a different emulator version.

**Practically:** treat downloads on this emulator as untrustworthy for anything much larger than a
few MB. This should not affect production, where the catalog is served from GitHub Releases over a
real CDN rather than a local dev server through the emulator's virtual network — but that has not
yet been verified on-device.

## 5. Workaround: seeding a catalog directly for UI testing

To test anything downstream of the download (search screen, DAOs, images) without fighting the bug
above, push a known-good decompressed catalog straight into the app's private storage:

```powershell
adb push build\catalog.sqlite /data/local/tmp/catalog.sqlite
adb shell run-as <package> cp /data/local/tmp/catalog.sqlite files/catalog/catalog.sqlite
```

Notes:

- `adb push` and `run-as cp` are unaffected by the network bug above (no HTTP/socket involved).
- Push to `/data/local/tmp` first, not `/sdcard` — `run-as` got `Permission denied` reading
  `/sdcard` (scoped storage), but `/data/local/tmp` files pushed by `adb` are world-readable
  (`rw-rw-rw-`).
- Use a path **relative to the app's data dir** with `run-as` (e.g. `files/catalog/...`), not the
  absolute `/data/user/0/<package>/...` path — the absolute form gave a spurious
  `Permission denied` even though `ls -l` showed correct ownership and mode.
- The catalog's `catalog_version` in its `meta` table must be `<=` the manifest's, or the app will
  still attempt to download an "update".

This was used to confirm the rest of the bootstrap/search pipeline works correctly end-to-end
(SearchScreen renders "38626 cards · 116712 printings · 1047 sets · catalog v1" with working search
and card images) independent of the download bug.

## 6. P4 status: auth/collection architecture is built, Firebase project setup is not

`AuthService`/`FirebaseAuthService` (`app/lib/data/auth/`) and `CollectionRepository`/
`FirestoreCollectionRepository` (`app/lib/data/collection/`) exist and are wired through
`AuthGate` → `SignInScreen`/`HomeShell`. `lib/firebase_options.dart` is a **placeholder** that
throws `UnsupportedError` — there is no Firebase project behind this app yet.

To finish the setup:

```
dart pub global activate flutterfire_cli
cd app
flutterfire configure
```

This overwrites `lib/firebase_options.dart` with real values and registers the Android app (adds
`google-services.json` and the Gradle plugin). It's safe to commit — see
`04-firestore-model.md` §5. Also deploy `firestore.rules` (repo root) to the project before the
first write.

**Google Sign-In has no Windows implementation** (`google_sign_in` only ships Android/iOS/macOS/web
platform code — checked in its `pubspec.yaml`). `FirebaseAuthService.supportsGoogleSignIn` gates on
`defaultTargetPlatform`, so Windows falls back to anonymous sign-in only until a browser-based OAuth
flow is added; `SignInScreen` already handles this by hiding the Google button there.

Untested end-to-end for the same reason as the catalog download bug above: no Firebase project to
point the emulator/app at yet. Once `flutterfire configure` has run, re-verify sign-in, add-to-
collection, and the quantity steppers against a real project before considering P4 done.

