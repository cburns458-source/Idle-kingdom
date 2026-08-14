import 'package:ik_content/ik_content.dart';

import '../combat/engine.dart';
import '../js_compat.dart';
import '../production/engine.dart';
import '../production/recipes.dart';
import '../rng/mulberry32.dart';
import '../save/generated/save_models.dart';
import '../time.dart';
import 'engine.dart';
import '../world/hostility.dart';

PlayerSave clearActivityTransition(PlayerSave save) {
  if (save.activityTransition == null) return save;
  return save.copyWith(activityTransition: null);
}

bool hasRunningPrimaryActivity(PlayerSave save) {
  return isNotBlank(save.currentActivityId) || isNotBlank(save.productionRecipeId);
}

/// Immediately stops the current Primary Activity (refunds remaining production materials).
PlayerSave stopPrimaryActivityNow(GameDatabase db, PlayerSave save, num nowMs) {
  // Death pause keeps the Primary Activity until recovery finishes.
  if (isDeathPaused(save, nowMs)) return save;

  var next = clearActivityTransition(save);
  if (isNotBlank(next.productionRecipeId)) {
    next = cancelProductionActivity(db, next);
  } else if (isNotBlank(next.currentActivityId)) {
    next = clearActivitySave(next, nowMs);
  }
  return next;
}

/// Travel interrupt: hard-stops the current Primary Activity immediately.
///
/// No activity-change cooldown — death pause still blocks travel in the
/// UI/hostility layer.
PlayerSave beginTravelActivityChange(GameDatabase db, PlayerSave save, num nowMs) {
  if (isDeathPaused(save, nowMs)) return save;
  if (!hasRunningPrimaryActivity(save) && save.activityTransition == null) return save;
  return stopPrimaryActivityNow(db, save, nowMs);
}

PlayerSave _startPoolActivityNow(
  GameDatabase db,
  PlayerSave save,
  String activityId,
  num nowMs,
  RandomFn random,
) {
  final started = beginActivitySave(clearActivityTransition(save), activityId, isoFromMs(nowMs));
  return generateNextAction(db, started, activityId, random, nowMs)?.save ?? started;
}

/// Either the updated save or the reason the change was refused.
class ActivityChangeResult {
  const ActivityChangeResult.ok(this.save) : reason = null;

  const ActivityChangeResult.failed(this.reason) : save = null;

  bool get ok => reason == null;
  final PlayerSave? save;
  final String? reason;
}

ProductionQueueResult _startProductionNow(
  GameDatabase db,
  PlayerSave save,
  String activityId,
  String recipeId,
  num quantity,
  num nowMs,
) {
  final started = beginActivitySave(clearActivityTransition(save), activityId, isoFromMs(nowMs));
  return beginProductionQueue(db, started, activityId, recipeId, quantity, nowMs);
}

String? _hostileStartBlocked(GameDatabase db, PlayerSave save, String activityId) {
  if (!locationIsHostileFor(db, save)) return null;
  final threatened = forcedHostileActivity(db, save, save.currentLocationId);
  if (threatened != null && jsString(threatened.raw['Activity ID']) == activityId) {
    return null;
  }
  return hostileActivityStartReason;
}

/// Starts or replaces a pool activity immediately. Death pause still blocks.
ActivityChangeResult requestActivityStart(
  GameDatabase db,
  PlayerSave save,
  String activityId,
  num nowMs,
  RandomFn random,
) {
  if (isDeathPaused(save, nowMs)) {
    return const ActivityChangeResult.failed(
      'Cannot change activities while recovering from defeat.',
    );
  }
  final hostile = _hostileStartBlocked(db, save, activityId);
  if (hostile != null) return ActivityChangeResult.failed(hostile);

  final validation = validateActivityStart(db, save, activityId);
  if (!validation.ok) return ActivityChangeResult.failed(validation.reason);

  if (save.currentActivityId == activityId &&
      isBlank(save.productionRecipeId) &&
      save.activityTransition == null) {
    return ActivityChangeResult.ok(clearActivityTransition(save));
  }

  var next = save;
  if (hasRunningPrimaryActivity(save) || save.activityTransition != null) {
    next = stopPrimaryActivityNow(db, save, nowMs);
  }

  return ActivityChangeResult.ok(_startPoolActivityNow(db, next, activityId, nowMs, random));
}

/// Starts Standard Production immediately, replacing any running Primary Activity.
ActivityChangeResult requestProductionStart(
  GameDatabase db,
  PlayerSave save,
  String activityId,
  String recipeId,
  num quantity,
  num nowMs,
) {
  if (isDeathPaused(save, nowMs)) {
    return const ActivityChangeResult.failed(
      'Cannot change activities while recovering from defeat.',
    );
  }
  if (locationIsHostileFor(db, save)) {
    return const ActivityChangeResult.failed(hostileActivityStartReason);
  }

  final validation = validateActivityStart(db, save, activityId);
  if (!validation.ok) return ActivityChangeResult.failed(validation.reason);

  var next = save;
  if (hasRunningPrimaryActivity(save) || save.activityTransition != null) {
    next = stopPrimaryActivityNow(db, save, nowMs);
  }

  final started = _startProductionNow(db, next, activityId, recipeId, quantity, nowMs);
  if (!started.ok) return ActivityChangeResult.failed(started.reason);
  return ActivityChangeResult.ok(started.save);
}

/// Stops the current Primary Activity immediately.
ActivityChangeResult requestActivityStop(GameDatabase db, PlayerSave save, num nowMs) {
  if (isDeathPaused(save, nowMs)) {
    return const ActivityChangeResult.failed(
      'Cannot change activities while recovering from defeat.',
    );
  }
  if (locationIsHostileFor(db, save)) {
    return const ActivityChangeResult.failed(hostileActivityLockReason);
  }
  if (!hasRunningPrimaryActivity(save) && save.activityTransition == null) {
    return const ActivityChangeResult.failed('No activity is running.');
  }

  return ActivityChangeResult.ok(stopPrimaryActivityNow(db, save, nowMs));
}

PlayerSave _applyFollowUpStart(
  GameDatabase db,
  PlayerSave save,
  ActivityTransition transition,
  num nowMs,
  RandomFn random,
) {
  final followUp = transition.followUpActivityId;
  if (isBlank(followUp)) return save;

  final recipeId = transition.productionRecipeId;
  final quantity = transition.productionQuantity;
  if (isNotBlank(recipeId) && quantity != null && quantity != 0) {
    final started = _startProductionNow(db, save, followUp!, recipeId!, quantity, nowMs);
    return started.ok ? started.save! : save;
  }

  final activity = getActivity(db, followUp!);
  if (activity != null && isStandardProductionActivity(db, activity)) return save;

  return _startPoolActivityNow(db, save, followUp, nowMs, random);
}

/// Clears legacy activity-change delays from older saves, applying any follow-up
/// immediately. New gameplay no longer queues these transitions.
PlayerSave resolveActivityTransitions(
  GameDatabase db,
  PlayerSave save,
  num nowMs,
  RandomFn random,
) {
  final transition = save.activityTransition;
  if (transition == null) return save;

  final next = stopPrimaryActivityNow(db, save, nowMs);
  if (transition.kind == 'starting') {
    return _applyFollowUpStart(
      db,
      next,
      transition.copyWith(followUpActivityId: transition.activityId),
      nowMs,
      random,
    );
  }
  return _applyFollowUpStart(db, next, transition, nowMs, random);
}
