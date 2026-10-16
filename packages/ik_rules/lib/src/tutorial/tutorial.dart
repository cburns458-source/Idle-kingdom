/// Mandatory Getting Started tutorial (QST-0006 / QST-02).
///
/// Unlock flags, gather/cook guarantees, the forced cow fight, Fennel's food
/// top-up, and lock-back migration. Ported from `src/game/tutorial/tutorial.ts`.
library;

import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/rewards.dart';
import '../combat/food.dart';
import '../equipment/loadout.dart';
import '../inventory/add_items.dart';
import '../js_compat.dart';
import '../quests/quests.dart';
import '../quests/steps.dart';
import '../save/generated/save_models.dart';

const String tutorialQuestId = 'QST-0006';
const String tutorialNpcId = 'NPC-0014';
const String tutorialFarmLocationId = 'LOC-0001';
const String tutorialTownGatewayLocationId = 'LOC-0002';
const String tutorialTownSquareLocationId = 'LOC-0054';
const String tutorialKitchenLocationId = 'LOC-0023';
const String tutorialFieldsActivityId = 'ACT-0021';
const String tutorialPastureActivityId = 'ACT-0001';
const String tutorialCookActivityId = 'ACT-0017';
const String tutorialPotatoActionId = 'ACN-0035';
const String tutorialCowActionId = 'ACN-0001';
const String tutorialPotatoItemId = 'ITEM-0025';
const String tutorialBakedPotatoItemId = startingBakedPotatoId;
const String tutorialPotatoRecipeId = 'RCP-0001';
const String tutorialCowEnemyId = 'ENM-0001';
const String tutorialStarterSwordId = 'ITEM-0124';
const String tutorialStarterShieldId = 'ITEM-0145';
const String tutorialWeaponSlotId = 'SLOT-0001';
const String tutorialOffhandSlotId = 'SLOT-0002';
const num tutorialGatherGuaranteeCount = 5;
const num tutorialCookGuaranteeCount = 5;
const num tutorialFoodTopUpQty = startingBakedPotatoQty;

const String tutorialGatherStepId = 'QSTP-0013';
const String tutorialShowPotatoesStepId = 'QSTP-0014';
const String tutorialCookStepId = 'QSTP-0015';
const String tutorialShowCookedStepId = 'QSTP-0016';
const String tutorialCombatStepId = 'QSTP-0022';

const String tutorialFarewellFlag = 'tutorial:farewell';
const String tutorialLockbackFlag = 'tutorial:lockback';
const String tutorialFoodGrantFlag = 'tutorial:food_grant';
const String tutorialLossFlag = 'tutorial:loss';

const List<String> _tutorialStepOrder = <String>[
  tutorialGatherStepId,
  tutorialShowPotatoesStepId,
  tutorialCookStepId,
  tutorialShowCookedStepId,
  tutorialCombatStepId,
];

const List<String> _tutorialCookPathLocationIds = <String>[
  tutorialFarmLocationId,
  tutorialTownGatewayLocationId,
  tutorialTownSquareLocationId,
  tutorialKitchenLocationId,
];

enum TutorialSpotlightId { fennel, fields, mapTown, kitchenCook, sword, shield, pasture, foodSlot }

class TutorialHudHint {
  const TutorialHudHint({
    required this.label,
    required this.locationId,
    this.activityId,
    this.spotlight,
  });

  final String label;
  final String locationId;
  final String? activityId;
  final TutorialSpotlightId? spotlight;
}

num tutorialGuaranteedGathersUsed(PlayerSave save) =>
    math.max(0, jsNumber(save.tutorialGuaranteedGathers).floor());

num tutorialGuaranteedCooksUsed(PlayerSave save) =>
    math.max(0, jsNumber(save.tutorialGuaranteedCooks).floor());

bool hasTutorialFlag(PlayerSave save, String flag) => save.dialogueFlags.contains(flag);

PlayerSave withTutorialFlag(PlayerSave save, String flag, bool on) {
  final current = save.dialogueFlags;
  if (current.contains(flag) == on) return save;
  final next = on ? [...current, flag] : current.where((entry) => entry != flag).toList();
  return save.copyWith(dialogueFlags: next..sort());
}

bool isGettingStartedComplete(PlayerSave save) =>
    getQuestProgress(save, tutorialQuestId).status == 'completed';

bool isGettingStartedActive(PlayerSave save) =>
    getQuestProgress(save, tutorialQuestId).status == 'active';

bool isTutorialLocked(PlayerSave save) => isGettingStartedActive(save);

String? tutorialCurrentStepId(GameDatabase db, PlayerSave save) {
  if (!isGettingStartedActive(save)) return null;
  final quest = getQuest(db, tutorialQuestId);
  if (quest == null) return null;
  return getCurrentStepId(db, save, quest);
}

