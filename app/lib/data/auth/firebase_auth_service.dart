import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../models/app_user.dart';
import 'auth_service.dart';

/// The Web client id Firebase issues alongside the Android/iOS client ids
/// (Firebase console → Project settings → your Web app, or the
/// `client_id` of the `client_type: 3` entry in `google-services.json`).
/// Only Android and iOS use this to obtain a Firebase-verifiable id token
/// from Google Sign-In; Windows has no Google Sign-In plugin (see
/// [FirebaseAuthService.supportsGoogleSignIn]) so it does not need it.
///
/// Overridable without a code change once you have a project:
/// `flutter run --dart-define=GOOGLE_SIGN_IN_SERVER_CLIENT_ID=...`
const String kGoogleSignInServerClientId = String.fromEnvironment(
  'GOOGLE_SIGN_IN_SERVER_CLIENT_ID',
);

/// [AuthService] backed by `firebase_auth` and `google_sign_in`.
///
/// planning/04-firestore-model.md §8: this is the only file allowed to
/// import `firebase_auth`. Everything else goes through [AuthService].
class FirebaseAuthService implements AuthService {
  FirebaseAuthService({fb.FirebaseAuth? auth}) : _auth = auth ?? fb.FirebaseAuth.instance;

  final fb.FirebaseAuth _auth;
  bool _googleSignInReady = false;

  /// `google_sign_in` has no Windows implementation. Windows users can only
  /// sign in anonymously until a browser-based OAuth flow is added.
  static bool get supportsGoogleSignIn =>
      defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Stream<AppUser?> authStateChanges() =>
      _auth.authStateChanges().map((user) => user == null ? null : _toAppUser(user));

  @override
  Future<AppUser> signInAnonymously() async {
    final credential = await _auth.signInAnonymously();
    return _toAppUser(credential.user!);
  }

  @override
  Future<AppUser> signInWithGoogle() async {
    if (!supportsGoogleSignIn) {
      throw UnsupportedError('Google Sign-In is not available on this platform yet.');
    }

    final googleSignIn = GoogleSignIn.instance;
    if (!_googleSignInReady) {
      await googleSignIn.initialize(
        serverClientId: kGoogleSignInServerClientId.isEmpty ? null : kGoogleSignInServerClientId,
      );
      _googleSignInReady = true;
    }

    final account = await googleSignIn.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw StateError('Google did not return an id token.');
    }

    final googleCredential = fb.GoogleAuthProvider.credential(idToken: idToken);

    // If the current user is anonymous, link instead of replacing them so a
    // collection built up before signing in is not orphaned.
    final current = _auth.currentUser;
    fb.UserCredential credential;
    if (current != null && current.isAnonymous) {
      try {
        credential = await current.linkWithCredential(googleCredential);
      } on fb.FirebaseAuthException catch (error) {
        // This Google account already has its own Firebase user; fall back
        // to signing into that one instead of a failed link.
        if (error.code != 'credential-already-in-use') rethrow;
        credential = await _auth.signInWithCredential(googleCredential);
      }
    } else {
      credential = await _auth.signInWithCredential(googleCredential);
    }
    return _toAppUser(credential.user!);
  }

  @override
  Future<void> signOut() async {
    if (supportsGoogleSignIn) {
      await GoogleSignIn.instance.signOut();
    }
    await _auth.signOut();
  }

  AppUser _toAppUser(fb.User user) => AppUser(
    uid: user.uid,
    isAnonymous: user.isAnonymous,
    displayName: user.displayName,
    email: user.email,
    photoUrl: user.photoURL,
  );
}
