import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

ActionRow _action(GameDatabase db, String actionId) {
  return db.actions.firstWhereOrNull((row) => row.actionId == actionId)!;
}

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

  group('enemy lookup parity', () {
    for (final fixture in loadParityFixtures('combat/lookups')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final enemyIds = fixture
            .inputField<List<Object?>>('enemyIds')
            .map((value) => value! as String)
            .toList();
        expect(
          checkParity(fixture, {
            'enemies': enemyIds.map((enemyId) => getEnemy(db, enemyId)?.enemyId).toList(),
            'byAction': const <String>['ACN-0003', 'ACN-0006', 'ACN-0009', 'ACN-0046']
                .map(
                  (actionId) => <String, Object?>{
                    'actionId': actionId,
                    'enemyId': enemyForAction(db, _action(db, actionId))?.enemyId,
                  },
                )
                .toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('combat begin parity', () {
    for (final fixture in loadParityFixtures('combat/begin')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final begun = beginCombatSave(
          db,
          saveOf(fixture),
          _action(db, 'ACN-0003'),
          getEnemy(db, 'ENM-0003')!,
          fixture.inputField<String>('nowIso'),
        );
        expect(
          checkParity(fixture, {
            'begun': begun.toJson(),
            'cleared': clearCombatSave(begun).toJson(),
          }),
          isNull,
        );
      });
    }
  });

  group('combat round parity', () {
    for (final fixture in loadParityFixtures('combat/rounds')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final enemy = getEnemy(db, fixture.inputField<String>('enemyId'))!;
        final random = Mulberry32(fixture.inputField<num>('seed').toInt()).asFunction;
        var save = saveOf(fixture);
        num enemyHp = enemy.maximumHp;
        final rounds = <Object?>[];
        for (var index = 0; index < fixture.inputField<num>('rounds'); index += 1) {
          final round = resolveCombatRound(db, save, enemy, enemyHp, random);
          rounds.add(round.toJson());
          enemyHp = round.enemyHp;
          save = save.copyWith(currentHp: round.playerHp, combatEnemyHp: round.enemyHp);
          if (round.outcome != 'ongoing') break;
        }
        expect(checkParity(fixture, {'rounds': rounds, 'save': save.toJson()}), isNull);
      });
    }
  });

  group('combat victory parity', () {
    for (final fixture in loadParityFixtures('combat/victory')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final result = applyCombatVictory(
          db,
          saveOf(fixture),
          _action(db, 'ACN-0003'),
          getEnemy(db, 'ENM-0003')!,
          Mulberry32(fixture.inputField<num>('seed').toInt()).asFunction,
          fixture.inputField<num>('nowMs'),
        );
        expect(
          checkParity(fixture, {
            'save': result.save.toJson(),
            'xpGained': result.xpGained,
            'goldGained': result.goldGained,
            'loot': result.loot.map((grant) => grant.toJson()).toList(),
            'foodConsumed': result.foodConsumed,
            'foodHealed': result.foodHealed,
            'foodName': result.foodName,
          }),
          isNull,
        );
      });
    }
  });

  group('post-victory food parity', () {
    for (final fixture in loadParityFixtures('combat/food')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final healed = tryConsumeFoodAfterVictory(db, saveOf(fixture).copyWith(currentHp: 5));
        final full = tryConsumeFoodAfterVictory(db, saveOf(fixture).copyWith(currentHp: 99999));
        expect(
          checkParity(fixture, {
            'hurt': <String, Object?>{
              'save': healed.save.toJson(),
              'consumed': healed.consumed,
              'healed': healed.healed,
              'foodName': healed.foodName,
            },
            'full': <String, Object?>{
              'save': full.save.toJson(),
              'consumed': full.consumed,
              'healed': full.healed,
            },
          }),
          isNull,
        );
      });
    }
  });

  group('combat defeat parity', () {
    for (final fixture in loadParityFixtures('combat/defeat')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final nowMs = fixture.inputField<num>('nowMs');
        final defeated = applyCombatDefeat(db, save, nowMs);
        expect(
          checkParity(fixture, {
            'save': defeated.toJson(),
            'paused': isDeathPaused(defeated, nowMs),
            'pausedLater': isDeathPaused(defeated, nowMs + 60000),
            'remaining': deathPauseRemainingMs(defeated, nowMs),
            'remainingLater': deathPauseRemainingMs(defeated, nowMs + 60000),
            'noPause': isDeathPaused(save, nowMs),
            'noPauseRemaining': deathPauseRemainingMs(save, nowMs),
          }),
          isNull,
        );
      });
    }
  });
}
