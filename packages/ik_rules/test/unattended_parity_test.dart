import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  group('unattended cap parity', () {
    for (final fixture in loadParityFixtures('unattended/cap')) {
      test(fixture.name, () {
        expect(checkParity(fixture, unattendedCapMs(databaseOf(fixture))), isNull);
      });
    }
  });

  group('unattended anchor parity', () {
    for (final fixture in loadParityFixtures('unattended/stamp')) {
      test(fixture.name, () {
        final save = saveOf(fixture);
        final nowMs = fixture.inputField<num>('nowMs');
        expect(
          checkParity(fixture, {
            'atPin': stampUnattendedProgressAt(save, nowMs).toJson(),
            'laterUnattendedProgressAt': stampUnattendedProgressAt(
              save,
              nowMs + 3600000,
            ).unattendedProgressAt,
          }),
          isNull,
        );
      });
    }
  });

  group('unattended catch-up parity', () {
    for (final fixture in loadParityFixtures('unattended/resolve')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final nowMs = fixture.inputField<num>('nowMs');
        final seed = fixture.inputField<num>('seed').toInt();
        final result = resolveUnattendedProgress(
          db,
          saveOf(fixture),
          nowMs,
          Mulberry32(seed).asFunction,
        );
        expect(checkParity(fixture, result.toJson()), isNull);
      });
    }
  });
}
