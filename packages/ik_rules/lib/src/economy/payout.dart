import '../js_compat.dart';
import '../save/generated/save_models.dart';

/// Reward kinds the shared payout can pay. Plaza points (ECO-03) add a second kind later.
const String rewardTypeGold = 'gold';

class Reward {
  const Reward({required this.type, required this.amount});

  final String type;
  final num amount;
}

class RewardPayout {
  const RewardPayout({required this.save, required this.paid});

  final PlayerSave save;
  final num paid;
}

num _goldAmount(num amount) {
  final paid = jsNumber(amount).floor();
  return paid < 0 ? 0 : paid;
}

/// Pays one reward into a save. Ranked PvP and bounty turn-in both go through
/// this so a later plaza-points swap only changes the gold kind.
RewardPayout payReward(PlayerSave save, Reward reward) {
  if (reward.type == rewardTypeGold) {
    final paid = _goldAmount(reward.amount);
    return RewardPayout(
      save: save.copyWith(
        gold: save.gold + paid,
        statistics: PlayerStatistics(
          values: <String, num>{
            ...save.statistics.values,
            'gold_earned': jsNumber(save.statistics.values['gold_earned'] ?? 0) + paid,
          },
        ),
      ),
      paid: paid,
    );
  }
  return RewardPayout(save: save, paid: 0);
}
