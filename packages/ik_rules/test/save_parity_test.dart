import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

SaveJson _legacyOf(ParityFixture fixture, String key) =>
    asJsonMap(fixture.inputField<Map<String, Object?>>(key));

/// `{ok, save}` on success and `{ok, error}` on failure, matching the recorder.
Map<String, Object?> _migrationResult(SaveJson legacy, num nowMs) {
  try {
    return <String, Object?>{'ok': true, 'save': migrateSaveJson(legacy, nowMs)};
  } on SaveMigrationException catch (error) {
    return <String, Object?>{'ok': false, 'error': error.message};
  }
}

Map<String, Object?> _parseResult(Object? raw, num nowMs) {
  try {
    return <String, Object?>{'ok': true, 'save': parseSave(raw, nowMs).toJson()};
  } on SaveParseException catch (error) {
    return <String, Object?>{'ok': false, 'error': error.message};
  } on SaveMigrationException catch (error) {
    return <String, Object?>{'ok': false, 'error': error.message};
  }
}

void main() {
  group('new save parity', () {
    for (final fixture in loadParityFixtures('save/new')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final nowMs = fixture.inputField<num>('nowMs');
        expect(checkParity(fixture, createNewSave(db, nowMs).toJson()), isNull);
      });
    }
  });

  group('save migration parity', () {
    for (final fixture in loadParityFixtures('save/migrations')) {
      if (fixture.name != 'registry') continue;
      test(fixture.name, () {
        expect(
          checkParity(fixture, {
            'currentVersion': saveVersion,
            'steps': saveMigrations
                .map(
                  (entry) => <String, Object?>{
                    'fromVersion': entry.fromVersion,
                    'toVersion': entry.toVersion,
                  },
                )
                .toList(),
          }),
          isNull,
        );
      });
    }

    for (final fixture in loadParityFixtures('save/migrations')) {
      if (!fixture.name.startsWith('from-v')) continue;
      test(fixture.name, () {
        final nowMs = fixture.inputField<num>('nowMs');
        final result = _migrationResult(_legacyOf(fixture, 'legacy'), nowMs);
        expect(checkParity(fixture, result), isNull);
        // The point of the chain is a save the current schema can read.
        expect(() => PlayerSave.fromJson(asJsonMap(result['save'])), returnsNormally);
      });
    }

    for (final fixture in loadParityFixtures('save/migrations')) {
      if (fixture.name != 'unsupported') continue;
      test(fixture.name, () {
        final nowMs = fixture.inputField<num>('nowMs');
        final cases = fixture.inputField<List<Object?>>('cases');
        expect(
          checkParity(fixture, {
            for (final entry in cases.map(asJsonMap))
              entry['name']! as String: _migrationResult(asJsonMap(entry['legacy']), nowMs),
          }),
          isNull,
        );
      });
    }

    for (final fixture in loadParityFixtures('save/migrations')) {
      if (fixture.name != 'missing-timestamps') continue;
      test(fixture.name, () {
        final nowMs = fixture.inputField<num>('nowMs');
        expect(
          checkParity(fixture, {
            'withUpdatedAt': _migrationResult(_legacyOf(fixture, 'withUpdatedAt'), nowMs),
            'anchorless': _migrationResult(_legacyOf(fixture, 'anchorless'), nowMs),
          }),
          isNull,
        );
      });
    }
  });

  group('save parse parity', () {
    for (final fixture in loadParityFixtures('save/parse')) {
      if (fixture.name != 'guards') continue;
      test(fixture.name, () {
        final nowMs = fixture.inputField<num>('nowMs');
        final cases = fixture.inputField<List<Object?>>('cases');
        expect(checkParity(fixture, cases.map((raw) => _parseResult(raw, nowMs)).toList()), isNull);
      });
    }

    for (final fixture in loadParityFixtures('save/parse')) {
      if (fixture.name != 'round-trip') continue;
      test(fixture.name, () {
        final nowMs = fixture.inputField<num>('nowMs');
        expect(checkParity(fixture, _parseResult(_legacyOf(fixture, 'legacy'), nowMs)), isNull);
      });
    }
  });

  group('save touch parity', () {
    for (final fixture in loadParityFixtures('save/touch')) {
      test(fixture.name, () {
        final nowMs = fixture.inputField<num>('nowMs');
        expect(checkParity(fixture, touchSave(saveOf(fixture), nowMs).toJson()), isNull);
      });
    }
  });

  group('character name parity', () {
    for (final fixture in loadParityFixtures('save/character-name')) {
      test(fixture.name, () {
        final names = fixture.inputField<List<Object?>>('names').map((n) => n! as String);
        expect(
          checkParity(
            fixture,
            names
                .map(
                  (raw) => <String, Object?>{
                    'raw': raw,
                    'normalized': normalizeCharacterName(raw),
                    'valid': isValidCharacterName(raw),
                  },
                )
                .toList(),
          ),
          isNull,
        );
      });
    }
  });

  group('starting gear parity', () {
    for (final fixture in loadParityFixtures('save/starting-gear')) {
      test(fixture.name, () {
        final saves = fixture.inputField<Map<String, Object?>>('saves');
        expect(
          checkParity(fixture, {
            for (final entry in saves.entries)
              entry.key: ensureStartingHuntingTool(PlayerSave.fromJson(asJsonMap(entry.value)))
                  .toJson(),
          }),
          isNull,
        );
      });
    }
  });
}
