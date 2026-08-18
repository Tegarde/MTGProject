import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/di.dart';

/// Account icon for an `AppBar.actions` list: shows who is signed in and
/// offers sign-out. Used on every top-level tab rather than a dedicated
/// account screen, since there is nothing else to show yet.
class AccountMenuButton extends ConsumerWidget {
  const AccountMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).value;
    final label = user == null
        ? 'Not signed in'
        : (user.isAnonymous ? 'Signed in as guest' : (user.displayName ?? user.email ?? 'Signed in'));

    return PopupMenuButton<void>(
      icon: Icon(user != null && !user.isAnonymous ? Icons.account_circle : Icons.person_outline),
      itemBuilder: (context) => [
        PopupMenuItem<void>(enabled: false, child: Text(label)),
        const PopupMenuDivider(),
        PopupMenuItem<void>(
          onTap: () => ref.read(authServiceProvider).signOut(),
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}
