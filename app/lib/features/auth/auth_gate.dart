import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di.dart';
import '../home/home_shell.dart';
import 'sign_in_screen.dart';

/// Shown once the catalog is ready: routes between [SignInScreen] and
/// [HomeShell] based on [authStateProvider], so nothing downstream ever
/// reads the collection before a user exists.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) => user == null ? const SignInScreen() : const HomeShell(),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) =>
          Scaffold(body: Center(child: Text('Sign-in failed to initialize: $error'))),
    );
  }
}
