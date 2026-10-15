import 'package:collection/collection.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

const _relIds = <String>[
  'REL-0001',
  'REL-0002',
  'REL-0003',
  'REL-0004',
  'REL-0005',
  'REL-0006',
  'REL-0007',
];
const _skillIds = <String>[
  'SKL-0001',
  'SKL-0002',
  'SKL-0003',
  'SKL-0004',
  'SKL-0005',
  'SKL-0006',
  'SKL-0007',
];
const _goldAmounts = <num>[0, 1, 7, 100, 12.5, -20];
const _nowMs = 1760486400000; // 2026-10-15T00:00:00.000Z
const _weekMs = 7 * 24 * 60 * 60 * 1000;
const _temple = 'LOC-0036';

PlayerSave _withTotalLevel(PlayerSave save, num target) {
  final bump = target - totalLevel(save);
  if (bump <= 0) return save;
  final first = save.skills.first;
  return save.copyWith(
    skills: <SkillProgress>[
      first.copyWith(level: first.level + bump),
      ...save.skills.skip(1),
    ],
  );
}

PlayerSave _atTemple(PlayerSave save, [num level = 100]) {
  return _withTotalLevel(save, level).copyWith(currentLocationId: _temple, gold: 100000);
}

Map<String, Object?> _chooseJson(ChooseReligionResult result) {
  if (!result.ok) return <String, Object?>{'ok': false, 'reason': result.reason};
  final save = result.save!;
  return <String, Object?>{
    'ok': true,
    'goldCost': result.goldCost,
    'religionId': save.religionId,
    'religionChangeCount': save.religionChangeCount,
    'religionHistory': save.religionHistory,
    'gold': save.gold,
    'religionChangedAt': save.religionChangedAt,
    'unlockedTitles': save.cosmetics.unlocked
        .where((id) => RegExp(r'^COS-001[3-9]$').hasMatch(id))
        .toList(),
    'equippedTitle': save.cosmetics.equipped['CSLOT-0003'],
    'acolyte': save.achievements.any((row) => row.achievementId == 'ACH-0050' && row.unlocked),
    'theologian': save.achievements.any((row) => row.achievementId == 'ACH-0051' && row.unlocked),
  };
}

