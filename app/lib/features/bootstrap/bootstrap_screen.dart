import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di.dart';
import '../../data/catalog/catalog_bootstrap.dart';
import '../auth/auth_gate.dart';

/// First screen shown at launch. Downloads and opens the card catalog, then
/// hands off to the app proper.
class BootstrapScreen extends ConsumerStatefulWidget {
  const BootstrapScreen({super.key});

  @override
  ConsumerState<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends ConsumerState<BootstrapScreen> {
  final _bootstrap = CatalogBootstrap();
  BootstrapProgress _progress = const BootstrapProgress(BootstrapStage.checking);

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _bootstrap.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _progress = const BootstrapProgress(BootstrapStage.checking));
    try {
      final catalog = await _bootstrap.ensureCatalog(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      ref.read(catalogProvider.notifier).adopt(catalog);
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthGate()),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _progress = BootstrapProgress(BootstrapStage.failed, error: error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: _progress.stage == BootstrapStage.failed
                ? _Failure(error: _progress.error, onRetry: _start)
                : _Progress(progress: _progress),
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.progress});

  final BootstrapProgress progress;

  String get _label => switch (progress.stage) {
    BootstrapStage.checking => 'Checking for card data\u2026',
    BootstrapStage.downloading => 'Downloading card catalog\u2026',
    BootstrapStage.verifying => 'Verifying download\u2026',
    BootstrapStage.installing => 'Installing catalog\u2026',
    BootstrapStage.ready => 'Ready',
    BootstrapStage.failed => 'Failed',
  };

  @override
  Widget build(BuildContext context) {
    final mib = progress.total > 0
        ? '${(progress.received / 1048576).toStringAsFixed(1)} of '
              '${(progress.total / 1048576).toStringAsFixed(1)} MiB'
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'MTG Collection',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 32),
        LinearProgressIndicator(value: progress.fraction),
        const SizedBox(height: 16),
        Text(_label, textAlign: TextAlign.center),
        if (mib != null) ...[
          const SizedBox(height: 4),
          Text(
            mib,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 24),
        Text(
          'This one-time download lets the app work offline, '
          'with no further calls to Scryfall.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.cloud_off, size: 48, color: Theme.of(context).colorScheme.error),
      const SizedBox(height: 16),
      Text('Could not load the card catalog', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(
        '$error',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('Try again'),
      ),
    ],
  );
}
