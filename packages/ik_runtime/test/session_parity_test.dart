import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  group('action progress parity', () {
    for (final fixture in loadParityFixtures('session/progress')) {
      test(fixture.name, () {
        final offsetsMs = fixture.inputField<List<Object?>>('offsetsMs');
        final saves = fixture.inputField<Map<String, Object?>>('saves');
        expect(
          checkParity(fixture, {
            for (final entry in saves.entries)
              entry.key: offsetsMs
                  .map(
                    (offsetMs) => actionProgressAt(
                      PlayerSave.fromJson(asJsonMap(entry.value)),
                      fixedTimestampMs + (offsetMs! as num),
                    ),
                  )
                  .toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('session tick parity', () {
    for (final fixture in loadParityFixtures('session/tick')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final seed = fixture.inputField<num>('seed').toInt();
        final offsetsMs = fixture.inputField<List<Object?>>('offsetsMs');
        // One generator for the whole run, so the recorded sequence only matches
        // if the port makes the same rolls in the same order.
        final random = Mulberry32(seed).asFunction;

        var save = saveOf(fixture);
        final steps = <Map<String, Object?>>[];
        for (final entry in offsetsMs) {
          final offsetMs = entry! as num;
          final nowMs = fixedTimestampMs + offsetMs;
          final result = advanceSession(db, save, nowMs, random);
          save = result.save;
          steps.add(<String, Object?>{
            'offsetMs': offsetMs,
            'changed': result.changed,
            'events': result.events.map((event) => event.toJson()).toList(),
            'progress': actionProgressAt(save, nowMs),
            'save': save.toJson(),
          });
        }

        expect(checkParity(fixture, <String, Object?>{'steps': steps}), isNull);
      });
    }
  });

  group('travel plan parity', () {
    for (final fixture in loadParityFixtures('session/travel')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final seed = fixture.inputField<num>('seed').toInt();
        final nowMs = fixture.inputField<num>('nowMs');
        final destinationId = fixture.inputField<String>('destinationId');

        final plan = planTravel(
          db,
          save,
          destinationId,
          fixture.inputField<String>('browseMapId'),
          nowMs,
          Mulberry32(seed).asFunction,
        );
        // A journey is only half the story, so the arrival that ends it is
        // recorded alongside the plan.
        final arrival = plan is TravelTimed
            ? arriveFromTravel(
                db,
                plan.save,
                destinationId,
                nowMs + plan.durationMs,
                Mulberry32(seed).asFunction,
              )
            : null;

        expect(
          checkParity(fixture, <String, Object?>{
            'plan': plan.toJson(),
            'arrival': arrival?.toJson(),
          }),
          isNull,
        );
      });
    }
  });

  group('save write pipeline parity', () {
    for (final fixture in loadParityFixtures('session/persist')) {
      test(fixture.name, () {
        final nowMs = fixture.inputField<num>('nowMs');
        expect(
          checkParity(
            fixture,
            prepareSaveForWrite(databaseOf(fixture), saveOf(fixture), nowMs + 90000).toJson(),
          ),
          isNull,
        );
      });
    }
  });
}

/// The clock every session fixture is anchored to: 2026-01-01T00:00:00.000Z.
const num fixedTimestampMs = 1767225600000;
