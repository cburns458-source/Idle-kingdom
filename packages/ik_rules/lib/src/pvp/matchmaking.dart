import '../combat/stats.dart';
import '../economy/payout.dart';
import '../economy/plaza.dart';
import '../save/generated/save_models.dart';
import '../skills/totals.dart';
import '../time.dart';

const num rankedPvpDailyCap = 5;

/// @deprecated Ranked wins pay plaza points.
const num rankedPvpWinGold = 0;
const String rankedPvpDailyCapCode = 'daily_cap_reached';
const String rankedPvpDailyCapMessage =
    "You've won 5 ranked fights today. Fights still count, but rewards return tomorrow.";
const String rankedPvpFakedWinRefusal = 'The server resolves ranked fights.';
const String rankedPvpUnknownFightRefusal = 'Unknown ranked fight.';

/// A stored player the arena can search or match against.
class ArenaOpponent {
  const ArenaOpponent({
    required this.userId,
    required this.username,
    required this.combatLevel,
    required this.totalLevel,
    this.appearance,
  });

  factory ArenaOpponent.fromJson(Map<String, Object?> json) => ArenaOpponent(
    userId: json['userId']! as String,
    username: json['username']! as String,
    combatLevel: json['combatLevel'] as num? ?? 0,
    totalLevel: json['totalLevel'] as num? ?? 0,
    appearance: json['appearance'] is Map
        ? PlayerAppearance.fromJson(Map<String, Object?>.from(json['appearance']! as Map))
        : null,
  );

  final String userId;
  final String username;
  final num combatLevel;
  final num totalLevel;
  final PlayerAppearance? appearance;

  Map<String, Object?> toJson() => <String, Object?>{
    'userId': userId,
    'username': username,
    'combatLevel': combatLevel,
    'totalLevel': totalLevel,
    if (appearance != null) 'appearance': appearance!.toJson(),
  };
}

/// UTC calendar day, matching `toISOString().slice(0, 10)`.
String rankedPvpDayKey(num nowMs) => isoFromMs(nowMs).substring(0, 10);

num rankedPvpKd(num wins, num losses) {
  final w = wins < 0 ? 0 : wins;
  final l = losses < 0 ? 0 : losses;
  if (w <= 0 && l <= 0) return 0;
  return w / (l <= 0 ? 1 : l);
}

/// Ranked wins already counted toward today's cap.
num rankedWinsUsedToday(PlayerSave save, num nowMs) {
  final key = rankedPvpDayKey(nowMs);
  if (save.rankedPvpDayKey != key) return 0;
  final used = save.rankedPvpFightsToday;
  return used < 0 ? 0 : used.floor();
}

num rankedWinsRemaining(PlayerSave save, num nowMs) {
  final left = rankedPvpDailyCap - rankedWinsUsedToday(save, nowMs);
  return left < 0 ? 0 : left;
}

/// Paid ranked wins still available today. Fights after the cap still resolve.
num rankedFightsUsedToday(PlayerSave save, num nowMs) => rankedWinsUsedToday(save, nowMs);

num rankedFightsRemaining(PlayerSave save, num nowMs) => rankedWinsRemaining(save, nowMs);

class RankedPvpStartResult {
  const RankedPvpStartResult._({required this.ok, this.reason});

  const RankedPvpStartResult.ok() : this._(ok: true);

  const RankedPvpStartResult.failed(String reason) : this._(ok: false, reason: reason);

  final bool ok;
  final String? reason;

  Map<String, Object?> toJson() => <String, Object?>{
    'ok': ok,
    if (reason != null) 'reason': reason,
  };
}

/// Search is by name: a case-insensitive substring of the stored username.
/// An empty query matches nobody, so the list is never "every player".
List<ArenaOpponent> searchArenaOpponents(List<ArenaOpponent> candidates, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return const <ArenaOpponent>[];
  final matches = candidates.where((row) => row.username.toLowerCase().contains(needle)).toList();
  matches.sort((a, b) {
    final byName = a.username.compareTo(b.username);
    return byName != 0 ? byName : a.userId.compareTo(b.userId);
  });
  return matches;
}

