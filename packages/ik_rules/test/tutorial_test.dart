import 'dart:convert';

import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

/// Mirrors `src/game/tutorial/tutorial.test.ts`.
void main() {
  late GameDatabase db;
  const now = 1760572800000; // 2026-10-16T00:00:00.000Z
  const farm = tutorialFarmLocationId;
  const town = tutorialTownGatewayLocationId;
  const copperMine = 'LOC-0003';

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  PlayerSave activeTutorial([String locationId = farm]) {
    final assigned = assignRace(
      db,
      createNewSave(db, now).copyWith(currentLocationId: locationId),
      'RACE-0001',
    );
    expect(assigned.ok, isTrue, reason: assigned.reason);
    return assigned.save!;
  }

  PlayerSave withoutFood(PlayerSave save) {
    return save.copyWith(
      inventory: save.inventory.where((stack) => !isEdibleItem(db, stack.itemId)).toList(),
      bank: save.bank.where((stack) => !isEdibleItem(db, stack.itemId)).toList(),
      equipment: EquipmentLoadout(
        slots: {
          for (final entry in save.equipment.slots.entries)
            if (entry.key != foodSlotId) entry.key: entry.value,
        },
      ),
    );
  }

  PlayerSave withItem(PlayerSave save, String itemId, num quantity) {
    final cleared = save.copyWith(
      inventory: save.inventory.where((stack) => stack.itemId != itemId).toList(),
    );
    return quantity > 0 ? addItemToInventory(cleared, itemId, quantity) : cleared;
  }

  PlayerSave combatStepSave() {
    var save = withoutFood(activeTutorial());
    save = save.copyWith(
      quests: [
        for (final quest in save.quests)
          if (quest.questId == tutorialQuestId)
            quest.copyWith(
              counters: {
                'step:QSTP-0013': 1,
                'step:QSTP-0014': 1,
                'step:QSTP-0015': 1,
                'step:QSTP-0016': 1,
              },
            )
          else
            quest,
      ],
    );
    return applyQuestStepUnlocks(db, save);
  }

  PlayerSave reload(PlayerSave save) => parseSave(jsonDecode(jsonEncode(save.toJson())), now);

  test('auto-accepts Getting Started on first race pick and locks the world', () {
    final save = activeTutorial();
    expect(getQuestProgress(save, tutorialQuestId).status, 'active');
    expect(isTutorialLocked(save), isTrue);
    expect(isTutorialLocationAllowed(save, farm), isTrue);
    expect(isTutorialLocationAllowed(save, town), isFalse);
    expect(isTutorialLocationAllowed(save, copperMine), isFalse);
    expect(isTutorialActivityAllowed(save, tutorialFieldsActivityId), isTrue);
    expect(isTutorialActivityAllowed(save, tutorialPastureActivityId), isFalse);
    expect(isTutorialActivityAllowed(save, tutorialCookActivityId), isFalse);
    expect(isTutorialSkillMenuAllowed(save), isFalse);
    expect(isTutorialBazaarAllowed(save), isFalse);
    expect(npcsAtLocationForSave(db, save, farm, now).map((npc) => npc.npcId), ['NPC-0014']);
  });

  test('opens the kitchen path only on the cook and show-cooked steps', () {
    final gathering = activeTutorial();
    expect(isTutorialLocationAllowed(gathering, tutorialKitchenLocationId), isFalse);
    var cooking = gathering.copyWith(
      quests: [
        for (final quest in gathering.quests)
          if (quest.questId == tutorialQuestId)
            quest.copyWith(counters: {'step:QSTP-0013': 1, 'step:QSTP-0014': 1})
          else
            quest,
      ],
    );
    cooking = applyQuestStepUnlocks(db, cooking);
    expect(isTutorialLocationAllowed(cooking, tutorialKitchenLocationId), isTrue);
    expect(isTutorialActivityAllowed(cooking, tutorialCookActivityId), isTrue);
    expect(canTravelTo(db, farm, town, mainMapId, const <String>[], cooking), isTrue);
    expect(canTravelTo(db, farm, copperMine, mainMapId, const <String>[], cooking), isFalse);
  });

  test('refuses locked locations and activities on travel, start, and visibility', () {
    final save = activeTutorial();
    expect(canTravelTo(db, farm, copperMine, mainMapId, const <String>[], save), isFalse);
    final refused = applyTravelArrival(db, save, copperMine, now);
    expect(refused.currentLocationId, farm);
    expect(tutorialGuaranteedGathersUsed(refused), tutorialGuaranteedGathersUsed(save));
    expect(validateActivityStart(db, save, tutorialPastureActivityId).ok, isFalse);
    expect(activityVisibleForSave(db, save, tutorialPastureActivityId), isFalse);
    expect(
      validateActivityStart(
        db,
        save.copyWith(currentLocationId: tutorialKitchenLocationId),
        tutorialCookActivityId,
      ).ok,
      isFalse,
    );
  });

  test('guarantees the first five potato gathers, persists the count across reload', () {
    var save = activeTutorial();
    final potato = db.actions.firstWhere((row) => row.actionId == tutorialPotatoActionId);
    for (var i = 0; i < 5; i++) {
      expect(
        tutorialForcedAction(db, save, tutorialFieldsActivityId)?.actionId,
        tutorialPotatoActionId,
      );
      final done = completeGatheringAction(db, save, potato, () => 0.999, now);
      save = done.save;
      expect([for (final drop in done.result.loot) drop.itemId], [tutorialPotatoItemId]);
      expect(tutorialGuaranteedGathersUsed(save), i + 1);
    }
    expect(tutorialForcedAction(db, save, tutorialFieldsActivityId), isNull);
    expect(tutorialGuaranteedGathersUsed(reload(save)), 5);
    expect(reload(save).saveVersion, saveVersion);
  });

  test('guarantees the first five potato cooks then uses normal odds', () {
    var save = activeTutorial().copyWith(
      currentLocationId: tutorialKitchenLocationId,
      productionRecipeId: tutorialPotatoRecipeId,
      productionQuantityRemaining: 6,
      productionQuantityTotal: 6,
    );
    save = withItem(save, tutorialPotatoItemId, 6);
    save = applyQuestStepUnlocks(
      db,
      save.copyWith(
        quests: [
          for (final quest in save.quests)
            if (quest.questId == tutorialQuestId)
              quest.copyWith(counters: {'step:QSTP-0013': 1, 'step:QSTP-0014': 1})
            else
              quest,
        ],
      ),
    );
    expect(
      [for (final row in recipesForActivity(db, save, tutorialCookActivityId)) row.recipeId],
      [tutorialPotatoRecipeId],
    );
    for (var i = 0; i < 5; i++) {
      final craft = completeProductionCraft(db, save, now + i, () => 0.999);
      expect(craft?.failed, isFalse);
      expect(craft!.outputQty, greaterThan(0));
      save = craft.save;
      expect(tutorialGuaranteedCooksUsed(save), i + 1);
    }
    expect(tutorialGuaranteedCooksUsed(reload(save)), 5);
  });

  test('forces the first pasture fight to be a Cow, including retries', () {
    final save = combatStepSave();
    expect(tutorialCombatStepActive(save), isTrue);
    expect(
      tutorialForcedAction(db, save, tutorialPastureActivityId)?.actionId,
      tutorialCowActionId,
    );
    final rolled = generateNextAction(db, save, tutorialPastureActivityId, () => 0.999, now);
    expect(rolled?.action.actionId, tutorialCowActionId);
    expect(enemyForAction(db, rolled!.action)?.enemyId, tutorialCowEnemyId);
  });

  test('grants Fennel food once per death only when the bag, bank, and food slot are empty', () {
    final empty = applyCombatDefeat(db, combatStepSave(), now);
    expect(empty.dialogueFlags, contains(tutorialLossFlag));
    expect(empty.dialogueFlags, contains(tutorialFoodGrantFlag));
    expect(
      empty.inventory.any(
        (stack) => stack.itemId == tutorialBakedPotatoItemId && stack.quantity == 5,
      ),
      isTrue,
    );
    final again = applyCombatDefeat(db, empty, now);
    expect(again.tutorialFoodGrantDeathAt, empty.tutorialFoodGrantDeathAt);
    expect(
      again.inventory.firstWhere((stack) => stack.itemId == tutorialBakedPotatoItemId).quantity,
      5,
    );

    final withBagFood = applyCombatDefeat(
      db,
      withItem(combatStepSave(), tutorialBakedPotatoItemId, 1),
      now,
    );
    expect(withBagFood.dialogueFlags, contains(tutorialLossFlag));
    expect(withBagFood.dialogueFlags, isNot(contains(tutorialFoodGrantFlag)));

    final banked = applyCombatDefeat(
      db,
      combatStepSave().copyWith(
        bank: [InventoryStack(itemId: tutorialBakedPotatoItemId, quantity: 1)],
      ),
      now,
    );
    expect(banked.dialogueFlags, isNot(contains(tutorialFoodGrantFlag)));

    final base = combatStepSave();
    final slotted = applyCombatDefeat(
      db,
      base.copyWith(
        equipment: EquipmentLoadout(
          slots: {
            ...base.equipment.slots,
            foodSlotId: EquippedStack(itemId: tutorialBakedPotatoItemId, quantity: 1),
          },
        ),
      ),
      now,
    );
    expect(slotted.dialogueFlags, isNot(contains(tutorialFoodGrantFlag)));
  });

  test(
    'completes the quest on one cow kill, stops combat, unlocks the world, and grants rewards once',
    () {
      final before = combatStepSave();
      final action = db.actions.firstWhere((row) => row.actionId == tutorialCowActionId);
      final enemy = db.enemies.firstWhere((row) => row.enemyId == tutorialCowEnemyId);
      final fighting = before.copyWith(
        currentActivityId: tutorialPastureActivityId,
        combatEnemyId: tutorialCowEnemyId,
        combatEnemyHp: 1,
      );
      final victory = applyCombatVictory(db, fighting, action, enemy, () => 0, now);
      expect(getQuestProgress(victory.save, tutorialQuestId).status, 'completed');
      expect(victory.save.currentActivityId, isNull);
      expect(victory.save.combatEnemyId, isNull);
      expect(isTutorialLocked(victory.save), isFalse);
      expect(isTutorialLocationAllowed(victory.save, copperMine), isTrue);
      expect(isTutorialSkillMenuAllowed(victory.save), isTrue);
      expect(victory.save.dialogueFlags, contains(tutorialFarewellFlag));
      expect(victory.save.unlockedBookIds, contains('BOOK-0001'));

      final twice = applyTutorialCowKill(db, victory.save, tutorialCowEnemyId);
      expect(twice.completed, isFalse);
      expect(getQuestProgress(twice.save, tutorialQuestId).status, 'completed');
    },
  );

  test('locks in-progress players back without dropping items or bazaar state', () {
    final mid = activeTutorial(town).copyWith(
      currentActivityId: 'ACT-0008',
      unlockedLocationIds: [copperMine],
      tutorialGuaranteedGathers: 3,
    );
    final locked = applyTutorialLockback(mid);
    expect(locked.dialogueFlags, contains(tutorialLockbackFlag));
    expect(locked.currentLocationId, farm);
    expect(locked.currentActivityId, isNull);
    expect(locked.tutorialGuaranteedGathers, 3);
    expect(getQuestProgress(locked, tutorialQuestId).status, 'active');

    final finished = applyTutorialLockback(
      mid.copyWith(
        quests: [QuestProgress(questId: tutorialQuestId, status: 'completed', progress: 1)],
      ),
    );
    expect(finished.currentLocationId, town);
    expect(finished.dialogueFlags, isNot(contains(tutorialLockbackFlag)));

    final raw = Map<String, Object?>.from(mid.toJson());
    raw['saveVersion'] = 66;
    raw.remove('tutorialGuaranteedGathers');
    raw.remove('tutorialGuaranteedCooks');
    raw.remove('tutorialFoodGrantDeathAt');
    final migrated = parseSave(raw, now);
    expect(migrated.saveVersion, 67);
    expect(migrated.currentLocationId, farm);
    expect(migrated.dialogueFlags, contains(tutorialLockbackFlag));
  });

  test('keeps step progress across reload while the combat step is open', () {
    final save = reload(combatStepSave());
    expect(getCurrentStepId(db, save, getQuest(db, tutorialQuestId)!), tutorialCombatStepId);
    expect(isStepLatched(save, tutorialQuestId, 'QSTP-0016'), isTrue);
    expect(ensureGettingStartedAccepted(db, save), save);
  });
}
