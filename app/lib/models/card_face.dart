import 'dart:convert';

/// One side of a multi-faced card.
///
/// Only populated for split, flip, transform, modal_dfc, meld, adventure and
/// reversible layouts. Single-faced cards have no faces at all.
class CardFace {
  const CardFace({
    required this.faceIndex,
    required this.name,
    required this.hasImage,
    this.manaCost,
    this.typeLine,
    this.oracleText,
    this.power,
    this.toughness,
    this.loyalty,
    this.defense,
    this.colors = const [],
  });

  final int faceIndex;
  final String name;
  final bool hasImage;
  final String? manaCost;
  final String? typeLine;
  final String? oracleText;

  /// Text, not numbers: real values include `*`, `1+*` and `?`.
  final String? power;
  final String? toughness;
  final String? loyalty;
  final String? defense;
  final List<String> colors;

  factory CardFace.fromRow(Map<String, dynamic> row) => CardFace(
    faceIndex: row['face_index'] as int,
    name: row['name'] as String,
    hasImage: (row['has_image'] as int) == 1,
    manaCost: row['mana_cost'] as String?,
    typeLine: row['type_line'] as String?,
    oracleText: row['oracle_text'] as String?,
    power: row['power'] as String?,
    toughness: row['toughness'] as String?,
    loyalty: row['loyalty'] as String?,
    defense: row['defense'] as String?,
    colors: _decodeList(row['colors'] as String?),
  );

  static List<String> _decodeList(String? raw) =>
      raw == null ? const [] : (jsonDecode(raw) as List).cast<String>();
}
