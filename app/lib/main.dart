import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/bootstrap/bootstrap_screen.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Object? firebaseError;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (error) {
    // Surfaced as a screen rather than a crash so `flutter run` still works
    // to develop everything upstream of sign-in (catalog, search, images)
    // before `flutterfire configure` has been run. See lib/firebase_options.dart.
    firebaseError = error;
  }

  runApp(ProviderScope(child: MtgCollectionApp(firebaseError: firebaseError)));
}

class MtgCollectionApp extends StatelessWidget {
  const MtgCollectionApp({super.key, this.firebaseError});

  final Object? firebaseError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MTG Collection',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6D4C41),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF6D4C41),
        brightness: Brightness.dark,
      ),
      home: firebaseError == null
          ? const BootstrapScreen()
          : _FirebaseNotConfigured(error: firebaseError!),
    );
  }
}

class _FirebaseNotConfigured extends StatelessWidget {
  const _FirebaseNotConfigured({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text('Firebase is not configured yet', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text(
                'Run `flutterfire configure` from app/ to generate '
                'lib/firebase_options.dart, then restart the app.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text('$error', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    ),
  );
}

