import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  group('mulberry32 parity', () {
    final fixtures = loadParityFixtures('rng');

    test('covers every recorded seed', () {
      expect(fixtures, isNotEmpty);
    });

    for (final fixture in fixtures) {
      test(fixture.name, () {
        final seed = fixture.inputField<int>('seed');
        final draws = fixture.inputField<int>('draws');
        final actual = {'values': Mulberry32(seed).drawSequence(draws)};
        expect(checkParity(fixture, actual), isNull);
      });
    }
  });

  group('canonical number parity', () {
    for (final fixture in loadParityFixtures('parity')) {
      test(fixture.name, () {
        final values = fixture.inputField<List<Object?>>('values');
        final actual = {'encoded': values.map((value) => canonicalNumber(value as num)).toList()};
        expect(checkParity(fixture, actual), isNull);
      });
    }
  });
}
