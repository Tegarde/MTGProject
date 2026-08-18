/// Physical condition of an owned card, per planning/04-firestore-model.md §3.
enum CardCondition { nm, lp, mp, hp, dmg }

extension CardConditionCode on CardCondition {
  String get code => switch (this) {
    CardCondition.nm => 'NM',
    CardCondition.lp => 'LP',
    CardCondition.mp => 'MP',
    CardCondition.hp => 'HP',
    CardCondition.dmg => 'DMG',
  };

  static CardCondition fromCode(String code) => CardCondition.values.firstWhere(
    (c) => c.code == code,
    orElse: () => CardCondition.nm,
  );
}

/// One document under `users/{uid}/collection/{entryId}` — a distinct thing
/// the user owns (a printing in a given finish, condition, and language).
///
/// Framework-free per planning/07-conventions.md: no `cloud_firestore`
/// import. [FirestoreCollectionRepository] converts to/from Firestore's
/// `Map<String, dynamic>` (with `Timestamp` swapped for [DateTime]).
class CollectionEntry {
  const CollectionEntry({
    required this.printingId,
    required this.oracleId,
    required this.setCode,
    required this.name,
    required this.quantity,
    required this.finish,
    required this.language,
    required this.condition,
    this.notes = '',
    this.orphaned = false,
    this.addedAt,
    this.updatedAt,
  });

  final String printingId;
  final String oracleId;
  final String setCode;
  final String name;
  final int quantity;

  /// `nonfoil` | `foil` | `etched` — see [Printing.finishes].
  final String finish;

  /// IETF language tag, e.g. `en`.
  final String language;
  final CardCondition condition;
  final String notes;
  final bool orphaned;
  final DateTime? addedAt;
  final DateTime? updatedAt;

  /// Deterministic composite id: `{printingId}_{finish}_{condition}_{language}`.
  ///
  /// Makes "add one more of this exact card" an idempotent write instead of a
  /// query-then-write, and makes duplicate documents structurally impossible.
  String get entryId => idFor(
    printingId: printingId,
    finish: finish,
    condition: condition,
    language: language,
  );

  static String idFor({
    required String printingId,
    required String finish,
    required CardCondition condition,
    required String language,
  }) => '${printingId}_${finish}_${condition.code}_$language';

  CollectionEntry copyWith({int? quantity, String? notes, bool? orphaned}) => CollectionEntry(
    printingId: printingId,
    oracleId: oracleId,
    setCode: setCode,
    name: name,
    quantity: quantity ?? this.quantity,
    finish: finish,
    language: language,
    condition: condition,
    notes: notes ?? this.notes,
    orphaned: orphaned ?? this.orphaned,
    addedAt: addedAt,
    updatedAt: updatedAt,
  );

  factory CollectionEntry.fromMap(Map<String, dynamic> map) => CollectionEntry(
    printingId: map['printingId'] as String,
    oracleId: map['oracleId'] as String,
    setCode: map['setCode'] as String,
    name: map['name'] as String,
    quantity: (map['quantity'] as num).toInt(),
    finish: map['finish'] as String,
    language: map['language'] as String,
    condition: CardConditionCode.fromCode(map['condition'] as String),
    notes: map['notes'] as String? ?? '',
    orphaned: map['orphaned'] as bool? ?? false,
    addedAt: map['addedAt'] as DateTime?,
    updatedAt: map['updatedAt'] as DateTime?,
  );

  /// Excludes `addedAt`/`updatedAt`; the repository stamps those with the
  /// server timestamp on write rather than a client clock.
  Map<String, dynamic> toMap() => {
    'printingId': printingId,
    'oracleId': oracleId,
    'setCode': setCode,
    'name': name,
    'quantity': quantity,
    'finish': finish,
    'language': language,
    'condition': condition.code,
    'notes': notes,
    'orphaned': orphaned,
  };
}
