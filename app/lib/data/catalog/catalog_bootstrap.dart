import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'catalog_database.dart';
import 'catalog_manifest.dart';

/// Hashes a file, on whichever isolate calls this.
///
/// Top-level so it can be handed to [Isolate.run]: hashing 25 MiB blocks for
/// seconds, which stalls the UI and pushes the process into the low-memory
/// killer's sights if done on the main isolate. The digest is returned rather
/// than compared here so the caller can react without an error having to cross
/// an isolate boundary.
Future<String> _sha256OfFile(String path) async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString();
}

/// Inflates [archivePath] into [stagedPath]. Top-level for the same reason.
Future<void> _expand((String archivePath, String stagedPath) args) async {
  final (archivePath, stagedPath) = args;
  final sink = File(stagedPath).openWrite();
  await File(archivePath).openRead().transform(gzip.decoder).pipe(sink);
}

enum BootstrapStage { checking, downloading, verifying, installing, ready, failed }

class BootstrapProgress {
  const BootstrapProgress(this.stage, {this.received = 0, this.total = 0, this.error});

  final BootstrapStage stage;
  final int received;
  final int total;
  final Object? error;

  double? get fraction => total > 0 ? received / total : null;
}

/// Downloads, verifies and installs the catalog file.
///
/// The state machine is documented in planning/05-flutter-app.md §3. The key
/// rule: a working catalog is never destroyed until a replacement has been
/// fully downloaded and its checksum verified.
class CatalogBootstrap {
  CatalogBootstrap({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Opens the local catalog, downloading one first if none is usable.
  ///
  /// [onProgress] reports download progress for the UI.
  Future<CatalogDatabase> ensureCatalog({
    void Function(BootstrapProgress)? onProgress,
    bool allowUpdate = true,
  }) async {
    void report(BootstrapProgress p) => onProgress?.call(p);
    report(const BootstrapProgress(BootstrapStage.checking));

    final target = await CatalogDatabase.defaultLocation();
    final existing = await CatalogDatabase.openIfPresent(target);

    CatalogManifest? manifest;
    try {
      manifest = await CatalogManifest.fetch(client: _client);
    } catch (error) {
      // A failed manifest fetch is not fatal when we already have a catalog:
      // the app is fully usable offline.
      if (existing != null) {
        report(const BootstrapProgress(BootstrapStage.ready));
        return existing;
      }
      report(BootstrapProgress(BootstrapStage.failed, error: error));
      rethrow;
    }

    if (manifest.schemaVersion > kSupportedSchemaVersion) {
      // Never download a catalog this build cannot read.
      if (existing != null) {
        report(const BootstrapProgress(BootstrapStage.ready));
        return existing;
      }
      final error = StateError(
        'The published catalog requires schema v${manifest.schemaVersion}, '
        'but this app supports v$kSupportedSchemaVersion. Please update the app.',
      );
      report(BootstrapProgress(BootstrapStage.failed, error: error));
      throw error;
    }

    final needsDownload = existing == null ||
        (allowUpdate && manifest.catalogVersion > existing.catalogVersion);
    if (!needsDownload) {
      report(const BootstrapProgress(BootstrapStage.ready));
      return existing;
    }

    existing?.dispose();

    try {
      await _install(manifest, target, report);
    } catch (error) {
      report(BootstrapProgress(BootstrapStage.failed, error: error));
      rethrow;
    }

    report(const BootstrapProgress(BootstrapStage.ready));
    return CatalogDatabase.open(target);
  }

  Future<void> _install(
    CatalogManifest manifest,
    File target,
    void Function(BootstrapProgress) report,
  ) async {
    final dir = target.parent;
    await dir.create(recursive: true);

    final archive = File('${target.path}.gz.tmp');
    final staged = File('${target.path}.tmp');

    try {
      // A transfer can be corrupted rather than merely cut short, and resuming
      // cannot repair bytes that are already wrong, so a checksum mismatch
      // discards the archive and starts over instead of failing outright.
      for (var attempt = 1; ; attempt++) {
        await _download(manifest, archive, report);

        report(const BootstrapProgress(BootstrapStage.verifying));
        final digest = await Isolate.run(() => _sha256OfFile(archive.path));
        if (digest == manifest.sha256) break;

        await archive.delete();
        if (attempt >= _maxDownloads) {
          throw ManifestException(
            'Catalog checksum mismatch after $attempt downloads: '
            'expected ${manifest.sha256}, got $digest',
          );
        }
      }

      await Isolate.run(() => _expand((archive.path, staged.path)));

      report(const BootstrapProgress(BootstrapStage.installing));

      // Sanity-check the decompressed file before it replaces a working catalog.
      CatalogDatabase.open(staged).dispose();

      if (target.existsSync()) await target.delete();
      await staged.rename(target.path);
    } finally {
      if (archive.existsSync()) await archive.delete();
      if (staged.existsSync()) await staged.delete();
    }
  }

  /// Fetches the archive, retrying and resuming if the transfer is cut short.
  ///
  /// 25 MiB over a mobile connection gets interrupted routinely, so a dropped
  /// stream is treated as normal rather than as a failure. The attempt budget
  /// only counts attempts that made no progress, so a link that keeps dying
  /// mid-transfer still finishes as long as it inches forward.
  Future<void> _download(
    CatalogManifest manifest,
    File destination,
    void Function(BootstrapProgress) report,
  ) async {
    if (destination.existsSync()) await destination.delete();

    var attempt = 0;
    var furthest = -1;

    while (true) {
      final resumeFrom = destination.existsSync() ? await destination.length() : 0;
      if (resumeFrom > furthest) {
        furthest = resumeFrom;
        attempt = 0;
      }
      attempt++;

      try {
        await _downloadFrom(manifest, destination, resumeFrom, report);
        return;
      } catch (error) {
        if (attempt >= _maxAttempts) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt));
      }
    }
  }

