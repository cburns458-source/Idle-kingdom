import 'dart:math' as math;

import '../production/recipes.dart';
import '../save/generated/save_models.dart';
import 'rotation.dart';
import 'types.dart';

/// Ensures save bounty counters match the current UTC hour board.
PlayerSave syncBountyHour(PlayerSave save, num nowMs) {
  final board = hourlyBountyBoard(nowMs);
  if (save.bountyHourKey == board.hourKey) return save;
  return save.copyWith(
    bountyHourKey: board.hourKey,
    bountyProgress: const <String, num>{},
    bountyClaimedIds: const <String>[],
  );
}

PlayerSave _bumpMatching(PlayerSave save, String kind, String targetId, num amount, num nowMs) {
  if (amount <= 0) return save;
  // gather_deliver is inventory-checked at turn-in, not countered while gathering.
  if (kind == 'gather_deliver') return save;
  final next = syncBountyHour(save, nowMs);
  final board = hourlyBountyBoard(nowMs);
  final progress = <String, num>{...next.bountyProgress};
  var changed = false;
  for (final bounty in board.bounties) {
    if (bounty.kind != kind || bounty.targetId != targetId) continue;
    if (next.bountyClaimedIds.contains(bounty.id)) continue;
    final current = progress[bounty.id] ?? 0;
    if (current >= bounty.amount) continue;
    progress[bounty.id] = math.min(bounty.amount, current + amount);
    changed = true;
  }
  if (!changed) return next;
  return next.copyWith(bountyProgress: progress);
}

PlayerSave applyBountyDefeatProgress(PlayerSave save, String enemyId, num amount, num nowMs) {
  return _bumpMatching(save, 'defeat', enemyId, amount, nowMs);
}

PlayerSave applyBountyProcessProgress(PlayerSave save, String recipeId, num amount, num nowMs) {
  return _bumpMatching(save, 'process', recipeId, amount, nowMs);
}

PlayerSave applyBountyProjectProgress(PlayerSave save, String projectId, num amount, num nowMs) {
  return _bumpMatching(save, 'project', projectId, amount, nowMs);
}

num bountyProgressFor(PlayerSave save, BountyDefinition bounty, num nowMs) {
  final synced = syncBountyHour(save, nowMs);
  if (bounty.kind == 'gather_deliver') {
    return math.min(bounty.amount, inventoryCount(synced, bounty.targetId));
  }
  return synced.bountyProgress[bounty.id] ?? 0;
}

bool isBountyReadyToClaim(PlayerSave save, BountyDefinition bounty, num nowMs) {
  final synced = syncBountyHour(save, nowMs);
  if (synced.bountyClaimedIds.contains(bounty.id)) return false;
  return bountyProgressFor(synced, bounty, nowMs) >= bounty.amount;
}
