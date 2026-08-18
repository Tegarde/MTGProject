import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_collection/models/collection_entry.dart';

void main() {
  group('CardCondition', () {
    test('round-trips through its Firestore code', () {
      for (final condition in CardCondition.values) {
        expect(CardConditionCode.fromCode(condition.code), condition);
      }
    });

    test('falls back to NM for an unrecognized code', () {
      expect(CardConditionCode.fromCode('???'), CardCondition.nm);
    });
  });

  group('CollectionEntry', () {
    const entry = CollectionEntry(
      printingId: '7673784e-db4b-43a1-8d55-1bb9fc1e284f',
      oracleId: '4457ed35-7c10-48c8-9776-456485fdf070',
      setCode: 'clu',
      name: 'Lightning Bolt',
      quantity: 4,
      finish: 'nonfoil',
      language: 'en',
      condition: CardCondition.nm,
    );

    test('entryId is a deterministic composite of the identifying fields', () {
      expect(
        entry.entryId,
        '7673784e-db4b-43a1-8d55-1bb9fc1e284f_nonfoil_NM_en',
      );
    });

    test('two entries with the same printing/finish/condition/language collide', () {
      final other = entry.copyWith(quantity: 1);
      expect(other.entryId, entry.entryId);
    });

    test('a different finish produces a different entryId', () {
      final foil = CollectionEntry(
        printingId: entry.printingId,
        oracleId: entry.oracleId,
        setCode: entry.setCode,
        name: entry.name,
        quantity: entry.quantity,
        finish: 'foil',
        language: entry.language,
        condition: entry.condition,
      );
      expect(foil.entryId, isNot(entry.entryId));
    });

    test('toMap/fromMap round-trips the fields it manages', () {
      final map = entry.toMap();
      final restored = CollectionEntry.fromMap(map);

      expect(restored.printingId, entry.printingId);
      expect(restored.oracleId, entry.oracleId);
      expect(restored.setCode, entry.setCode);
      expect(restored.name, entry.name);
      expect(restored.quantity, entry.quantity);
      expect(restored.finish, entry.finish);
      expect(restored.language, entry.language);
      expect(restored.condition, entry.condition);
      expect(restored.notes, entry.notes);
      expect(restored.orphaned, entry.orphaned);
    });

    test('copyWith only replaces the given fields', () {
      final updated = entry.copyWith(quantity: 2, notes: 'traded for 1', orphaned: true);
      expect(updated.quantity, 2);
      expect(updated.notes, 'traded for 1');
      expect(updated.orphaned, isTrue);
      expect(updated.printingId, entry.printingId);
      expect(updated.finish, entry.finish);
    });
  });
}
