import 'package:ik_rules/ik_rules.dart';

/// Start intents that stamp a new action / combat / production clock on the
/// server about a round-trip later than the local tap.
const hostedStartCommands = <String>{'start_activity', 'confirm_auto_equip', 'start_production'};

/// True when a successful command result should keep the clocks the player
/// already sees, instead of snapping the bar back to the server's start time.
bool keepsLocalActionClock(String? command) {
  return command != null && hostedStartCommands.contains(command);
}

/// Overlays the local action and combat clocks onto a start-command result.
///
/// The client starts the activity on tap. The hosted `start_activity` (and the
/// auto-equip / production equivalents) runs `Date.now()` about a second later
/// and returns a save whose `actionStartedAt` / `combatRoundStartedAt` reset the
/// bar. Later cycles are local ticks, so the snap only shows on the first
/// action. Sell, travel, and conflict pulls still take the server copy whole —
/// those responses may have finished the action.
PlayerSave mergeHostedStartSave(PlayerSave local, PlayerSave incoming, {String? command}) {
  if (!keepsLocalActionClock(command)) return incoming;
  if (isBlank(local.currentActivityId) || local.currentActivityId != incoming.currentActivityId) {
    return incoming;
  }
  return incoming.copyWith(
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
