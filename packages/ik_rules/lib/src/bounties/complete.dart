import 'dart:math' as math;

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
  const BountyRewardResult({required this.save, required this.goldGained});

  final PlayerSave save;
  final num goldGained;

  Map<String, Object?> toJson() => <String, Object?>{
    'save': save.toJson(),
    'goldGained': goldGained,
  };
}

/// Pays out a bounty a backend has accepted. Everyone eligible earns the base
/// reward; only the claim the server recorded first adds the bonus.
BountyRewardResult applyBountyReward(
  PlayerSave save,
  BountyDefinition bounty,
  bool firstCompleter,
) {
  final goldGained = bounty.rewardGold + (firstCompleter ? bounty.firstPlaceBonusGold : 0);
  return BountyRewardResult(
    save: save.copyWith(
      gold: save.gold + goldGained,
      bountyClaimedIds: <String>[...save.bountyClaimedIds, bounty.id],
      statistics: PlayerStatistics(
        values: <String, num>{
          ...save.statistics.values,
          'bounties_completed': jsNumber(save.statistics.values['bounties_completed'] ?? 0) + 1,
          'gold_earned': jsNumber(save.statistics.values['gold_earned'] ?? 0) + goldGained,
        },
      ),
    ),
    goldGained: goldGained,
  );
}
