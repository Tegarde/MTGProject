import 'package:sqlite3/sqlite3.dart';

import '../../core/fts_query.dart';
import '../../models/card_face.dart';
import '../../models/mtg_card.dart';
import '../../models/printing.dart';
import 'catalog_database.dart';

/// Search filters. All fields are optional; an empty filter browses everything.
class CardFilter {
  const CardFilter({
    this.text = '',
    this.colors = const {},
    this.rarities = const {},
    this.setCode,
    this.minCmc,
    this.maxCmc,
    this.typeContains,
    this.includeTokens = false,
    this.includeDigital = false,
  });

  final String text;

  /// Colour identity letters: W, U, B, R, G.
  final Set<String> colors;
  final Set<String> rarities;
  final String? setCode;
  final double? minCmc;
  final double? maxCmc;
  final String? typeContains;
  final bool includeTokens;
  final bool includeDigital;

  bool get hasText => text.trim().isNotEmpty;

  CardFilter copyWith({
    String? text,
    Set<String>? colors,
    Set<String>? rarities,
    String? setCode,
    double? minCmc,
    double? maxCmc,
    String? typeContains,
    bool? includeTokens,
    bool? includeDigital,
  }) => CardFilter(
    text: text ?? this.text,
    colors: colors ?? this.colors,
    rarities: rarities ?? this.rarities,
    setCode: setCode ?? this.setCode,
    minCmc: minCmc ?? this.minCmc,
    maxCmc: maxCmc ?? this.maxCmc,
    typeContains: typeContains ?? this.typeContains,
    includeTokens: includeTokens ?? this.includeTokens,
    includeDigital: includeDigital ?? this.includeDigital,
  );
}

class CardDao {
  CardDao(this._catalog);

  final CatalogDatabase _catalog;
  Database get _db => _catalog.raw;

  /// Full-text plus filter search.
  ///
  /// When [filter] has text, FTS5 drives the query and bm25 weights bias matches
  /// toward the card name; otherwise it degrades to a plain indexed browse.
  List<MtgCard> search(CardFilter filter, {int limit = 50, int offset = 0}) {
    final where = <String>[];
    final params = <Object?>[];

    final ftsQuery = filter.hasText ? toFtsQuery(filter.text) : null;

    final from = StringBuffer('FROM cards c');
    if (ftsQuery != null) {
      from.write(' JOIN cards_fts f ON c.rowid = f.rowid');
      where.add('cards_fts MATCH ?');
      params.add(ftsQuery);
    }

    // Joining through the default printing keeps token/digital filtering to two
    // primary-key lookups instead of a correlated subquery over all printings.
    if (!filter.includeTokens || !filter.includeDigital || filter.setCode != null) {
      from.write(' JOIN printings dp ON dp.scryfall_id = c.default_printing_id');
      from.write(' JOIN sets ds ON ds.code = dp.set_code');
      if (!filter.includeTokens) where.add("ds.set_type != 'token'");
      if (!filter.includeDigital) where.add('dp.digital = 0');
    }

    if (filter.setCode != null) {
      where.add(
        'EXISTS (SELECT 1 FROM printings p WHERE p.oracle_id = c.oracle_id '
        'AND p.set_code = ?)',
      );
      params.add(filter.setCode);
    }

    for (final color in filter.colors) {
      where.add('c.color_identity LIKE ?');
      params.add('%"$color"%');
    }

    if (filter.rarities.isNotEmpty) {
      final marks = List.filled(filter.rarities.length, '?').join(',');
      where.add(
        'EXISTS (SELECT 1 FROM printings p WHERE p.oracle_id = c.oracle_id '
        'AND p.rarity IN ($marks))',
      );
      params.addAll(filter.rarities);
    }

    if (filter.minCmc != null) {
      where.add('c.cmc >= ?');
      params.add(filter.minCmc);
    }
    if (filter.maxCmc != null) {
      where.add('c.cmc <= ?');
      params.add(filter.maxCmc);
    }
    if (filter.typeContains != null) {
      where.add('c.type_line LIKE ?');
      params.add('%${filter.typeContains}%');
    }

    final order = ftsQuery != null
        ? 'ORDER BY bm25(cards_fts, 10.0, 1.0, 2.0)'
        : 'ORDER BY c.name COLLATE NOCASE';

    final sql = StringBuffer('SELECT c.* ')
      ..write(from)
      ..write(where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}')
      ..write(' $order LIMIT ? OFFSET ?');
    params
      ..add(limit)
      ..add(offset);

    return _db
        .select(sql.toString(), params)
        .map(MtgCard.fromRow)
        .toList(growable: false);
  }

  MtgCard? byOracleId(String oracleId) {
    final rows = _db.select(
      'SELECT * FROM cards WHERE oracle_id = ?',
      [oracleId],
    );
    return rows.isEmpty ? null : MtgCard.fromRow(rows.first);
  }

  MtgCard? byName(String name) {
    final rows = _db.select(
      'SELECT * FROM cards WHERE name = ? COLLATE NOCASE LIMIT 1',
      [name],
    );
    return rows.isEmpty ? null : MtgCard.fromRow(rows.first);
  }

  /// Faces of a multi-faced card, in printed order. Empty for normal cards.
  List<CardFace> facesOf(String oracleId) => _db
      .select(
        'SELECT * FROM card_faces WHERE oracle_id = ? ORDER BY face_index',
        [oracleId],
      )
      .map(CardFace.fromRow)
      .toList(growable: false);

  /// Every printing of a card, newest set first.
  List<Printing> printingsOf(String oracleId) => _db
      .select(
        'SELECT * FROM printings WHERE oracle_id = ? '
        'ORDER BY released_at DESC, set_code, collector_number',
        [oracleId],
      )
      .map(Printing.fromRow)
      .toList(growable: false);

  Printing? printingById(String scryfallId) {
    final rows = _db.select(
      'SELECT * FROM printings WHERE scryfall_id = ?',
      [scryfallId],
    );
    return rows.isEmpty ? null : Printing.fromRow(rows.first);
  }

  /// Convenience for rendering a card without loading all of its printings.
  Printing? defaultPrintingOf(MtgCard card) => printingById(card.defaultPrintingId);
}
