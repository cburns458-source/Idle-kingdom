import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

ActionRow _action(GameDatabase db, String actionId) {
  return db.actions.firstWhereOrNull((row) => row.actionId == actionId)!;
}

EquipmentRow? _equipment(GameDatabase db, String itemId) {
  return db.equipment.firstWhereOrNull((row) => row.itemId == itemId);
}

List<String> _stringList(ParityFixture fixture, String key) {
  return fixture.inputField<List<Object?>>(key).map((value) => value! as String).toList();
}

/// The save moved to where [activityId] lives, matching how the fixture was
/// recorded: validation only reaches its later gates when the player is there.
PlayerSave _atActivity(GameDatabase db, PlayerSave save, String activityId) {
  final activity = getActivity(db, activityId);
  return activity == null ? save : save.copyWith(currentLocationId: activity.locationId);
}

PlayerSave _withPotionSlot(PlayerSave save, EquippedStack? stack) {
  return save.copyWith(
    equipment: EquipmentLoadout(slots: {...save.equipment.slots, 'SLOT-0012': stack}),
  );
}

Map<String, Object?> _changeJson(ActivityChangeResult result) {
  return result.ok
      ? <String, Object?>{'ok': true, 'save': result.save!.toJson()}
      : <String, Object?>{'ok': false, 'reason': result.reason};
}

