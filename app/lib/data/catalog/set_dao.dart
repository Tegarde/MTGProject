import 'package:sqlite3/sqlite3.dart';

import '../../models/mtg_set.dart';
import 'catalog_database.dart';

class SetDao {
  SetDao(this._catalog);

  final CatalogDatabase _catalog;
  Database get _db => _catalog.raw;

  /// All sets, newest first. Token and digital-only sets are excluded by
  /// default because they clutter the set picker.
  List<MtgSet> all({bool includeTokens = false, bool includeDigital = false}) {
    final where = <String>[];
    if (!includeTokens) where.add("set_type != 'token'");
    if (!includeDigital) where.add('digital = 0');

    final sql = StringBuffer('SELECT * FROM sets')
      ..write(where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}')
      ..write(' ORDER BY released_at DESC, name');

    return _db.select(sql.toString()).map(MtgSet.fromRow).toList(growable: false);
  }

  MtgSet? byCode(String code) {
    final rows = _db.select('SELECT * FROM sets WHERE code = ?', [code]);
    return rows.isEmpty ? null : MtgSet.fromRow(rows.first);
  }

  /// Distinct printing count per set, for progress indicators like
  /// "you own 42 of 281 cards in this set".
  Map<String, int> printingCounts() {
    final counts = <String, int>{};
    for (final row in _db.select(
      'SELECT set_code, COUNT(*) AS n FROM printings GROUP BY set_code',
    )) {
      counts[row['set_code'] as String] = row['n'] as int;
    }
    return counts;
  }
}
