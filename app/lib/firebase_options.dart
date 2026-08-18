// Firebase configuration for the `mtg-collection-15d93` project.
//
// Generated with `flutterfire configure` from `app/`, then hand-verified
// (see planning/08-dev-testing-notes.md §6) — these values are public by
// design and safe to commit; see planning/04-firestore-model.md §5.
// Re-run `flutterfire configure` if the Firebase project ever changes.
library;

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web. Run '
        '`flutterfire configure` again if web support is ever added.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.windows:
        return windows;
      default:
        // Only Android and Windows are in scope; see planning/00-overview.md §3.
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for $defaultTargetPlatform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAM-TcMejhR8B5WRgaf3tKKau0vUKomJWE',
    appId: '1:72976746895:android:048b99a603b13e3a58e3fa',
    messagingSenderId: '72976746895',
    projectId: 'mtg-collection-15d93',
    storageBucket: 'mtg-collection-15d93.firebasestorage.app',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyB-nzwBYr6-KJVAzeceoyi8SiHjp4dnHac',
    appId: '1:72976746895:web:8034decbe8bd959058e3fa',
    messagingSenderId: '72976746895',
    projectId: 'mtg-collection-15d93',
    authDomain: 'mtg-collection-15d93.firebaseapp.com',
    storageBucket: 'mtg-collection-15d93.firebasestorage.app',
    measurementId: 'G-CXCD0DSX8E',
  );
}
