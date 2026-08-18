import 'dart:convert';

/// A unique Magic card, keyed by Scryfall's oracle id.
///
/// One row per card regardless of how many times it has been printed; the
/// printings themselves live in [Printing].
class MtgCard {
  const MtgCard({
    required this.oracleId,
    required this.name,
    required this.cmc,
    required this.layout,
    required this.colorIdentity,
    required this.legalities,
    required this.faceCount,
    required this.defaultPrintingId,
    this.manaCost,
    this.typeLine,
    this.oracleText,
    this.power,
    this.toughness,
    this.loyalty,
    this.defense,
    this.colors = const [],
    this.keywords = const [],
    this.producedMana = const [],
    this.reserved = false,
    this.gameChanger = false,
    this.edhrecRank,
  });

  final String oracleId;
  final String name;
  final double cmc;
  final String layout;

  /// Colour identity, which is not the same as [colors]. Commander deck
  /// validation must use this one.
  final List<String> colorIdentity;

  /// Format name to one of `legal`, `not_legal`, `restricted`, `banned`.
  final Map<String, String> legalities;

  /// 0 for single-faced cards, otherwise the number of [CardFace] rows.
  final int faceCount;
  final String defaultPrintingId;

  final String? manaCost;
  final String? typeLine;
  final String? oracleText;

  /// Text, not numbers: real values include `*`, `1+*` and `?`.
  final String? power;
  final String? toughness;
  final String? loyalty;
  final String? defense;

  final List<String> colors;
  final List<String> keywords;
  final List<String> producedMana;
  final bool reserved;
  final bool gameChanger;
  final int? edhrecRank;

  bool get isMultiFaced => faceCount > 0;
  bool get isBasicLand => typeLine?.contains('Basic Land') ?? false;

  bool isLegalIn(String format) => legalities[format] == 'legal';

  factory MtgCard.fromRow(Map<String, dynamic> row) => MtgCard(
    oracleId: row['oracle_id'] as String,
    name: row['name'] as String,
    cmc: (row['cmc'] as num).toDouble(),
    layout: row['layout'] as String,
    colorIdentity: _list(row['color_identity'] as String?),
    legalities: _map(row['legalities'] as String?),
    faceCount: row['face_count'] as int,
    defaultPrintingId: row['default_printing_id'] as String,
    manaCost: row['mana_cost'] as String?,
    typeLine: row['type_line'] as String?,
    oracleText: row['oracle_text'] as String?,
    power: row['power'] as String?,
    toughness: row['toughness'] as String?,
    loyalty: row['loyalty'] as String?,
    defense: row['defense'] as String?,
    colors: _list(row['colors'] as String?),
    keywords: _list(row['keywords'] as String?),
    producedMana: _list(row['produced_mana'] as String?),
    reserved: (row['reserved'] as int?) == 1,
    gameChanger: (row['game_changer'] as int?) == 1,
    edhrecRank: row['edhrec_rank'] as int?,
  );

  static List<String> _list(String? raw) =>
      raw == null ? const [] : (jsonDecode(raw) as List).cast<String>();

  static Map<String, String> _map(String? raw) => raw == null
      ? const {}
      : (jsonDecode(raw) as Map).cast<String, dynamic>().map(
          (k, v) => MapEntry(k, v as String),
        );
}
