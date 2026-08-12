import 'bonus_xp.dart';
import 'reward_summary.dart';
import 'rewards.dart';

/// The action currently ticking down, mirrored outside the save for the UI.
class ActiveActionState {
  const ActiveActionState({
    required this.actionId,
    required this.startedAtMs,
    required this.durationMs,
  });

  final String actionId;
  final num startedAtMs;
  final num durationMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'actionId': actionId,
    'startedAtMs': startedAtMs,
    'durationMs': durationMs,
  };
}

/// One completed action's combined reward line (all XP + items).
class ActionRewardBundle {
  const ActionRewardBundle({
    required this.id,
    required this.xpRewards,
    required this.loot,
    required this.goldGained,
  });

  final String id;
  final List<ActionXpRewardSummary> xpRewards;
  final List<LootGrant> loot;
  final num goldGained;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'xpRewards': xpRewards.map((reward) => reward.toJson()).toList(),
    'loot': loot.map((grant) => grant.toJson()).toList(),
    'goldGained': goldGained,
  };
}

class ActionCompletionResult {
  const ActionCompletionResult({
    required this.actionId,
    required this.actionName,
    required this.skillId,
    required this.xpGained,
    required this.bonusXp,
    required this.xpRewards,
    required this.goldGained,
    required this.loot,
    required this.leveledUpTo,
  });

  final String actionId;
  final String actionName;
  final String skillId;
  final num xpGained;

  /// Extra skill XP beyond the action's primary Relevant Skill reward.
  final List<BonusXpGrant> bonusXp;

  /// Ordered XP reward summaries for the action reward UI.
  final List<ActionXpRewardSummary> xpRewards;
  final num goldGained;
  final List<LootGrant> loot;
  final num? leveledUpTo;

  Map<String, Object?> toJson() => <String, Object?>{
    'actionId': actionId,
    'actionName': actionName,
    'skillId': skillId,
    'xpGained': xpGained,
    'bonusXp': bonusXp.map((grant) => grant.toJson()).toList(),
    'xpRewards': xpRewards.map((reward) => reward.toJson()).toList(),
    'goldGained': goldGained,
    'loot': loot.map((grant) => grant.toJson()).toList(),
    'leveledUpTo': leveledUpTo,
  };
}

/// Either a green light or the reason an activity cannot start.
class ActivityStartResult {
  const ActivityStartResult.ok() : reason = null;

  const ActivityStartResult.failed(this.reason);

  bool get ok => reason == null;
  final String? reason;

  Map<String, Object?> toJson() => <String, Object?>{
    'ok': ok,
    if (reason != null) 'reason': reason,
  };
}
