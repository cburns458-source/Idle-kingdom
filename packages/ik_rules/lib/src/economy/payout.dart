import '../js_compat.dart';
import '../save/generated/save_models.dart';
import 'plaza.dart';

/// Reward kinds the shared payout can pay.
const String rewardTypeGold = 'gold';
const String rewardTypePlazaPoints = 'plaza_points';

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

num _wholeAmount(num amount) {
  final paid = jsNumber(amount).floor();
  return paid < 0 ? 0 : paid;
}

/// Pays one reward into a save. Ranked PvP and bounty turn-in both go through
/// this. Plaza points round down; gold is unchanged by a points payout.
RewardPayout payReward(PlayerSave save, Reward reward) {
  final paid = _wholeAmount(reward.amount);
  if (reward.type == rewardTypeGold) {
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
  if (reward.type == rewardTypePlazaPoints) {
    final next = plazaPointsOf(save) + paid;
    return RewardPayout(
      save: save.copyWith(
        plazaPoints: next,
        statistics: PlayerStatistics(
          values: <String, num>{
            ...save.statistics.values,
            'plaza_points_earned':
                jsNumber(save.statistics.values['plaza_points_earned'] ?? 0) + paid,
          },
        ),
      ),
      paid: paid,
    );
  }
  return RewardPayout(save: save, paid: 0);
}
