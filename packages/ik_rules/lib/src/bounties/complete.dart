import 'dart:math' as math;

import '../economy/payout.dart';
import '../js_compat.dart';
import '../production/recipes.dart';
import '../save/generated/save_models.dart';
import 'progress.dart';
import 'rotation.dart';
import 'types.dart';

/// Either the save with the turn-in staged, or the reason it was refused.
class BountyTurnInCheck {
  const BountyTurnInCheck.ok(this.save) : reason = null;

  const BountyTurnInCheck.failed(this.reason) : save = null;

  bool get ok => reason == null;
  final PlayerSave? save;
  final String? reason;

  Map<String, Object?> toJson() => ok
      ? <String, Object?>{'ok': true, 'save': save!.toJson()}
      : <String, Object?>{'ok': false, 'reason': reason};
}

BountyTurnInCheck _consumeInventoryItems(PlayerSave save, String itemId, num amount) {
  if (inventoryCount(save, itemId) < amount) {
    return const BountyTurnInCheck.failed('Not enough items to deliver.');
  }
  var remaining = amount;
  final inventory = <InventoryStack>[];
  for (final stack in save.inventory) {
    if (stack.itemId != itemId || remaining <= 0 || isNotBlank(stack.enchantmentId)) {
      if (stack.quantity > 0) inventory.add(stack);
      continue;
    }
    final take = math.min(stack.quantity, remaining);
    remaining -= take;
    final left = stack.quantity - take;
    if (left > 0) inventory.add(stack.copyWith(quantity: left));
  }
  if (remaining > 0) return const BountyTurnInCheck.failed('Not enough items to deliver.');
  return BountyTurnInCheck.ok(save.copyWith(inventory: inventory));
}

/// Everything the turn-in decides locally: the board is current, the objective
/// is met, and any delivered items have left the bag. The returned save is what
/// the reward applies to once a backend accepts the claim.
BountyTurnInCheck prepareBountyTurnIn(PlayerSave save, BountyDefinition bounty, num nowMs) {
  final next = syncBountyHour(save, nowMs);
  final board = hourlyBountyBoard(nowMs);
  if (board.hourKey != next.bountyHourKey) {
    return const BountyTurnInCheck.failed('This bounty board has rotated.');
  }
  if (!board.bounties.any((row) => row.id == bounty.id)) {
    return const BountyTurnInCheck.failed('That bounty is not on the current board.');
  }
  if (next.bountyClaimedIds.contains(bounty.id)) {
    return const BountyTurnInCheck.failed('You already claimed this bounty.');
  }
  if (!isBountyReadyToClaim(next, bounty, nowMs)) {
    return const BountyTurnInCheck.failed('Finish the bounty objective first.');
  }
  if (bounty.kind == 'gather_deliver') {
    return _consumeInventoryItems(next, bounty.targetId, bounty.amount);
  }
  return BountyTurnInCheck.ok(next);
}

class BountyRewardResult {
  const BountyRewardResult({
    required this.save,
    required this.goldGained,
    required this.pointsGained,
  });

  final PlayerSave save;
  final num goldGained;
  final num pointsGained;

  Map<String, Object?> toJson() => <String, Object?>{
    'save': save.toJson(),
    'goldGained': goldGained,
    'pointsGained': pointsGained,
  };
}

/// Plaza points for a bounty. Always rounds down.
num bountyPointsFor(BountyDefinition bounty, bool firstCompleter) {
  final raw =
      jsNumber(bounty.rewardGold) + (firstCompleter ? jsNumber(bounty.firstPlaceBonusGold) : 0);
  final paid = raw.floor();
  return paid < 0 ? 0 : paid;
}

/// Pays out a bounty a backend has accepted. Everyone eligible earns the base
/// points; only the claim the server recorded first adds the bonus. Gold is
/// never granted. Points always round down.
BountyRewardResult applyBountyReward(
  PlayerSave save,
  BountyDefinition bounty,
  bool firstCompleter,
) {
  final pointsGained = bountyPointsFor(bounty, firstCompleter);
  final payout = payReward(save, Reward(type: rewardTypePlazaPoints, amount: pointsGained));
  return BountyRewardResult(
    save: payout.save.copyWith(
      bountyClaimedIds: <String>[...save.bountyClaimedIds, bounty.id],
      statistics: PlayerStatistics(
        values: <String, num>{
          ...payout.save.statistics.values,
          'bounties_completed': jsNumber(save.statistics.values['bounties_completed'] ?? 0) + 1,
        },
      ),
    ),
    goldGained: 0,
    pointsGained: payout.paid,
  );
}
