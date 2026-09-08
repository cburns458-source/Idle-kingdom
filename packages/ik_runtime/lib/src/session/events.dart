import 'package:ik_rules/ik_rules.dart';

/// Everything a tick can tell the UI about, so the session never touches
/// presentation and every client reacts to the same list.
///
/// [kind] and the JSON shape match the TypeScript discriminated union in
/// `src/game/session/events.ts`, which is what the parity fixtures compare.
sealed class SessionEvent {
  const SessionEvent();

  String get kind;

  Map<String, Object?> toJson();
}

/// One completed action's combined XP / loot / gold line.
///
/// Optional thievery floater fields travel with gathering rewards so the UI can
/// show damage / zero-hit / food heal without a separate combat round.
class RewardsEvent extends SessionEvent {
  const RewardsEvent(
    this.bundle, {
    this.damageTaken = 0,
    this.foodHealed = 0,
    this.showZeroDamageHit = false,
  });

  final ActionRewardBundle bundle;

  /// HP lost on a thievery failure (combat-style floater).
  final num damageTaken;

  /// Food healed after a thievery resolution.
  final num foodHealed;

  /// Lockpick actions show a 0 damage floater like a combat swing.
  final bool showZeroDamageHit;

  @override
  String get kind => 'rewards';

  @override
  Map<String, Object?> toJson() {
    final json = <String, Object?>{'kind': kind, 'bundle': bundle.toJson()};
    // Omit defaults so existing session parity fixtures stay byte-stable.
    if (damageTaken != 0 || foodHealed != 0 || showZeroDamageHit) {
      json['damageTaken'] = damageTaken;
      json['foodHealed'] = foodHealed;
      json['showZeroDamageHit'] = showZeroDamageHit;
    }
    return json;
  }
}

/// Transient status line, e.g. the blow-by-blow of a combat round.
class MessageEvent extends SessionEvent {
  const MessageEvent(this.text);

  final String text;

  @override
  String get kind => 'message';

  @override
  Map<String, Object?> toJson() => <String, Object?>{'kind': kind, 'text': text};
}

/// The running activity ended on its own; the reason explains why.
class ActivityStoppedEvent extends SessionEvent {
  const ActivityStoppedEvent(this.reason);

  final String reason;

  @override
  String get kind => 'activity-stopped';

  @override
  Map<String, Object?> toJson() => <String, Object?>{'kind': kind, 'reason': reason};
}

/// A standard production craft finished, for the item pop.
class CraftCompletedEvent extends SessionEvent {
  const CraftCompletedEvent({required this.itemId, required this.displayName});

  final String itemId;
  final String displayName;

  @override
  String get kind => 'craft-completed';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'itemId': itemId,
    'displayName': displayName,
  };
}

/// A craft is blocked until the player frees a bag slot.
class InventoryFullEvent extends SessionEvent {
  const InventoryFullEvent();

  @override
  String get kind => 'inventory-full';

  @override
  Map<String, Object?> toJson() => <String, Object?>{'kind': kind};
}

class CombatRoundEvent extends SessionEvent {
  const CombatRoundEvent({
    required this.enemyId,
    required this.enemyName,
    required this.playerHit,
    required this.playerCrit,
    required this.offhandHit,
    required this.staffHit,
    required this.enemyHit,
    required this.thornsHit,
    required this.outcome,
    this.bossInkActive = false,
  });

  final String enemyId;
  final String enemyName;
  final num playerHit;
  final bool playerCrit;
  final num? offhandHit;
  final num? staffHit;
  final num? enemyHit;
  final num thornsHit;

  /// One of `ongoing`, `victory`, `defeat`.
  final String outcome;

  /// True when Mother Squid (or another ink boss) clouded this round.
  final bool bossInkActive;

  @override
  String get kind => 'combat-round';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'enemyId': enemyId,
    'enemyName': enemyName,
    'playerHit': playerHit,
    'playerCrit': playerCrit,
    'offhandHit': offhandHit,
    'staffHit': staffHit,
    'enemyHit': enemyHit,
    'thornsHit': thornsHit,
    'outcome': outcome,
    'bossInkActive': bossInkActive,
  };
}

/// Food was eaten after a win, for the green heal pop.
class FoodHealedEvent extends SessionEvent {
  const FoodHealedEvent({required this.healed, required this.foodName});

  final num healed;
  final String foodName;

  @override
  String get kind => 'food-healed';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'healed': healed,
    'foodName': foodName,
  };
}

class EnemyDefeatedEvent extends SessionEvent {
  const EnemyDefeatedEvent({required this.enemyId, required this.enemyName});

  final String enemyId;
  final String enemyName;

  @override
  String get kind => 'enemy-defeated';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'enemyId': enemyId,
    'enemyName': enemyName,
  };
}

class PlayerDefeatedEvent extends SessionEvent {
  const PlayerDefeatedEvent({required this.enemyId, required this.enemyName});

  final String enemyId;
  final String enemyName;

  @override
  String get kind => 'player-defeated';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'enemyId': enemyId,
    'enemyName': enemyName,
  };
}

/// A death pause elapsed and the activity picked back up.
class RecoveredEvent extends SessionEvent {
  const RecoveredEvent();

  @override
  String get kind => 'recovered';

  @override
  Map<String, Object?> toJson() => <String, Object?>{'kind': kind};
}

class CritterSpawnedEvent extends SessionEvent {
  const CritterSpawnedEvent({required this.critterId, required this.displayName});

  final String critterId;
  final String displayName;

  @override
  String get kind => 'critter-spawned';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'critterId': critterId,
    'displayName': displayName,
  };
}