/// Step id from latched counters only — safe in save migrations that have no database.
String? tutorialStepIdFromCounters(PlayerSave save) {
  if (!isGettingStartedActive(save)) return null;
  for (final stepId in _tutorialStepOrder) {
    if (!isStepLatched(save, tutorialQuestId, stepId)) return stepId;
  }
  return tutorialCombatStepId;
}

bool tutorialKitchenPathOpen(PlayerSave save) {
  if (!isTutorialLocked(save)) return false;
  final stepId = tutorialStepIdFromCounters(save);
  return stepId == tutorialCookStepId || stepId == tutorialShowCookedStepId;
}

bool tutorialCombatStepActive(PlayerSave save) =>
    isTutorialLocked(save) && tutorialStepIdFromCounters(save) == tutorialCombatStepId;

bool isTutorialLocationAllowed(PlayerSave save, String locationId) {
  if (!isTutorialLocked(save)) return true;
  if (locationId == tutorialFarmLocationId) return true;
  if (!tutorialKitchenPathOpen(save)) return false;
  return _tutorialCookPathLocationIds.contains(locationId);
}

bool isTutorialActivityAllowed(PlayerSave save, String activityId) {
  if (!isTutorialLocked(save)) return true;
  if (activityId == tutorialFieldsActivityId) return true;
  if (activityId == tutorialCookActivityId) return tutorialKitchenPathOpen(save);
  if (activityId == tutorialPastureActivityId) return tutorialCombatStepActive(save);
  return false;
}

bool isTutorialRecipeAllowed(PlayerSave save, String recipeId) {
  if (!isTutorialLocked(save)) return true;
  return recipeId == tutorialPotatoRecipeId && tutorialKitchenPathOpen(save);
}

bool isTutorialNpcAllowed(PlayerSave save, String npcId) {
  if (!isTutorialLocked(save)) return true;
  return npcId == tutorialNpcId;
}

bool isTutorialSkillMenuAllowed(PlayerSave save) => !isTutorialLocked(save);

bool isTutorialBazaarAllowed(PlayerSave save) => !isTutorialLocked(save);

bool isTutorialGuildHallAllowed(PlayerSave save) => !isTutorialLocked(save);

num tutorialForcedGatherRemaining(PlayerSave save) {
  if (!isTutorialLocked(save)) return 0;
  return math.max(0, tutorialGatherGuaranteeCount - tutorialGuaranteedGathersUsed(save));
}

num tutorialForcedCookRemaining(PlayerSave save) {
  if (!isTutorialLocked(save)) return 0;
  return math.max(0, tutorialCookGuaranteeCount - tutorialGuaranteedCooksUsed(save));
}

bool shouldGuaranteeTutorialGather(PlayerSave save) => tutorialForcedGatherRemaining(save) > 0;

bool shouldGuaranteeTutorialCook(PlayerSave save, String recipeId) =>
    recipeId == tutorialPotatoRecipeId && tutorialForcedCookRemaining(save) > 0;

PlayerSave noteTutorialGuaranteedGather(PlayerSave save) {
  if (!shouldGuaranteeTutorialGather(save)) return save;
  return save.copyWith(tutorialGuaranteedGathers: tutorialGuaranteedGathersUsed(save) + 1);
}

ActionRewards applyTutorialGuaranteedPotatoGather(GameDatabase db, PlayerSave save) {
  final noted = noteTutorialGuaranteedGather(save);
  final granted = addItemsToInventory(noted, tutorialPotatoItemId, 1);
  final displayName =
      db.items.firstWhereOrNull((item) => item.itemId == tutorialPotatoItemId)?.displayName ??
      'Potato';
  final loot = granted.added > 0
      ? <LootGrant>[
          LootGrant(
            itemId: tutorialPotatoItemId,
            quantity: granted.added,
            displayName: displayName,
          ),
        ]
      : const <LootGrant>[];
  final leftBehind = granted.added < 1
      ? <LootGrant>[
          LootGrant(
            itemId: tutorialPotatoItemId,
            quantity: 1 - granted.added,
            displayName: displayName,
          ),
        ]
      : const <LootGrant>[];
  return ActionRewards(save: granted.save, loot: loot, goldGained: 0, leftBehind: leftBehind);
}

PlayerSave noteTutorialGuaranteedCook(PlayerSave save, String recipeId) {
  if (!shouldGuaranteeTutorialCook(save, recipeId)) return save;
  return save.copyWith(tutorialGuaranteedCooks: tutorialGuaranteedCooksUsed(save) + 1);
}

