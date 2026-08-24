import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

const _raceIds = <String>[
  'RACE-0001',
  'RACE-0002',
  'RACE-0003',
  'RACE-0004',
  'RACE-0005',
  'RACE-0006',
  'RACE-0007',
];
const _skillIds = <String>[
  'SKL-0001',
  'SKL-0002',
  'SKL-0003',
  'SKL-0004',
  'SKL-0005',
  'SKL-0006',
  'SKL-0007',
  'SKL-9999',
];
const _goldAmounts = <num>[0, 1, 7, 100, 12.5, -20];
const _hostilityLocations = <String>['LOC-0002', 'LOC-0003', 'LOC-9999'];

void main() {
  group('race catalog parity', () {
    for (final fixture in loadParityFixtures('races/catalog')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        expect(
          checkParity(fixture, {
            'order': races(db).map((row) => row.raceId).toList(),
            'names': races(db).map((row) => raceDisplayName(db, row.raceId)).toList(),
            'missing': raceDisplayName(db, 'RACE-9999'),
            'nullId': raceDisplayName(db, null),
            'foundById': _raceIds.map((raceId) => raceById(db, raceId)?.raceId).toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('race bonus parity', () {
    for (final fixture in loadParityFixtures('races/bonuses')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final raceId = fixture.inputField<String>('raceId');
        expect(
          checkParity(fixture, {
            'bonusIds': raceBonusesFor(db, raceId).map((row) => row.raceBonusId).toList(),
            'summary': raceBonusSummaryLines(db, raceId),
            'startingItemIds': raceStartingItems(
              db,
              raceId,
            ).map((row) => row.raceStartingItemId).toList(),
            'miningStoreLevel': dwarvenMiningStoreRequiredLevel(save),
            'maxHp': raceMaxHpMultiplier(db, save),
            'goldGain': raceGoldGainMultiplier(db, save),
            'skillDropChance': _skillIds
                .map((skillId) => raceSkillDropChanceBonusPercent(db, save, skillId))
                .toList(),
            'appliedGold': _goldAmounts
                .map((amount) => applyRaceGoldGain(db, save, amount))
                .toList(),
            'hostility': _hostilityLocations
                .map((locationId) => raceBypassesForcedHostilityAt(db, save, locationId))
                .toList(),
          }),
          isNull,
        );
      });
    }

    for (final fixture in loadParityFixtures('races/no-race')) {
      test('no race ${fixture.name}', () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        expect(
          checkParity(fixture, {
            'bonusIds': raceBonusesFor(db, null).map((row) => row.raceBonusId).toList(),
            'miningStoreLevel': dwarvenMiningStoreRequiredLevel(save),
            'maxHp': raceMaxHpMultiplier(db, save),
            'goldGain': raceGoldGainMultiplier(db, save),
            'hostility': _hostilityLocations
                .map((locationId) => raceBypassesForcedHostilityAt(db, save, locationId))
                .toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('race starting kit parity', () {
    for (final fixture in loadParityFixtures('races/starting-kit')) {
      test(fixture.name, () {
        final granted = grantRaceStartingItems(
          databaseOf(fixture),
          saveOf(fixture),
          fixture.inputField<String>('raceId'),
        );
        expect(checkParity(fixture, {'save': granted.toJson()}), isNull);
      });
    }
  });

  group('assign race parity', () {
    for (final fixture in loadParityFixtures('races/assign')) {
      test(fixture.name, () {
        final result = assignRace(
          databaseOf(fixture),
          saveOf(fixture),
          fixture.inputField<String>('raceId'),
        );
        expect(
          checkParity(
            fixture,
            result.ok
                ? <String, Object?>{
                    'ok': true,
                    'grantedStarterKit': result.grantedStarterKit,
                    'save': result.save!.toJson(),
                  }
                : <String, Object?>{'ok': false, 'reason': result.reason},
          ),
          isNull,
        );
      });
    }
  });
}
