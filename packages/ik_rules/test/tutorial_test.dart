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

  PlayerSave combatStepSave([String raceId = 'RACE-0001']) {
    final assigned = assignRace(
      db,
      createNewSave(db, now).copyWith(currentLocationId: farm),
      raceId,
    );
    expect(assigned.ok, isTrue, reason: assigned.reason);
    var save = withoutFood(assigned.save!);
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

  PlayerSave withEquipped(PlayerSave save, String slotId, String itemId) {
    return save.copyWith(
      equipment: EquipmentLoadout(
        slots: {
          ...save.equipment.slots,
          slotId: EquippedStack(itemId: itemId, quantity: 1),
        },
      ),
    );
  }

  PlayerSave withLatchedSteps(PlayerSave save, List<String> stepIds) {
    return applyQuestStepUnlocks(
      db,
      save.copyWith(
        quests: [
          for (final quest in save.quests)
            if (quest.questId == tutorialQuestId)
              quest.copyWith(counters: {for (final stepId in stepIds) 'step:$stepId': 1})
            else
              quest,
        ],
      ),
    );
  }

  PlayerSave fightingCow(PlayerSave save, {required num enemyHp, required num playerHp}) {
    return beginActivitySave(save, tutorialPastureActivityId, isoFromMs(now)).copyWith(
      unattendedProgressAt: isoFromMs(now),
      currentActionId: tutorialCowActionId,
      combatEnemyId: tutorialCowEnemyId,
      combatEnemyHp: enemyHp,
      currentHp: playerHp,
      combatRoundStartedAt: isoFromMs(now),
    );
  }

  num stackQty(PlayerSave save, String itemId) {
    num total = 0;
    for (final stack in save.inventory) {
      if (stack.itemId == itemId) total += stack.quantity;
    }
    return total;
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

  test('asks goblins to equip the wooden dagger instead of a shield', () {
    final goblin = withEquipped(
      combatStepSave('RACE-0005'),
      tutorialWeaponSlotId,
      tutorialStarterSwordId,
    );
    expect(tutorialHudHint(db, goblin)?.label, 'Equip your dagger');
    final goblinReady = withEquipped(goblin, tutorialOffhandSlotId, tutorialStarterDaggerId);
    expect(tutorialHudHint(db, goblinReady)?.label, 'Fight a cow in the pasture');

    final human = withEquipped(
      combatStepSave('RACE-0001'),
      tutorialWeaponSlotId,
      tutorialStarterSwordId,
    );
    expect(tutorialHudHint(db, human)?.label, 'Equip your shield');
    final humanReady = withEquipped(human, tutorialOffhandSlotId, tutorialStarterShieldId);
    expect(tutorialHudHint(db, humanReady)?.label, 'Fight a cow in the pasture');
  });

  test('first five potato gathers give exactly one potato and no other drop', () {
    var save = activeTutorial();
    final potato = db.actions.firstWhere((row) => row.actionId == tutorialPotatoActionId);
    for (var i = 0; i < 5; i++) {
      final before = stackQty(save, tutorialPotatoItemId);
      final done = completeGatheringAction(db, save, potato, () => 0.999, now);
      save = done.save;
      expect(done.result.loot, hasLength(1));
      expect(done.result.loot.single.itemId, tutorialPotatoItemId);
      expect(done.result.loot.single.quantity, 1);
      expect(stackQty(save, tutorialPotatoItemId), before + 1);
    }
    expect(tutorialForcedAction(db, save, tutorialFieldsActivityId), isNull);
    final later = generateNextAction(db, save, tutorialFieldsActivityId, () => 0.999, now);
    expect(later?.action.actionId, isNot(tutorialPotatoActionId));
    expect(tutorialGuaranteedGathersUsed(reload(save)), 5);
  });

  test('sixth potato cook uses normal odds after the guarantee', () {
    var save = activeTutorial().copyWith(
      currentLocationId: tutorialKitchenLocationId,
      productionRecipeId: tutorialPotatoRecipeId,
      productionQuantityRemaining: 6,
      productionQuantityTotal: 6,
    );
    save = withItem(save, tutorialPotatoItemId, 6);
    save = withLatchedSteps(save, [tutorialGatherStepId, tutorialShowPotatoesStepId]);
    for (var i = 0; i < 5; i++) {
      final craft = completeProductionCraft(db, save, now + i, () => 0.999);
      expect(craft?.failed, isFalse);
      save = craft!.save;
    }
    expect(tutorialGuaranteedCooksUsed(save), 5);
    final sixth = completeProductionCraft(db, save, now + 5, () => 0.999);
    expect(sixth?.failed, isTrue);
    expect(sixth!.outputQty, 0);
    expect(tutorialGuaranteedCooksUsed(sixth.save), 5);
    expect(tutorialGuaranteedCooksUsed(reload(sixth.save)), 5);
  });

  test('first pasture fight stays a Cow after a loss, never a bull', () {
    const bullActionId = 'ACN-0002';
    const bullEnemyId = 'ENM-0002';
    final lost = applyCombatDefeat(db, combatStepSave(), now);
    expect(getQuestProgress(lost, tutorialQuestId).status, 'active');
    expect(getCurrentStepId(db, lost, getQuest(db, tutorialQuestId)!), tutorialCombatStepId);
    expect(tutorialCombatStepActive(lost), isTrue);
    expect(
      tutorialForcedAction(db, lost, tutorialPastureActivityId)?.actionId,
      tutorialCowActionId,
    );
    expect(
      tutorialForcedAction(db, lost, tutorialPastureActivityId)?.actionId,
      isNot(bullActionId),
    );

    final recovered = applyDeathRecovery(db, lost);
    expect(validateActivityStart(db, recovered, tutorialPastureActivityId).ok, isTrue);
    final retry = generateNextAction(
      db,
      recovered,
      tutorialPastureActivityId,
      () => 0.999,
      now + 60 * 1000,
    );
    expect(retry?.action.actionId, tutorialCowActionId);
    expect(enemyForAction(db, retry!.action)?.enemyId, tutorialCowEnemyId);
    expect(retry.action.actionId, isNot(bullActionId));
    expect(enemyForAction(db, retry.action)?.enemyId, isNot(bullEnemyId));
  });

  test('food top-up is only on the Cow step after a zero-food death', () {
    final gatheringDeath = applyCombatDefeat(db, withoutFood(activeTutorial()), now);
    expect(gatheringDeath.dialogueFlags, isNot(contains(tutorialFoodGrantFlag)));
    expect(stackQty(gatheringDeath, tutorialBakedPotatoItemId), 0);

    final cooking = withLatchedSteps(withoutFood(activeTutorial()), [
      tutorialGatherStepId,
      tutorialShowPotatoesStepId,
    ]);
    final cookingDeath = applyCombatDefeat(db, cooking, now);
    expect(cookingDeath.dialogueFlags, isNot(contains(tutorialFoodGrantFlag)));
    expect(stackQty(cookingDeath, tutorialBakedPotatoItemId), 0);

    final empty = applyCombatDefeat(db, combatStepSave(), now);
    expect(empty.dialogueFlags, contains(tutorialFoodGrantFlag));
    expect(stackQty(empty, tutorialBakedPotatoItemId), tutorialFoodTopUpQty);

    final finished = applyTutorialCowKill(db, combatStepSave(), tutorialCowEnemyId);
    expect(finished.completed, isTrue);
    final afterWin = applyCombatDefeat(db, withoutFood(finished.save), now);
    expect(afterWin.dialogueFlags, isNot(contains(tutorialFoodGrantFlag)));
    expect(stackQty(afterWin, tutorialBakedPotatoItemId), 0);
  });

  test('reloading or retrying a refused food grant does not grant twice', () {
    final granted = applyCombatDefeat(db, combatStepSave(), now);
    expect(stackQty(granted, tutorialBakedPotatoItemId), tutorialFoodTopUpQty);
    final retried = applyCombatDefeat(db, reload(granted), now);
    expect(retried.tutorialFoodGrantDeathAt, granted.tutorialFoodGrantDeathAt);
    expect(stackQty(retried, tutorialBakedPotatoItemId), tutorialFoodTopUpQty);

    final snapshot = applyCombatDefeat(db, combatStepSave(), now);
    final refusedReplay = applyCombatDefeat(db, snapshot, now + 1000);
    expect(stackQty(refusedReplay, tutorialBakedPotatoItemId), tutorialFoodTopUpQty);
  });

  test('food top-up during offline catch-up is once per death', () {
    final dying = fightingCow(combatStepSave(), enemyHp: 100, playerHp: 1);
    final resolved = resolveUnattendedProgress(db, dying, now + 8000, () => 0.99);
    expect(resolved.combatDeaths, greaterThan(0));
    expect(resolved.save.dialogueFlags, contains(tutorialFoodGrantFlag));
    expect(stackQty(resolved.save, tutorialBakedPotatoItemId), tutorialFoodTopUpQty);
    final again = applyCombatDefeat(db, resolved.save, now + 8000);
    expect(stackQty(again, tutorialBakedPotatoItemId), tutorialFoodTopUpQty);
  });

  test('one Cow kill through catch-up or reload mid-fight completes once', () {
    final action = db.actions.firstWhere((row) => row.actionId == tutorialCowActionId);
    final enemy = db.enemies.firstWhere((row) => row.enemyId == tutorialCowEnemyId);
    final fighting = fightingCow(combatStepSave(), enemyHp: 1, playerHp: 1000);
    final victory = applyCombatVictory(db, reload(fighting), action, enemy, () => 0, now);
    expect(getQuestProgress(victory.save, tutorialQuestId).status, 'completed');
    expect(victory.save.currentActivityId, isNull);
    expect(victory.save.unlockedBookIds, contains('BOOK-0001'));
    expect(isTutorialLocked(victory.save), isFalse);

    final away = resolveUnattendedProgress(
      db,
      fightingCow(combatStepSave(), enemyHp: 1, playerHp: 1000),
      now + 8000,
      () => 0,
    );
    expect(away.combatVictories, greaterThan(0));
    expect(getQuestProgress(away.save, tutorialQuestId).status, 'completed');
    expect(away.save.currentActivityId, isNull);
    expect(away.save.unlockedBookIds.where((id) => id == 'BOOK-0001'), hasLength(1));
    final twice = applyTutorialCowKill(db, away.save, tutorialCowEnemyId);
    expect(twice.completed, isFalse);
    expect(away.save.unlockedBookIds.where((id) => id == 'BOOK-0001'), hasLength(1));
  });

  test('losing to the Cow leaves the step open and retryable', () {
    final lost = applyCombatDefeat(db, combatStepSave(), now);
    expect(getQuestProgress(lost, tutorialQuestId).status, 'active');
    expect(getCurrentStepId(db, lost, getQuest(db, tutorialQuestId)!), tutorialCombatStepId);
    expect(isTutorialLocked(lost), isTrue);
    expect(isTutorialLocationAllowed(lost, copperMine), isFalse);
    final recovered = applyDeathRecovery(db, lost);
    expect(
      requestActivityStart(db, recovered, tutorialPastureActivityId, now, () => 0.999).ok,
      isTrue,
    );
    final retry = generateNextAction(db, recovered, tutorialPastureActivityId, () => 0.999, now);
    expect(retry?.action.actionId, tutorialCowActionId);
  });

  test('v66 to v67 keeps partway progress and items, and locks the player back', () {
    var mid = withItem(activeTutorial(town), tutorialPotatoItemId, 3);
    mid = withLatchedSteps(mid, [tutorialGatherStepId, tutorialShowPotatoesStepId]);
    mid = mid.copyWith(
      currentLocationId: tutorialKitchenLocationId,
      currentActivityId: tutorialCookActivityId,
      gold: 77,
      claimedMerchantTipIds: const ['NPC-0008'],
      tutorialGuaranteedGathers: 4,
      tutorialGuaranteedCooks: 2,
    );
    final raw = Map<String, Object?>.from(mid.toJson());
    raw['saveVersion'] = 66;
    raw.remove('tutorialGuaranteedGathers');
    raw.remove('tutorialGuaranteedCooks');
    raw.remove('tutorialFoodGrantDeathAt');
    final migrated = parseSave(raw, now);
    expect(migrated.saveVersion, 67);
    expect(migrated.dialogueFlags, contains(tutorialLockbackFlag));
    expect(isStepLatched(migrated, tutorialQuestId, tutorialGatherStepId), isTrue);
    expect(isStepLatched(migrated, tutorialQuestId, tutorialShowPotatoesStepId), isTrue);
    expect(getCurrentStepId(db, migrated, getQuest(db, tutorialQuestId)!), tutorialCookStepId);
    expect(stackQty(migrated, tutorialPotatoItemId), 3);
    expect(migrated.gold, 77);
    expect(migrated.claimedMerchantTipIds, ['NPC-0008']);
    expect(migrated.currentLocationId, tutorialKitchenLocationId);
  });

  test('v66 to v67 stops idle actions and travel in now-hidden places', () {
    final hidden = activeTutorial(copperMine)
        .copyWith(currentActivityId: 'ACT-0002', unlockedLocationIds: [copperMine, town]);
    final raw = Map<String, Object?>.from(hidden.toJson());
    raw['saveVersion'] = 66;
    raw.remove('tutorialGuaranteedGathers');
    raw.remove('tutorialGuaranteedCooks');
    raw.remove('tutorialFoodGrantDeathAt');
    final migrated = parseSave(raw, now);
    expect(migrated.currentLocationId, farm);
    expect(migrated.currentActivityId, isNull);
    expect(canTravelTo(db, farm, copperMine, mainMapId, const <String>[], migrated), isFalse);
    expect(validateActivityStart(db, migrated, 'ACT-0002').ok, isFalse);
  });

  test('v66 to v67 leaves finished players and bazaar-adjacent state unchanged', () {
    final potatoes = withItem(activeTutorial(town), tutorialPotatoItemId, 4);
    final finished = potatoes.copyWith(
      quests: [const QuestProgress(questId: tutorialQuestId, status: 'completed', progress: 1)],
      currentActivityId: 'ACT-0008',
      gold: 120,
      claimedMerchantTipIds: const ['NPC-0008'],
    );
    expect(applyTutorialLockback(finished).currentLocationId, town);
    expect(applyTutorialLockback(finished).currentActivityId, 'ACT-0008');
    expect(applyTutorialLockback(finished).gold, 120);
    expect(applyTutorialLockback(finished).claimedMerchantTipIds, ['NPC-0008']);
    expect(stackQty(applyTutorialLockback(finished), tutorialPotatoItemId), 4);
    expect(applyTutorialLockback(finished).dialogueFlags, isNot(contains(tutorialLockbackFlag)));

    final raw = Map<String, Object?>.from(finished.toJson());
    raw['saveVersion'] = 66;
    raw.remove('tutorialGuaranteedGathers');
    raw.remove('tutorialGuaranteedCooks');
    raw.remove('tutorialFoodGrantDeathAt');
    final migrated = parseSave(raw, now);
    expect(migrated.saveVersion, 67);
    expect(migrated.currentLocationId, town);
    expect(migrated.currentActivityId, 'ACT-0008');
    expect(migrated.gold, 120);
    expect(migrated.claimedMerchantTipIds, ['NPC-0008']);
    expect(stackQty(migrated, tutorialPotatoItemId), 4);
    expect(getQuestProgress(migrated, tutorialQuestId).status, 'completed');
    expect(migrated.dialogueFlags, isNot(contains(tutorialLockbackFlag)));
  });

  test('new accounts start Getting Started at step 1', () {
    final save = activeTutorial();
    expect(tutorialCurrentStepId(db, save), tutorialGatherStepId);
    expect(getCurrentStepId(db, save, getQuest(db, tutorialQuestId)!), tutorialGatherStepId);
    expect(tutorialGuaranteedGathersUsed(save), 0);
    expect(tutorialGuaranteedCooksUsed(save), 0);
    expect(isStepLatched(save, tutorialQuestId, tutorialGatherStepId), isFalse);
  });

  test('unlock flags cannot skip locked places before their step', () {
    final gather = activeTutorial().copyWith(
      unlockedLocationIds: [town, copperMine, tutorialKitchenLocationId],
    );
    expect(isTutorialLocationAllowed(gather, tutorialKitchenLocationId), isFalse);
    expect(isTutorialLocationAllowed(gather, town), isFalse);
    expect(isTutorialLocationAllowed(gather, copperMine), isFalse);
    expect(isTutorialActivityAllowed(gather, tutorialCookActivityId), isFalse);
    expect(isTutorialActivityAllowed(gather, tutorialPastureActivityId), isFalse);
    expect(canTravelTo(db, farm, town, mainMapId, const <String>[], gather), isFalse);
    expect(canTravelTo(db, farm, copperMine, mainMapId, const <String>[], gather), isFalse);
    expect(isTutorialBazaarAllowed(gather), isFalse);
    expect(isTutorialGuildHallAllowed(gather), isFalse);

    final cooking = withLatchedSteps(gather, [tutorialGatherStepId, tutorialShowPotatoesStepId]);
    expect(isTutorialLocationAllowed(cooking, tutorialKitchenLocationId), isTrue);
    expect(isTutorialActivityAllowed(cooking, tutorialCookActivityId), isTrue);
    expect(isTutorialActivityAllowed(cooking, tutorialPastureActivityId), isFalse);
    expect(canTravelTo(db, farm, copperMine, mainMapId, const <String>[], cooking), isFalse);

    final combat = withLatchedSteps(gather, [
      tutorialGatherStepId,
      tutorialShowPotatoesStepId,
      tutorialCookStepId,
      tutorialShowCookedStepId,
    ]);
    expect(isTutorialLocationAllowed(combat, tutorialKitchenLocationId), isFalse);
    expect(isTutorialActivityAllowed(combat, tutorialCookActivityId), isFalse);
    expect(isTutorialActivityAllowed(combat, tutorialPastureActivityId), isTrue);
    expect(canTravelTo(db, farm, copperMine, mainMapId, const <String>[], combat), isFalse);
    expect(
      validateActivityStart(
        db,
        combat.copyWith(currentLocationId: tutorialKitchenLocationId),
        tutorialCookActivityId,
      ).ok,
      isFalse,
    );
  });

  test('equip step accepts Human starting sword and shield from inventory', () {
    var save = combatStepSave();
    final sword = equipItemFromInventory(db, save, tutorialStarterSwordId);
    expect(sword.ok, isTrue, reason: sword.reason);
    save = sword.save!;
    final shield = equipItemFromInventory(db, save, tutorialStarterShieldId);
    expect(shield.ok, isTrue, reason: shield.reason);
    save = shield.save!;
    expect(isTutorialSwordEquipped(save), isTrue);
    expect(isTutorialShieldEquipped(save), isTrue);
    expect(tutorialHudHint(db, save)?.spotlight, TutorialSpotlightId.pasture);
  });

  test('equip step accepts Goblin starting wooden dagger from inventory', () {
    var save = combatStepSave('RACE-0005');
    expect(stackQty(save, tutorialStarterDaggerId), 1);
    expect(stackQty(save, tutorialStarterShieldId), 0);
    final sword = equipItemFromInventory(db, save, tutorialStarterSwordId);
    expect(sword.ok, isTrue, reason: sword.reason);
    save = sword.save!;
    expect(isTutorialSwordEquipped(save), isTrue);
    final dagger = equipItemFromInventory(db, save, tutorialStarterDaggerId);
    expect(dagger.ok, isTrue, reason: dagger.reason);
    save = dagger.save!;
    expect(save.equipment.slots[tutorialOffhandSlotId]?.itemId, tutorialStarterDaggerId);
    expect(isTutorialShieldEquipped(save), isTrue);
    expect(tutorialHudHint(db, save)?.spotlight, TutorialSpotlightId.pasture);
  });

  test('step progress survives reload and a refused travel save', () {
    final save = combatStepSave();
    final refused = applyTravelArrival(db, save, copperMine, now);
    expect(refused.currentLocationId, farm);
    expect(isStepLatched(refused, tutorialQuestId, tutorialShowCookedStepId), isTrue);
    expect(getCurrentStepId(db, refused, getQuest(db, tutorialQuestId)!), tutorialCombatStepId);
    final reloaded = reload(refused);
    expect(isStepLatched(reloaded, tutorialQuestId, tutorialShowCookedStepId), isTrue);
    expect(getCurrentStepId(db, reloaded, getQuest(db, tutorialQuestId)!), tutorialCombatStepId);
    expect(tutorialGuaranteedGathersUsed(reloaded), tutorialGuaranteedGathersUsed(save));
  });
}