ActionRow? tutorialForcedAction(GameDatabase db, PlayerSave save, String activityId) {
  if (!isTutorialLocked(save)) return null;
  if (activityId == tutorialFieldsActivityId && shouldGuaranteeTutorialGather(save)) {
    return db.actions.firstWhereOrNull((row) => row.actionId == tutorialPotatoActionId);
  }
  if (activityId == tutorialPastureActivityId && tutorialCombatStepActive(save)) {
    return db.actions.firstWhereOrNull((row) => row.actionId == tutorialCowActionId);
  }
  return null;
}

num _bagCount(PlayerSave save, String itemId) {
  var total = 0;
  for (final stack in save.inventory) {
    if (stack.itemId == itemId) total += math.max(0, jsNumber(stack.quantity).floor());
  }
  return total;
}

num _edibleQuantity(GameDatabase db, String itemId, num quantity) {
  if (!isEdibleItem(db, itemId)) return 0;
  return math.max(0, jsNumber(quantity).floor());
}

/// Food in the bag, bank, or food slot. Banking/selling to look empty does not work.
bool tutorialHasAnyFood(GameDatabase db, PlayerSave save) {
  var total = 0;
  for (final stack in save.inventory) {
    total += _edibleQuantity(db, stack.itemId, stack.quantity);
  }
  for (final stack in save.bank) {
    total += _edibleQuantity(db, stack.itemId, stack.quantity);
  }
  final equipped = slotStack(save, foodSlotId);
  if (equipped != null) {
    total += _edibleQuantity(db, equipped.itemId, equipped.quantity);
  }
  return total > 0;
}

bool shouldGrantTutorialDeathFood(GameDatabase db, PlayerSave save) {
  if (!tutorialCombatStepActive(save)) return false;
  if (save.deathPauseUntil == null) return false;
  if (save.tutorialFoodGrantDeathAt == save.deathPauseUntil) return false;
  return !tutorialHasAnyFood(db, save);
}

PlayerSave applyTutorialDeathFoodGrant(GameDatabase db, PlayerSave save) {
  if (!shouldGrantTutorialDeathFood(db, save)) return save;
  final granted = addItemsToInventory(save, tutorialBakedPotatoItemId, tutorialFoodTopUpQty);
  return withTutorialFlag(
    granted.save.copyWith(tutorialFoodGrantDeathAt: save.deathPauseUntil),
    tutorialFoodGrantFlag,
    true,
  );
}

/// Loss line always; food top-up only when the bag, bank, and food slot are empty.
PlayerSave applyTutorialCombatDefeat(GameDatabase db, PlayerSave save) {
  if (!tutorialCombatStepActive(save)) return save;
  return applyTutorialDeathFoodGrant(db, withTutorialFlag(save, tutorialLossFlag, true));
}

PlayerSave _stopRunningAction(PlayerSave save) {
  return save.copyWith(
    currentActivityId: null,
    activityStartedAt: null,
    currentActionId: null,
    actionStartedAt: null,
    actionDurationMs: null,
    activityTransition: null,
    combatEnemyId: null,
    combatEnemyHp: null,
    combatRoundStartedAt: null,
    combatManualEatRoundStartedAt: null,
    combatPlayerSwingApplied: false,
    combatPendingRound: null,
    combatEatUntil: null,
    combatContinueActivityAfterEat: false,
    combatSkipEnemyAttack: false,
    combatBossSleepRoundsRemaining: null,
    combatBossPendingId: null,
    combatBossPendingHp: null,
    combatBossAddsRemaining: null,
    combatBossAddsTriggered: false,
    combatBossInkActive: false,
    productionRecipeId: null,
    productionQuantityTotal: null,
    productionQuantityRemaining: null,
    heldActionByActivityId: const <String, String>{},
  );
}

/// Existing players still on Getting Started are locked back in: illegal
/// activities stop, travel out of a now-hidden place returns them to the farm,
/// and Fennel has a one-time lock-back line. Bazaar orders are not touched.
PlayerSave applyTutorialLockback(PlayerSave save) {
  var next = save.copyWith(
    tutorialGuaranteedGathers: tutorialGuaranteedGathersUsed(save),
    tutorialGuaranteedCooks: tutorialGuaranteedCooksUsed(save),
    tutorialFoodGrantDeathAt: save.tutorialFoodGrantDeathAt,
  );
  if (!isGettingStartedActive(next)) return next;

  next = withTutorialFlag(next, tutorialLockbackFlag, true);
  final locationAllowed = isTutorialLocationAllowed(next, next.currentLocationId);
  final activityId = next.currentActivityId;
  final activityAllowed = activityId == null || isTutorialActivityAllowed(next, activityId);
  if (!locationAllowed || !activityAllowed) {
    next = _stopRunningAction(next);
  }
  if (!locationAllowed) {
    next = next.copyWith(currentLocationId: tutorialFarmLocationId);
  }
  return next;
}

