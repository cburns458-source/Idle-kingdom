import 'package:collection/collection.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  group('config number parity', () {
    for (final fixture in loadParityFixtures('config/numbers')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final values = fixture
            .inputField<List<Object?>>('keys')
            .map((key) => configNumber(db, key! as String, -1))
            .toList();
        expect(checkParity(fixture, {'values': values}), isNull);
      });
    }
  });

  group('selectable action parity', () {
    for (final fixture in loadParityFixtures('pools/selectable')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final actions = db.actions
            .map(
              (action) => <String, Object?>{
                'actionId': action.actionId,
                'selectable': isSelectableAction(action),
              },
            )
            .toList();
        expect(checkParity(fixture, {'actions': actions}), isNull);
      });
    }
  });

  group('eligible pool entry parity', () {
    for (final fixture in loadParityFixtures('pools/eligible')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final poolIds = <String>{};
        for (final entry in db.poolEntries) {
          poolIds.add(entry.poolId);
        }
        final pools = poolIds
            .map(
              (poolId) => <String, Object?>{
                'poolId': poolId,
                'actionIds': eligiblePoolEntries(
                  db,
                  poolId,
                ).map((pair) => pair.action.actionId).toList(),
              },
            )
            .toList();
        expect(checkParity(fixture, {'pools': pools}), isNull);
      });
    }
  });

  group('weighted pick parity', () {
    for (final fixture in loadParityFixtures('pools/pick')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final entries = eligiblePoolEntries(db, fixture.inputField<String>('poolId'));
        final seed = fixture.inputField<num>('seed').toInt();
        final random = Mulberry32(seed).asFunction;
        final picks = List<String?>.generate(
          fixture.inputField<num>('count').toInt(),
          (_) => pickWeightedAction(entries, random)?.actionId,
        );
        expect(
          checkParity(fixture, {
            'picks': picks,
            'empty': pickWeightedAction(
              const <PoolCandidate>[],
              Mulberry32(seed).asFunction,
            )?.actionId,
          }),
          isNull,
        );
      });
    }
  });

  group('drop chance tag parity', () {
    for (final fixture in loadParityFixtures('loot/drop-chance-tags')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        expect(
          checkParity(fixture, {
            'parsed': fixture
                .inputField<List<Object?>>('strings')
                .map(parseRelativeDropChanceBonusPercent)
                .toList(),
            'allEquipment': db.equipment
                .map(
                  (row) => <String, Object?>{
                    'itemId': row.itemId,
                    'bonus': parseRelativeDropChanceBonusPercent(row.raw['Capabilities / Effects']),
                  },
                )
                .toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('drop chance parity', () {
    for (final fixture in loadParityFixtures('loot/drop-chance')) {
      if (fixture.name == 'apply-relative') continue;
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        expect(
          checkParity(fixture, {
            'equipped': equippedRelativeDropChanceBonusPercent(db, save),
            'total': totalRelativeDropChanceBonusPercent(db, save),
          }),
          isNull,
        );
      });
    }

    for (final fixture in loadParityFixtures('loot/drop-chance')) {
      if (fixture.name != 'apply-relative') continue;
      test(fixture.name, () {
        final results = fixture.inputField<List<Object?>>('cases').map((value) {
          final entry = value! as List<Object?>;
          return applyRelativeDropChance(entry[0] as num?, entry[1]! as num);
        }).toList();
        expect(checkParity(fixture, {'results': results}), isNull);
      });
    }
  });

  group('locale compare parity', () {
    for (final fixture in loadParityFixtures('js-compat/locale-compare')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final signs = fixture.inputField<List<Object?>>('pairs').map((value) {
          final pair = (value! as List<Object?>).cast<String>();
          return jsLocaleCompare(pair[0], pair[1]);
        }).toList();
        final names = db.items.map((row) => row.displayName).toList();
        mergeSort<String>(names, compare: jsLocaleCompare);
        expect(checkParity(fixture, {'signs': signs, 'sortedItemNames': names}), isNull);
      });
    }
  });
}