/// Ranked picks the closest combat level on the game, then closer total level,
/// then a stable user id. Self is already excluded by the caller.
ArenaOpponent? pickRankedOpponent(
  num selfCombatLevel,
  num selfTotalLevel,
  List<ArenaOpponent> candidates,
) {
  if (candidates.isEmpty) return null;
  final ranked = [...candidates]
    ..sort((a, b) {
      final combatA = (a.combatLevel - selfCombatLevel).abs();
      final combatB = (b.combatLevel - selfCombatLevel).abs();
      final combat = combatA.compareTo(combatB);
      if (combat != 0) return combat;
      final totalA = (a.totalLevel - selfTotalLevel).abs();
      final totalB = (b.totalLevel - selfTotalLevel).abs();
      final total = totalA.compareTo(totalB);
      if (total != 0) return total;
      return a.userId.compareTo(b.userId);
    });
  return ranked.first;
}

/// Ranked fights always start. The daily cap stops the purse, not the match.
RankedPvpStartResult canStartRankedPvp(PlayerSave save, num nowMs) {
  final _ = (save, nowMs);
  return const RankedPvpStartResult.ok();
}

class RankedPvpApplyResult {
  const RankedPvpApplyResult({
    required this.save,
    required this.won,
    required this.paid,
    required this.goldGained,
    required this.pointsGained,
    required this.winsToday,
    required this.winsRemaining,
    this.code,
  });

  final PlayerSave save;
  final bool won;
  final bool paid;
  final num goldGained;
  final num pointsGained;
  final String? code;
  final num winsToday;
  final num winsRemaining;

  Map<String, Object?> toJson() => <String, Object?>{
    'save': save.toJson(),
    'won': won,
    'paid': paid,
    'goldGained': goldGained,
    'pointsGained': pointsGained,
    'winsToday': winsToday,
    'winsRemaining': winsRemaining,
    if (code != null) 'code': code,
  };
}

/// Records a ranked fight: K/D always, and 25 plaza points on a win under the
/// daily cap of 5 wins. Search fights skip this. The sixth win still counts but
/// pays nothing. Gold is never granted.
RankedPvpApplyResult applyRankedPvpResult(PlayerSave save, bool won, num nowMs) {
  final key = rankedPvpDayKey(nowMs);
  final winsToday = rankedWinsUsedToday(save, nowMs);
  final paid = won && winsToday < rankedPvpDailyCap;
  final payout = payReward(
    save,
    Reward(type: rewardTypePlazaPoints, amount: paid ? rankedPvpWinPoints : 0),
  );
  final nextWinsToday = won ? winsToday + 1 : winsToday;
  final wins = save.rankedPvpWins < 0 ? 0 : save.rankedPvpWins.floor();
  final losses = save.rankedPvpLosses < 0 ? 0 : save.rankedPvpLosses.floor();
  return RankedPvpApplyResult(
    save: payout.save.copyWith(
      rankedPvpDayKey: key,
      rankedPvpFightsToday: nextWinsToday,
      rankedPvpWins: wins + (won ? 1 : 0),
      rankedPvpLosses: losses + (won ? 0 : 1),
    ),
    won: won,
    paid: paid,
    goldGained: 0,
    pointsGained: payout.paid,
    code: won && !paid ? rankedPvpDailyCapCode : null,
    winsToday: nextWinsToday,
    winsRemaining: nextWinsToday > rankedPvpDailyCap ? 0 : rankedPvpDailyCap - nextWinsToday,
  );
}

ArenaOpponent arenaOpponentFromSave(String userId, String username, PlayerSave save) {
  return ArenaOpponent(
    userId: userId,
    username: username,
    combatLevel: combatLevelOf(save),
    totalLevel: totalLevel(save),
    appearance: save.appearance,
  );
}