PlayerSave ensureGettingStartedAccepted(GameDatabase db, PlayerSave save) {
  final progress = getQuestProgress(save, tutorialQuestId);
  if (progress.status == 'active' || progress.status == 'completed') return save;
  final accepted = acceptQuest(db, save, tutorialQuestId, ignoreLocation: true);
  return accepted.save ?? save;
}

bool shouldStopTutorialCombatAfterKill(PlayerSave save, String enemyId) =>
    tutorialCombatStepActive(save) && enemyId == tutorialCowEnemyId;

class TutorialCowKillResult {
  const TutorialCowKillResult({required this.save, required this.completed});

  final PlayerSave save;
  final bool completed;
}

TutorialCowKillResult applyTutorialCowKill(GameDatabase db, PlayerSave save, String enemyId) {
  if (!shouldStopTutorialCombatAfterKill(save, enemyId)) {
    return TutorialCowKillResult(save: save, completed: false);
  }
  if (isGettingStartedComplete(save)) {
    return TutorialCowKillResult(save: _stopRunningAction(save), completed: true);
  }

  var next = applyQuestStepUnlocks(db, save);
  final finished = completeQuest(db, next, tutorialQuestId, ignoreLocation: true);
  if (!finished.ok || finished.save == null) {
    return TutorialCowKillResult(save: _stopRunningAction(next), completed: false);
  }
  next = _stopRunningAction(finished.save!);
  next = withTutorialFlag(next, tutorialFarewellFlag, true);
  next = withTutorialFlag(next, tutorialFoodGrantFlag, false);
  next = withTutorialFlag(next, tutorialLockbackFlag, false);
  next = withTutorialFlag(next, tutorialLossFlag, false);
  return TutorialCowKillResult(save: next, completed: true);
}

bool isTutorialSwordEquipped(PlayerSave save) =>
    slotStack(save, tutorialWeaponSlotId)?.itemId == tutorialStarterSwordId;

bool isTutorialShieldEquipped(PlayerSave save) =>
    slotStack(save, tutorialOffhandSlotId)?.itemId == tutorialStarterShieldId;

TutorialHudHint? tutorialHudHint(GameDatabase db, PlayerSave save) {
  if (hasTutorialFlag(save, tutorialFarewellFlag)) return null;
  if (!isTutorialLocked(save)) return null;
  final stepId = tutorialCurrentStepId(db, save) ?? tutorialStepIdFromCounters(save);
  if (stepId == null) return null;

  if (stepId == tutorialGatherStepId) {
    final have = math.min(5, _bagCount(save, tutorialPotatoItemId));
    return TutorialHudHint(
      label: 'Gather potatoes ${jsNumberToString(have)}/5',
      locationId: tutorialFarmLocationId,
      activityId: tutorialFieldsActivityId,
      spotlight: TutorialSpotlightId.fields,
    );
  }
  if (stepId == tutorialShowPotatoesStepId) {
    return const TutorialHudHint(
      label: 'Show Fennel the potatoes',
      locationId: tutorialFarmLocationId,
      spotlight: TutorialSpotlightId.fennel,
    );
  }
  if (stepId == tutorialCookStepId) {
    final cooked = math.min(
      5,
      jsNumber(
        getQuestProgress(save, tutorialQuestId).counters?['process:$tutorialPotatoRecipeId'] ?? 0,
      ),
    );
    final atKitchen = save.currentLocationId == tutorialKitchenLocationId;
    return TutorialHudHint(
      label: atKitchen
          ? 'Cook potatoes ${jsNumberToString(cooked)}/5'
          : 'Go to the kitchen in town',
      locationId: atKitchen ? tutorialKitchenLocationId : tutorialTownGatewayLocationId,
      activityId: atKitchen ? tutorialCookActivityId : null,
      spotlight: atKitchen ? TutorialSpotlightId.kitchenCook : TutorialSpotlightId.mapTown,
    );
  }
  if (stepId == tutorialShowCookedStepId) {
    return const TutorialHudHint(
      label: 'Show Fennel the cooked potatoes',
      locationId: tutorialFarmLocationId,
      spotlight: TutorialSpotlightId.fennel,
    );
  }
  if (stepId == tutorialCombatStepId) {
    if (!isTutorialSwordEquipped(save)) {
      return const TutorialHudHint(
        label: 'Equip your sword',
        locationId: tutorialFarmLocationId,
        spotlight: TutorialSpotlightId.sword,
      );
    }
    if (!isTutorialShieldEquipped(save)) {
      return const TutorialHudHint(
        label: 'Equip your shield',
        locationId: tutorialFarmLocationId,
        spotlight: TutorialSpotlightId.shield,
      );
    }
    return const TutorialHudHint(
      label: 'Fight a cow in the pasture',
      locationId: tutorialFarmLocationId,
      activityId: tutorialPastureActivityId,
      spotlight: TutorialSpotlightId.pasture,
    );
  }
  return null;
}
