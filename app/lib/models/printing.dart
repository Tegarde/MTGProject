import 'dart:convert';

/// One physical printing of a card.
///
/// Mirrors the `printings` table in planning/02-catalog-schema.md. Deliberately
/// slim: no rules text, no image URLs, no prices.
class Printing {
  const Printing({
    required this.scryfallId,
    required this.oracleId,
    required this.setCode,
    required this.collectorNumber,
    required this.rarity,
    required this.finishes,
    required this.lang,
    required this.imageStatus,
    required this.twoSidedImage,
    this.artist,
    this.releasedAt,
    this.borderColor,
    this.frame,
    this.promo = false,
    this.fullArt = false,
    this.textless = false,
    this.variation = false,
    this.oversized = false,
    this.digital = false,
    this.booster = false,
  });

  final String scryfallId;
  final String oracleId;
  final String setCode;
  final String collectorNumber;
  final String rarity;
  final List<String> finishes;
  final String lang;
  final String imageStatus;
  final bool twoSidedImage;
  final String? artist;
  final String? releasedAt;
  final String? borderColor;
  final String? frame;
  final bool promo;
  final bool fullArt;
  final bool textless;
  final bool variation;
  final bool oversized;
  final bool digital;
  final bool booster;

  bool get hasImage => imageStatus != 'missing';

  factory Printing.fromRow(Map<String, dynamic> row) => Printing(
    scryfallId: row['scryfall_id'] as String,
    oracleId: row['oracle_id'] as String,
    setCode: row['set_code'] as String,
    collectorNumber: row['collector_number'] as String,
    rarity: row['rarity'] as String,
    finishes: (jsonDecode(row['finishes'] as String) as List).cast<String>(),
    lang: row['lang'] as String,
    imageStatus: row['image_status'] as String,
    twoSidedImage: (row['two_sided_image'] as int) == 1,
    artist: row['artist'] as String?,
    releasedAt: row['released_at'] as String?,
    borderColor: row['border_color'] as String?,
    frame: row['frame'] as String?,
    promo: (row['promo'] as int?) == 1,
    fullArt: (row['full_art'] as int?) == 1,
    textless: (row['textless'] as int?) == 1,
    variation: (row['variation'] as int?) == 1,
    oversized: (row['oversized'] as int?) == 1,
    digital: (row['digital'] as int?) == 1,
    booster: (row['booster'] as int?) == 1,
  );
}
