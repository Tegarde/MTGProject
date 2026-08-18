import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_collection/core/fts_query.dart';
import 'package:mtg_collection/core/image_urls.dart';
import 'package:mtg_collection/core/natural_sort.dart';

void main() {
  group('toFtsQuery', () {
    test('quotes tokens and adds prefix matching', () {
      expect(toFtsQuery('lightning bolt'), '"lightning"* "bolt"*');
    });

    test('strips FTS5 operator characters that would throw', () {
      // Raw input like this is what breaks a naive MATCH query.
      expect(toFtsQuery('Jace, the Mind Sculptor'), '"Jace"* "the"* "Mind"* "Sculptor"*');
      expect(toFtsQuery('fire (ice)'), '"fire"* "ice"*');
      expect(toFtsQuery('a-b'), '"ab"*');
    });

    test('returns null when nothing usable remains', () {
      expect(toFtsQuery(''), isNull);
      expect(toFtsQuery('   '), isNull);
      expect(toFtsQuery('***'), isNull);
    });
  });

  group('cardImageUrl', () {
    const id = '7673784e-db4b-43a1-8d55-1bb9fc1e284f';

    test('matches the verified CDN pattern', () {
      expect(
        cardImageUrl(id),
        'https://cards.scryfall.io/normal/front/7/6/$id.jpg',
      );
    });

    test('uses png extension for the png size', () {
      expect(cardImageUrl(id, size: ImageSize.png), endsWith('.png'));
    });

    test('supports back faces and art crops', () {
      expect(cardImageUrl(id, back: true), contains('/back/'));
      expect(cardImageUrl(id, size: ImageSize.artCrop), contains('/art_crop/'));
    });
  });

  group('compareNatural', () {
    test('orders digit runs numerically, not lexically', () {
      final numbers = ['10', '2', '1', '20']..sort(compareNatural);
      expect(numbers, ['1', '2', '10', '20']);
    });

    test('handles suffixed collector numbers', () {
      final numbers = ['12b', '12a', '2', '12']..sort(compareNatural);
      expect(numbers, ['2', '12', '12a', '12b']);
    });

    test('handles star and prefixed collector numbers', () {
      final numbers = ['101\u2605', '101', 'A-45']..sort(compareNatural);
      expect(numbers.first, '101');
    });
  });
}
