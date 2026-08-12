/// One hourly bounty.
class BountyDefinition {
  const BountyDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.kind,
    required this.targetId,
    required this.amount,
    required this.rewardGold,
    required this.firstPlaceBonusGold,
  });

  final String id;
  final String title;
  final String description;

  /// One of `defeat`, `gather_deliver`, `process`, `project`.
  final String kind;
  final String targetId;
  final num amount;
  final num rewardGold;

  /// Extra gold for the first valid turn-in this hour.
  final num firstPlaceBonusGold;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'description': description,
    'kind': kind,
    'targetId': targetId,
    'amount': amount,
    'rewardGold': rewardGold,
    'firstPlaceBonusGold': firstPlaceBonusGold,
  };
}

/// One recorded first-completer claim.
class BountyClaimRecord {
  const BountyClaimRecord({
    required this.hourKey,
    required this.bountyId,
    required this.userId,
    required this.username,
    required this.claimedAt,
  });

  final String hourKey;
  final String bountyId;
  final String userId;
  final String username;
  final String claimedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'hourKey': hourKey,
    'bountyId': bountyId,
    'userId': userId,
    'username': username,
    'claimedAt': claimedAt,
  };
}

class HourlyBountyBoard {
  const HourlyBountyBoard({
    required this.hourKey,
    required this.expiresAtMs,
    required this.bounties,
  });

  final String hourKey;
  final num expiresAtMs;
  final List<BountyDefinition> bounties;

  Map<String, Object?> toJson() => <String, Object?>{
    'hourKey': hourKey,
    'expiresAtMs': expiresAtMs,
    'bounties': bounties.map((bounty) => bounty.toJson()).toList(),
  };
}
