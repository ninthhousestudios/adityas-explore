import 'package:flutter_test/flutter_test.dart';

import 'package:explore/ui/being_slug.dart';

void main() {
  group('resolveBeingSlug', () {
    test(
      'resolves a companion being to its (sign, type), name left to content',
      () {
        final being = resolveBeingSlug('varuna-rishi');
        expect(being, isNotNull);
        expect(being!.sign, 4); // varuna is the 4th Aditya
        expect(being.type, 'rishi');
        expect(being.name, ''); // display name is async content
        expect(being.planet, ''); // not tied to a chart placement
      },
    );

    test('the aditya being carries the Aditya name synchronously', () {
      final being = resolveBeingSlug('aryama-aditya');
      expect(being, isNotNull);
      expect(being!.sign, 2);
      expect(being.type, 'aditya');
      expect(being.name, 'Aryama');
    });

    test('is case-insensitive on both segments', () {
      expect(resolveBeingSlug('VARUNA-Naga')?.sign, 4);
      expect(resolveBeingSlug('VARUNA-Naga')?.type, 'naga');
    });

    test('unknown Aditya → null', () {
      expect(resolveBeingSlug('surya-rishi'), isNull);
    });

    test('unknown being type → null', () {
      expect(resolveBeingSlug('varuna-emperor'), isNull);
    });

    test('ill-formed slugs → null (no arbitrary navigation)', () {
      expect(resolveBeingSlug('varuna'), isNull);
      expect(resolveBeingSlug('-rishi'), isNull);
      expect(resolveBeingSlug('varuna-'), isNull);
      expect(resolveBeingSlug(''), isNull);
    });
  });
}
