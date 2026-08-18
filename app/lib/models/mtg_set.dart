/// A Magic set (expansion, core set, commander deck, token sheet, and so on).
class MtgSet {
  const MtgSet({
    required this.code,
    required this.scryfallId,
    required this.name,
    required this.setType,
    required this.cardCount,
    this.releasedAt,
    this.parentSetCode,
    this.blockCode,
    this.block,
    this.digital = false,
    this.foilOnly = false,
    this.nonfoilOnly = false,
    this.iconSvgUri,
  });

  final String code;
  final String scryfallId;
  final String name;
  final String setType;
  final int cardCount;
  final String? releasedAt;
  final String? parentSetCode;
  final String? blockCode;
  final String? block;
  final bool digital;
  final bool foilOnly;
  final bool nonfoilOnly;

  /// Scryfall asks that icons be cached locally rather than hotlinked.
  final String? iconSvgUri;

  bool get isToken => setType == 'token';

  factory MtgSet.fromRow(Map<String, dynamic> row) => MtgSet(
    code: row['code'] as String,
    scryfallId: row['scryfall_id'] as String,
    name: row['name'] as String,
    setType: row['set_type'] as String,
    cardCount: row['card_count'] as int,
    releasedAt: row['released_at'] as String?,
    parentSetCode: row['parent_set_code'] as String?,
    blockCode: row['block_code'] as String?,
    block: row['block'] as String?,
    digital: (row['digital'] as int?) == 1,
    foilOnly: (row['foil_only'] as int?) == 1,
    nonfoilOnly: (row['nonfoil_only'] as int?) == 1,
    iconSvgUri: row['icon_svg_uri'] as String?,
  );
}
