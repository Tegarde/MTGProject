import '../../models/app_user.dart';

/// Interface for authentication, kept separate from any Firebase import.
///
/// planning/04-firestore-model.md §8: Firebase on Windows is beta, so no
/// widget or view model may import `firebase_auth` directly. If the Windows
/// beta ever proves unstable, a REST-based implementation can be swapped in
/// through dependency injection with no UI changes.
abstract class AuthService {
  Stream<AppUser?> authStateChanges();
  Future<AppUser> signInWithGoogle();
  Future<AppUser> signInAnonymously();
  Future<void> signOut();
}
