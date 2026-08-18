import 'dart:convert';

import 'package:http/http.dart' as http;

/// Points at the published catalog. Committed to the repo by CI and served over
/// raw.githubusercontent.com; a few hundred bytes, and the only network call
/// the app makes on a normal launch.
///
/// Overridable for development against a local catalog server:
/// `flutter run --dart-define=MANIFEST_URL=http://10.0.2.2:8000/manifest.json`
const String kManifestUrl = String.fromEnvironment(
  'MANIFEST_URL',
  defaultValue: 'https://raw.githubusercontent.com/Tegarde/MTGProject/main/manifest.json',
);

const String kUserAgent = 'MTGCollectionTracker/1.0';

class CatalogManifest {
  const CatalogManifest({
    required this.catalogVersion,
    required this.schemaVersion,
    required this.url,
    required this.compressedSize,
    required this.sha256,
    required this.builtAt,
    required this.cardCount,
    required this.printingCount,
    required this.setCount,
  });

  final int catalogVersion;
  final int schemaVersion;
  final String url;
  final int compressedSize;
  final String sha256;
  final String builtAt;
  final int cardCount;
  final int printingCount;
  final int setCount;

  factory CatalogManifest.fromJson(Map<String, dynamic> json) => CatalogManifest(
    catalogVersion: json['catalog_version'] as int,
    schemaVersion: json['schema_version'] as int,
    url: json['url'] as String,
    compressedSize: json['compressed_size'] as int,
    sha256: json['sha256'] as String,
    builtAt: json['built_at'] as String,
    cardCount: json['card_count'] as int,
    printingCount: json['printing_count'] as int,
    setCount: json['set_count'] as int,
  );

  static Future<CatalogManifest> fetch({http.Client? client}) async {
    final owned = client == null;
    final http.Client c = client ?? http.Client();
    try {
      final response = await c
          .get(Uri.parse(kManifestUrl), headers: {'User-Agent': kUserAgent})
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw ManifestException('manifest fetch failed: HTTP ${response.statusCode}');
      }
      return CatalogManifest.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } finally {
      if (owned) c.close();
    }
  }
}

class ManifestException implements Exception {
  ManifestException(this.message);
  final String message;
  @override
  String toString() => message;
}