  Future<void> _downloadFrom(
    CatalogManifest manifest,
    File destination,
    int offset,
    void Function(BootstrapProgress) report,
  ) async {
    final request = http.Request('GET', Uri.parse(manifest.url))
      ..headers['User-Agent'] = kUserAgent;
    if (offset > 0) request.headers['Range'] = 'bytes=$offset-';

    final response = await _client.send(request);
    final resuming = response.statusCode == 206;
    if (response.statusCode != 200 && !resuming) {
      throw ManifestException('catalog download failed: HTTP ${response.statusCode}');
    }

    // A server that ignores Range answers 200 with the whole body, so start over.
    final startAt = resuming ? offset : 0;
    final total = manifest.compressedSize;

    var received = startAt;
    var reportedAt = startAt;

    // A RandomAccessFile is used rather than an IOSink because awaiting each
    // write gives natural backpressure, and closing it after a failed transfer
    // does not throw over the top of the error that caused the failure.
    final file = await destination.open(
      mode: startAt > 0 ? FileMode.append : FileMode.write,
    );
    try {
      await for (final chunk in response.stream) {
        await file.writeFrom(chunk);
        received += chunk.length;

        // Repainting per chunk would queue thousands of frames and stall the UI.
        if (received - reportedAt >= _reportEvery || received >= total) {
          reportedAt = received;
          report(BootstrapProgress(
            BootstrapStage.downloading,
            received: received,
            total: total,
          ));
        }
      }
    } finally {
      await file.close();
    }

    final size = await destination.length();
    if (size != manifest.compressedSize) {
      throw ManifestException(
        'catalog download truncated: got $size of ${manifest.compressedSize} bytes',
      );
    }
  }

  static const int _maxAttempts = 5;
  static const int _maxDownloads = 3;
  static const int _reportEvery = 256 << 10; // 256 KiB

  void dispose() => _client.close();
}
