import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

PlayerSave _withCombatLevel(PlayerSave save, num level) {
  return save.copyWith(
    skills: save.skills
        .map((skill) => skill.skillId == combatSkillId ? skill.copyWith(level: level) : skill)
        .toList(),
  );
}

void main() {
  group('combat stat parity', () {
    for (final fixture in loadParityFixtures('combat/stats')) {
      if (fixture.name == 'level-thresholds') continue;
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        expect(
          checkParity(fixture, {
            'maxHp': playerMaxHp(db, save),
            'damageReduction': playerDamageReduction(db, save),
            'damageRange': playerDamageRange(db, save).toJson(),
            'offhandRange': playerOffhandDamageRange(db, save)?.toJson(),
            'levelMultiplier': combatLevelBonusMultiplier(save),
          }),
          isNull,
        );
      });
    }

    for (final fixture in loadParityFixtures('combat/stats')) {
      if (fixture.name != 'level-thresholds') continue;
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final byLevel = fixture.inputField<List<Object?>>('levels').map((value) {
          final level = value! as num;
          final save = _withCombatLevel(saveOf(fixture), level);
          return <String, Object?>{
            'level': level,
            'multiplier': combatLevelBonusMultiplier(save),
            'maxHp': playerMaxHp(db, save),
            'damageRange': playerDamageRange(db, save).toJson(),
          };
        }).toList();
        expect(checkParity(fixture, {'byLevel': byLevel}), isNull);
      });
    }
  });

  group('roll damage parity', () {
    for (final fixture in loadParityFixtures('combat/roll-damage')) {
      test(fixture.name, () {
        final seed = fixture.inputField<num>('seed').toInt();
        final count = fixture.inputField<num>('count').toInt();
        final random = Mulberry32(seed).asFunction;
        final rolls = List<num>.generate(count, (_) => rollDamage(10, 30, random));
        final swapped = Mulberry32(seed).asFunction;
        expect(
          checkParity(fixture, {
            'rolls': rolls,
            'swapped': List<num>.generate(count, (_) => rollDamage(30, 10, swapped)),
          }),
          isNull,
        );
      });
    }
  });

  group('mitigation parity', () {
    for (final fixture in loadParityFixtures('combat/mitigation')) {
      test(fixture.name, () {
        final results = fixture.inputField<List<Object?>>('cases').map((value) {
          final entry = (value! as List<Object?>).cast<num>();
          return applyMitigation(entry[0], entry[1], entry[2]);
        }).toList();
        expect(checkParity(fixture, {'results': results}), isNull);
      });
    }
  });
}
