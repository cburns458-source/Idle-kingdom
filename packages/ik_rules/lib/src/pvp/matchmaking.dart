import '../activity/xp.dart';
import '../combat/stats.dart';
import '../save/generated/save_models.dart';
import '../skills/totals.dart';
import '../time.dart';

const num rankedPvpDailyCap = 5;
const num rankedPvpWinGold = 1000;

/// A stored player the arena can search or match against.
class ArenaOpponent {
  const ArenaOpponent({
    required this.userId,
    required this.username,
    required this.combatLevel,
    required this.totalLevel,
    this.appearance,
  });

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

num combatLevelOf(PlayerSave save) => getSkillProgress(save, combatSkillId).level;

/// UTC calendar day, matching `toISOString().slice(0, 10)`.
String rankedPvpDayKey(num nowMs) => isoFromMs(nowMs).substring(0, 10);

num rankedPvpKd(num wins, num losses) {
  final w = wins < 0 ? 0 : wins;
  final l = losses < 0 ? 0 : losses;
  if (w <= 0 && l <= 0) return 0;
  return w / (l <= 0 ? 1 : l);
}

num rankedFightsUsedToday(PlayerSave save, num nowMs) {
  final key = rankedPvpDayKey(nowMs);
  if (save.rankedPvpDayKey != key) return 0;
  final used = save.rankedPvpFightsToday;
  return used < 0 ? 0 : used.floor();
}

num rankedFightsRemaining(PlayerSave save, num nowMs) {
  final left = rankedPvpDailyCap - rankedFightsUsedToday(save, nowMs);
  return left < 0 ? 0 : left;
}

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

RankedPvpStartResult canStartRankedPvp(PlayerSave save, num nowMs) {
  if (rankedFightsRemaining(save, nowMs) <= 0) {
    return const RankedPvpStartResult.failed('Ranked is capped at 5 fights a day.');
  }
  return const RankedPvpStartResult.ok();
}

/// Records a ranked fight: the daily cap, K/D, and 1,000 gold on a win. Search fights skip this.
PlayerSave applyRankedPvpResult(PlayerSave save, bool won, num nowMs) {
  final key = rankedPvpDayKey(nowMs);
  final used = rankedFightsUsedToday(save, nowMs);
  final gold = won ? rankedPvpWinGold : 0;
  final wins = save.rankedPvpWins < 0 ? 0 : save.rankedPvpWins.floor();
  final losses = save.rankedPvpLosses < 0 ? 0 : save.rankedPvpLosses.floor();
  return save.copyWith(
    rankedPvpDayKey: key,
    rankedPvpFightsToday: used + 1,
    rankedPvpWins: wins + (won ? 1 : 0),
    rankedPvpLosses: losses + (won ? 0 : 1),
    gold: save.gold + gold,
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
