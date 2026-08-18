import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// The catalog schema version this build of the app understands.
///
/// Must match `SCHEMA_VERSION` in tools/catalog_builder/schema.py. If a
/// published manifest advertises a higher version, the app refuses to download
/// it and keeps using the catalog it has.
const int kSupportedSchemaVersion = 1;

/// Read-only handle on the local card catalog.
///
/// Opened once at startup and held for the app's lifetime; reopening per query
/// defeats the page cache and is markedly slower.
class CatalogDatabase {
  CatalogDatabase._(this._db, this.meta);

  final Database _db;
  final Map<String, String> meta;

  Database get raw => _db;

  int get schemaVersion => int.parse(meta['schema_version'] ?? '0');
  int get catalogVersion => int.parse(meta['catalog_version'] ?? '0');
  int get cardCount => int.parse(meta['card_count'] ?? '0');
  int get printingCount => int.parse(meta['printing_count'] ?? '0');
  int get setCount => int.parse(meta['set_count'] ?? '0');
  String? get builtAt => meta['built_at'];

  static Future<File> defaultLocation() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}catalog'
        '${Platform.pathSeparator}catalog.sqlite');
  }

  static Future<CatalogDatabase?> openIfPresent([File? file]) async {
    final target = file ?? await defaultLocation();
    if (!target.existsSync()) return null;
    return open(target);
  }

  static CatalogDatabase open(File file) {
    final db = sqlite3.open(file.path, mode: OpenMode.readOnly);
    db.execute('PRAGMA query_only = ON;');
    db.execute('PRAGMA cache_size = -32000;'); // ~32 MB page cache
    db.execute('PRAGMA temp_store = MEMORY;');

    final meta = <String, String>{};
    for (final row in db.select('SELECT key, value FROM meta')) {
      meta[row['key'] as String] = row['value'] as String;
    }
    return CatalogDatabase._(db, meta);
  }

  void dispose() => _db.dispose();
}
