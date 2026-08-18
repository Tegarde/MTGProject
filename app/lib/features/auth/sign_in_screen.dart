import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di.dart';
import '../../data/auth/firebase_auth_service.dart';

/// Shown when no user is signed in yet. Google Sign-In is the primary path;
/// anonymous is offered as a fallback so the app is usable immediately (see
/// planning/04-firestore-model.md §7).
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _busy = false;
  Object? _error;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.read(authServiceProvider);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.style, size: 56, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'MTG Collection',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to sync your collection and decks across devices.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                if (FirebaseAuthService.supportsGoogleSignIn)
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _run(() => auth.signInWithGoogle()),
                    icon: const Icon(Icons.account_circle),
                    label: const Text('Sign in with Google'),
                  )
                else
                  Text(
                    'Google Sign-In is not yet available on '
                    '${defaultTargetPlatform.name}; continue as a guest below.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _busy ? null : () => _run(() => auth.signInAnonymously()),
                  child: const Text('Continue as guest'),
                ),
                if (_busy) ...[const SizedBox(height: 24), const CircularProgressIndicator()],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    '$_error',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
