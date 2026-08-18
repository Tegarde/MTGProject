/// The signed-in user, independent of which auth provider was used.
///
/// Framework-free per planning/07-conventions.md: no `firebase_auth` import
/// here. [FirebaseAuthService] maps its `User` objects to this.
class AppUser {
  const AppUser({
    required this.uid,
    required this.isAnonymous,
    this.displayName,
    this.email,
    this.photoUrl,
  });

  final String uid;
  final bool isAnonymous;
  final String? displayName;
  final String? email;
  final String? photoUrl;
}