void main() {
  group('activity validation parity', () {
    for (final fixture in loadParityFixtures('activity/validate')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final byActivity = _stringList(fixture, 'activityIds').map((activityId) {
          final here = _atActivity(db, save, activityId);
          return <String, Object?>{
            'activityId': activityId,
            'found': getActivity(db, activityId) != null,
            'atOwnLocation': validateActivityStart(db, here, activityId).toJson(),
            'elsewhere': validateActivityStart(db, save, activityId).toJson(),
            'stillValid': activityStillValid(db, here, activityId),
          };
        }).toList();
        expect(checkParity(fixture, {'byActivity': byActivity}), isNull);
      });
    }
  });

  group('gathering duration parity', () {
    for (final fixture in loadParityFixtures('activity/gathering')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final byAction = _stringList(fixture, 'actionIds').map((actionId) {
          final action = _action(db, actionId);
          return <String, Object?>{
            'actionId': actionId,
            'duration': gatheringDurationMs(db, save, action),
            'xp': gatheringXpReward(db, save, action),
            'below': isBelowProficiency(save, action),
            'overrideXp': gatheringXpReward(db, save, action, 100),
            'zeroXp': gatheringXpReward(db, save, action, 0),
          };
        }).toList();
        expect(checkParity(fixture, {'byAction': byAction}), isNull);
      });
    }
  });

  group('bonus xp parity', () {
    for (final fixture in loadParityFixtures('activity/bonus-xp')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final byAction = db.actions
            .map(
              (action) => <String, Object?>{
                'actionId': action.actionId,
                'bonus': bonusSkillXpForAction(action.actionId)?.toJson(),
              },
            )
            .where((row) => row['bonus'] != null)
            .toList();
        expect(
          checkParity(fixture, {
            'byAction': byAction,
            'hunting': bowHuntingCombatXpBonus(db, save, 'SKL-0005', 400)?.toJson(),
            'nonHunting': bowHuntingCombatXpBonus(db, save, 'SKL-0001', 400)?.toJson(),
            'zeroXp': bowHuntingCombatXpBonus(db, save, 'SKL-0005', 0)?.toJson(),
          }),
          isNull,
        );
      });
    }
  });

  group('reward summary parity', () {
    for (final fixture in loadParityFixtures('activity/reward-summary')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final lines = const <String>['SKL-0001', 'SKL-0007', 'SKL-9999']
            .expand(
              (skillId) => <Object?>[
                summarizeXpReward(db, save, skillId, 120, null)?.toJson(),
                summarizeXpReward(db, save, skillId, 120, 14)?.toJson(),
                summarizeXpReward(db, save, skillId, 0, null)?.toJson(),
              ],
            )
            .toList();
        expect(checkParity(fixture, {'lines': lines}), isNull);
      });
    }
  });

  group('action reward parity', () {
    for (final fixture in loadParityFixtures('activity/rewards')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final rewarded = resolveActionRewards(
          db,
          saveOf(fixture),
          _action(db, fixture.inputField<String>('actionId')),
          Mulberry32(fixture.inputField<num>('seed').toInt()).asFunction,
        );
        expect(
          checkParity(fixture, {
            'save': rewarded.save.toJson(),
            'loot': rewarded.loot.map((grant) => grant.toJson()).toList(),
            'goldGained': rewarded.goldGained,
          }),
          isNull,
        );
      });
    }
  });

  group('gathering completion parity', () {
    for (final fixture in loadParityFixtures('activity/complete')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final completed = completeGatheringAction(
          db,
          saveOf(fixture),
          _action(db, fixture.inputField<String>('actionId')),
          Mulberry32(fixture.inputField<num>('seed').toInt()).asFunction,
        );
        expect(
          checkParity(fixture, {
            'save': completed.save.toJson(),
            'result': completed.result.toJson(),
          }),
          isNull,
        );
      });
    }
  });

  group('action generation parity', () {
    for (final fixture in loadParityFixtures('activity/generate')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final activityId = fixture.inputField<String>('activityId');
        final generated = generateNextAction(
          db,
          _atActivity(db, saveOf(fixture), activityId),
          activityId,
          Mulberry32(fixture.inputField<num>('seed').toInt()).asFunction,
          fixture.inputField<num>('nowMs'),
        );
        expect(
          checkParity(
            fixture,
            generated == null
                ? null
                : <String, Object?>{
                    'actionId': generated.action.actionId,
                    'state': generated.state?.toJson(),
                    'save': generated.save.toJson(),
                  },
          ),
          isNull,
        );
      });
    }
  });

  group('activity save state parity', () {
    for (final fixture in loadParityFixtures('activity/save-state')) {
      test(fixture.name, () {
        final queued = saveOf(fixture);
        final begun = beginActivitySave(queued, 'ACT-0001', fixture.inputField<String>('nowIso'));
        final cleared = clearActivitySave(begun, jsDateParse(fixture.inputField<String>('nowIso')));
        expect(
          checkParity(fixture, {
            'begun': begun.toJson(),
            'cleared': cleared.toJson(),
            'restored': restoreActiveActionState(queued)?.toJson(),
            'restoredEmpty': restoreActiveActionState(cleared)?.toJson(),
            'running': <bool>[
              hasRunningPrimaryActivity(queued),
              hasRunningPrimaryActivity(cleared),
            ],
          }),
          isNull,
        );
      });
    }
  });

  group('activity stop parity', () {
    for (final fixture in loadParityFixtures('activity/transition')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final nowMs = fixture.inputField<num>('nowMs');
        expect(
          checkParity(fixture, {
            'stopNow': stopPrimaryActivityNow(db, save, nowMs).toJson(),
            'travel': beginTravelActivityChange(db, save, nowMs).toJson(),
            'request': _changeJson(requestActivityStop(db, save, nowMs)),
            'clearedTransition': clearActivityTransition(save).toJson(),
          }),
          isNull,
        );
      });
    }
  });

  group('activity start request parity', () {
    for (final fixture in loadParityFixtures('activity/request-start')) {
      if (fixture.name == 'death-paused') continue;
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final activityId = fixture.inputField<String>('activityId');
        final started = requestActivityStart(
          db,
          _atActivity(db, saveOf(fixture), activityId),
          activityId,
          fixture.inputField<num>('nowMs'),
          Mulberry32(fixture.inputField<num>('seed').toInt()).asFunction,
        );
        expect(checkParity(fixture, _changeJson(started)), isNull);
      });
    }

    for (final fixture in loadParityFixtures('activity/request-start')) {
      if (fixture.name != 'death-paused') continue;
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final nowMs = fixture.inputField<num>('nowMs');
        expect(
          checkParity(fixture, {
            'start': _changeJson(
              requestActivityStart(
                db,
                save,
                fixture.inputField<String>('activityId'),
                nowMs,
                Mulberry32(0).asFunction,
              ),
            ),
            'stop': _changeJson(requestActivityStop(db, save, nowMs)),
            'stopNow': stopPrimaryActivityNow(db, save, nowMs).toJson(),
          }),
          isNull,
        );
      });
    }
  });

  group('production start request parity', () {
    for (final fixture in loadParityFixtures('activity/request-production')) {
      test(fixture.name, () {
        final started = requestProductionStart(
          databaseOf(fixture),
          saveOf(fixture),
          fixture.inputField<String>('activityId'),
          fixture.inputField<String>('recipeId'),
          fixture.inputField<num>('quantity'),
          fixture.inputField<num>('nowMs'),
        );
        expect(checkParity(fixture, _changeJson(started)), isNull);
      });
    }
  });

  group('legacy transition parity', () {
    for (final fixture in loadParityFixtures('activity/resolve-transitions')) {
      test(fixture.name, () {
        final resolved = resolveActivityTransitions(
          databaseOf(fixture),
          saveOf(fixture),
          fixture.inputField<num>('nowMs'),
          Mulberry32(fixture.inputField<num>('seed').toInt()).asFunction,
        );
        expect(checkParity(fixture, {'resolved': resolved.toJson()}), isNull);
      });
    }
  });

  group('potion effect parity', () {
    for (final fixture in loadParityFixtures('potions/effects')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final parsed = _stringList(fixture, 'itemIds')
            .map(
              (itemId) => <String, Object?>{
                'itemId': itemId,
                'effect': parsePotionEffect(_equipment(db, itemId), itemId)?.toJson(),
              },
            )
            .toList();
        expect(
          checkParity(fixture, {
            'parsed': parsed,
            'missingRow': parsePotionEffect(null, 'ITEM-0070')?.toJson(),
          }),
          isNull,
        );
      });
    }
  });

  group('potion consumption parity', () {
    for (final fixture in loadParityFixtures('potions/consume')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final scope = fixture.inputField<String>('scope');
        final save = saveOf(fixture);
        final consumed = tryConsumePotionForScope(db, save, scope);
        final lastOne = tryConsumePotionForScope(
          db,
          _withPotionSlot(save, EquippedStack(itemId: 'ITEM-0071', quantity: 1)),
          scope,
        );
        final emptySlot = tryConsumePotionForScope(db, _withPotionSlot(save, null), scope);
        expect(
          checkParity(fixture, {
            'consumed': <String, Object?>{
              'save': consumed.save.toJson(),
              'consumed': consumed.consumed,
              'effect': consumed.effect?.toJson(),
              'potionName': consumed.potionName,
            },
            'lastOne': <String, Object?>{
              'save': lastOne.save.toJson(),
              'consumed': lastOne.consumed,
            },
            'emptySlot': <String, Object?>{
              'save': emptySlot.save.toJson(),
              'consumed': emptySlot.consumed,
            },
            'cleared': clearActivePotionEffect(consumed.save).toJson(),
          }),
          isNull,
        );
      });
    }
  });

  group('potion modifier parity', () {
    for (final fixture in loadParityFixtures('potions/apply')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final dropEffect = parsePotionEffect(_equipment(db, 'ITEM-0070'), 'ITEM-0070');
        final durationEffect = parsePotionEffect(_equipment(db, 'ITEM-0071'), 'ITEM-0071');
        final poisonEffect = parsePotionEffect(_equipment(db, 'ITEM-0073'), 'ITEM-0073');
        expect(
          checkParity(fixture, {
            'dropChance': const <num?>[
              10,
              90,
              0,
              null,
            ].map((base) => applyPotionDropChance(base, dropEffect)).toList(),
            'dropChanceNoEffect': applyPotionDropChance(10, null),
            'durations': const <num>[
              0,
              1000,
              20000,
              33333,
            ].map((ms) => applyPotionDurationMs(ms, durationEffect)).toList(),
            'durationsNoEffect': <num>[applyPotionDurationMs(20000, null)],
            'poison': const <num>[
              0,
              100,
              1250,
            ].map((hp) => potionEnemyMaxHpDamage(hp, poisonEffect)).toList(),
            'poisonNoEffect': potionEnemyMaxHpDamage(1250, durationEffect),
          }),
          isNull,
        );
      });
    }
  });
}