void main() {
  group('religion catalog parity', () {
    for (final fixture in loadParityFixtures('religion/catalog')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        expect(
          checkParity(fixture, {
            'order': religions(db).map((row) => row.religionId).toList(),
            'names': religions(db).map((row) => religionDisplayName(db, row.religionId)).toList(),
            'gods': religions(db).map((row) => row.god).toList(),
            'titleKeys': religions(db).map((row) {
              final cosmetic = db.cosmetics
                  .where((entry) => entry.cosmeticId == row.titleCosmeticId)
                  .firstOrNull;
              if (cosmetic == null) return null;
              return db.items
                  .where((item) => item.itemId == cosmetic.itemId)
                  .firstOrNull
                  ?.internalKey;
            }).toList(),
            'missing': religionDisplayName(db, 'REL-9999'),
            'nullId': religionDisplayName(db, null),
            'foundById': _relIds.map((id) => religionById(db, id)?.religionId).toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('religion bonus parity', () {
    for (final fixture in loadParityFixtures('religion/bonuses')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final religionId = fixture.inputField<String>('religionId');
        expect(
          checkParity(fixture, {
            'bonusIds': religionBonusesFor(
              db,
              religionId,
            ).map((row) => row.religionBonusId).toList(),
            'summary': religionBonusSummaryLines(db, religionId),
            'skillDropChance': _skillIds
                .map((skillId) => alignmentSkillDropChanceBonusPercent(db, save, skillId))
                .toList(),
            'goldGain': alignmentGoldGainMultiplier(db, save),
            'appliedGold': _goldAmounts
                .map((amount) => applyAlignmentGoldGain(db, save, amount))
                .toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('religion alignment parity', () {
    for (final fixture in loadParityFixtures('religion/alignment')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        late Map<String, Object?> actual;
        switch (fixture.name) {
          case 'no-faith-wood-elf':
            final assigned = assignRace(db, createNewSave(db, _nowMs), 'RACE-0002');
            final save = assigned.save!;
            actual = <String, Object?>{
              'hunting': alignmentSkillDropChanceBonusPercent(db, save, 'SKL-0005'),
              'woodcutting': alignmentSkillDropChanceBonusPercent(db, save, 'SKL-0006'),
              'gold': applyAlignmentGoldGain(db, save, 100),
            };
          case 'faith-replaces-race':
            final assigned = assignRace(db, createNewSave(db, _nowMs), 'RACE-0002');
            final save = assigned.save!.copyWith(religionId: 'REL-0001');
            actual = <String, Object?>{
              'hunting': alignmentSkillDropChanceBonusPercent(db, save, 'SKL-0005'),
              'woodcutting': alignmentSkillDropChanceBonusPercent(db, save, 'SKL-0006'),
              'gold': applyAlignmentGoldGain(db, save, 100),
            };
          default:
            final save = createNewSave(db, _nowMs);
            actual = <String, Object?>{
              'hunting': alignmentSkillDropChanceBonusPercent(db, save, 'SKL-0005'),
              'gold': applyAlignmentGoldGain(db, save, 100),
            };
        }
        expect(checkParity(fixture, actual), isNull);
      });
    }
  });

  group('religion cost parity', () {
    for (final fixture in loadParityFixtures('religion/cost')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final none = _atTemple(createNewSave(db, _nowMs), 100);
        final following = none.copyWith(religionId: 'REL-0001');
        expect(
          checkParity(fixture, {
            'firstPick': religionChangeGoldCost(db, none),
            'at100': religionChangeGoldCost(db, following),
            'at101': religionChangeGoldCost(db, _withTotalLevel(following, 101)),
            'at250': religionChangeGoldCost(db, _withTotalLevel(following, 250)),
            'at500': religionChangeGoldCost(db, _withTotalLevel(following, 500)),
            'at999': religionChangeGoldCost(db, _withTotalLevel(following, 999)),
            'at1000': religionChangeGoldCost(db, _withTotalLevel(following, 1000)),
            'at1001': religionChangeGoldCost(db, _withTotalLevel(following, 1001)),
          }),
          isNull,
        );
      });
    }
  });

  group('religion choose parity', () {
    for (final fixture in loadParityFixtures('religion/choose')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final nowMs = fixture.inputField<num>('nowMs');
        late Object actual;
        switch (fixture.name) {
          case 'first-pick-free':
            actual = _chooseJson(
              chooseReligion(db, _atTemple(createNewSave(db, nowMs), 100), 'REL-0001', nowMs),
            );
          case 'level-99-refused':
            actual = _chooseJson(
              chooseReligion(db, _atTemple(createNewSave(db, nowMs), 99), 'REL-0001', nowMs),
            );
          case 'same-faith-retry':
            final first = chooseReligion(
              db,
              _atTemple(createNewSave(db, nowMs), 100),
              'REL-0001',
              nowMs,
            );
            actual = _chooseJson(chooseReligion(db, first.save!, 'REL-0001', nowMs + 1000));
          case 'cooldown-then-change':
            final first = chooseReligion(
              db,
              _atTemple(createNewSave(db, nowMs), 100),
              'REL-0001',
              nowMs,
            );
            final blocked = chooseReligion(db, first.save!, 'REL-0002', nowMs + 1000);
            final changed = chooseReligion(db, first.save!, 'REL-0002', nowMs + _weekMs);
            final retried = changed.ok
                ? chooseReligion(db, changed.save!, 'REL-0002', nowMs + _weekMs + 1)
                : changed;
            actual = <String, Object?>{
              'first': _chooseJson(first),
              'blocked': _chooseJson(blocked),
              'changed': _chooseJson(changed),
              'retried': _chooseJson(retried),
            };
          case 'theologian-once':
            var next = _atTemple(createNewSave(db, nowMs), 100);
            final steps = <Object?>[];
            for (var index = 0; index < _relIds.length; index += 1) {
              final result = chooseReligion(
                db,
                next.copyWith(gold: 100000),
                _relIds[index],
                nowMs + index * _weekMs,
              );
              steps.add(_chooseJson(result));
              if (!result.ok) break;
              next = result.save!;
            }
            actual = <String, Object?>{
              'steps': steps,
              'again': _chooseJson(
                chooseReligion(db, next, 'REL-0001', nowMs + _relIds.length * _weekMs),
              ),
            };
          default:
            actual = <String, Object?>{'unhandled': fixture.name};
        }
        expect(checkParity(fixture, actual), isNull);
      });
    }
  });
}
