import 'package:ik_rules/ik_rules.dart';

/// Start intents that stamp a new action / combat / production clock on the
/// server about a round-trip later than the local tap.
const hostedStartCommands = <String>{'start_activity', 'confirm_auto_equip', 'start_production'};

/// Travel adopts the server location, but live HP should not snap backward.
const hostedTravelCommands = <String>{'travel', 'travel_guild_hall'};

/// True when a successful command result should keep the clocks the player
/// already sees, instead of snapping the bar back to the server's start time.
bool keepsLocalActionClock(String? command) {
  return command != null && hostedStartCommands.contains(command);
}

/// True when travel should keep the HP the player already sees.
///
/// Hostile arrival that started a new fight takes the server vitals instead —
/// that HP change is the ambush, not a stale hosted snapshot.
bool keepsLocalVitals(String? command, PlayerSave local, PlayerSave incoming) {
  if (command == null || !hostedTravelCommands.contains(command)) return false;
  if (isNotBlank(incoming.combatEnemyId) && incoming.combatEnemyId != local.combatEnemyId) {
    return false;
  }
  return true;
}

/// Overlays local clocks and, for travel, live HP onto a command result.
///
/// The client starts the activity on tap. The hosted `start_activity` (and the
/// auto-equip / production equivalents) runs `Date.now()` about a second later
/// and returns a save whose `actionStartedAt` / `combatRoundStartedAt` reset the
/// bar. Travel used to adopt a hosted `currentHp` that was seconds behind the
/// local tick, so a 190 HP walk snapped to 150. Conflict and failure pulls
/// still take the server copy whole.
PlayerSave mergeHostedStartSave(PlayerSave local, PlayerSave incoming, {String? command}) {
  var next = incoming;
  if (keepsLocalActionClock(command) &&
      isNotBlank(local.currentActivityId) &&
      local.currentActivityId == incoming.currentActivityId) {
    next = incoming.copyWith(
      activityStartedAt: local.activityStartedAt,
      currentActionId: local.currentActionId,
      actionStartedAt: local.actionStartedAt,
      actionDurationMs: local.actionDurationMs,
      heldActionByActivityId: local.heldActionByActivityId,
      combatEnemyId: local.combatEnemyId,
      combatEnemyHp: local.combatEnemyHp,
      combatRoundStartedAt: local.combatRoundStartedAt,
      combatManualEatRoundStartedAt: local.combatManualEatRoundStartedAt,
      combatPlayerSwingApplied: local.combatPlayerSwingApplied,
      combatPendingRound: local.combatPendingRound,
      combatEatUntil: local.combatEatUntil,
      combatContinueActivityAfterEat: local.combatContinueActivityAfterEat,
      combatSkipEnemyAttack: local.combatSkipEnemyAttack,
      combatBossSleepRoundsRemaining: local.combatBossSleepRoundsRemaining,
      combatBossPendingId: local.combatBossPendingId,
      combatBossPendingHp: local.combatBossPendingHp,
      combatBossAddsRemaining: local.combatBossAddsRemaining,
      combatBossAddsTriggered: local.combatBossAddsTriggered,
      combatBossInkActive: local.combatBossInkActive,
      productionRecipeId: local.productionRecipeId,
      productionQuantityTotal: local.productionQuantityTotal,
      productionQuantityRemaining: local.productionQuantityRemaining,
    );
  }
  if (keepsLocalVitals(command, local, incoming)) {
    next = next.copyWith(
      currentHp: local.currentHp,
      lastDamagedAt: local.lastDamagedAt,
      hpRegenStreak: local.hpRegenStreak,
      deathPauseUntil: local.deathPauseUntil,
    );
  }
  return next;
}
