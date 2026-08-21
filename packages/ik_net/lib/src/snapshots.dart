import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'types.dart';

/// One board and the value the player currently holds on it.
class LeaderboardBoardValue {
  const LeaderboardBoardValue({required this.boardKey, required this.value, this.secondaryValue});

  final MultiplayerBoardKey boardKey;
  final num value;

  /// The second number a combined board shows, and the tie-break on the first.
  final num? secondaryValue;

  Map<String, Object?> toJson() => <String, Object?>{
    'boardKey': boardKey,
    'value': value,
    if (secondaryValue != null) 'secondaryValue': secondaryValue,
  };
}

class LeaderboardSnapshotValues {
  const LeaderboardSnapshotValues({required this.boards});

  final List<LeaderboardBoardValue> boards;

  Map<String, Object?> toJson() => <String, Object?>{
    'boards': boards.map((board) => board.toJson()).toList(),
  };
}

/// Every board value a save implies, submitted on a ranking update.
LeaderboardSnapshotValues buildLeaderboardSnapshot(GameDatabase db, PlayerSave save) {
  num crittersCollected = 0;
  for (final row in save.critterCollections) {
    crittersCollected += math.max(0, row.count);
  }

  final level = totalLevel(save);
  final xp = totalSkillXp(save);
  final pacifist = isPacifistSave(save);

  final boards = <LeaderboardBoardValue>[
    LeaderboardBoardValue(boardKey: boardTotalLevel, value: level, secondaryValue: xp),
    // Zero keeps a fighter off the board without needing a delete: the read
    // drops zero rows, and one is written again the moment they qualify.
    LeaderboardBoardValue(
      boardKey: boardPacifistTotalLevel,
      value: pacifist ? level : 0,
      secondaryValue: pacifist ? xp : 0,
    ),
    LeaderboardBoardValue(
      boardKey: boardGoldEarned,
      value: jsNumber(save.statistics.values['gold_earned'] ?? 0),
    ),
    LeaderboardBoardValue(
      boardKey: boardMonstersKilled,
      value: jsNumber(save.statistics.values['monsters_killed'] ?? 0),
    ),
    LeaderboardBoardValue(boardKey: boardCrittersCollected, value: crittersCollected),
    LeaderboardBoardValue(
      boardKey: boardBountiesCompleted,
      value: jsNumber(save.statistics.values['bounties_completed'] ?? 0),
    ),
    LeaderboardBoardValue(
      boardKey: boardPvpKd,
      value: rankedPvpKd(save.rankedPvpWins, save.rankedPvpLosses),
    ),
  ];

  for (final skill in db.skills.where((row) => row.raw['Release Phase'] == 'Launch')) {
    final skillId = skill.raw['Skill ID']! as String;
    final progress = save.skills.where((row) => row.skillId == skillId).firstOrNull;
    final level = progress?.level ?? 1;
    final xp = progress?.xp ?? 0;
    // Past 100 the boards rank by XP; at or under it they rank by level, with
    // XP still stored so ties resolve.
    boards.add(
      LeaderboardBoardValue(boardKey: skillBoardKey(skillId), value: level > 100 ? xp : level),
    );
  }

  return LeaderboardSnapshotValues(boards: boards);
}

String boardLabel(GameDatabase db, MultiplayerBoardKey boardKey) {
  if (boardKey == boardTotalLevel) return 'Total Level & XP';
  if (boardKey == boardGuildTotalLevel) return 'Guild Total Level';
  if (boardKey == boardPacifistTotalLevel) return 'Pacifist Total Level';
  if (boardKey == boardTotalExperience) return 'Total XP';
  if (boardKey == boardGoldEarned) return 'Gold Earned';
  if (boardKey == boardMonstersKilled) return 'Monsters Killed';
  if (boardKey == boardCrittersCollected) return 'Critters Collected';
  if (boardKey == boardBountiesCompleted) return 'Bounties Completed';
  if (boardKey == boardPvpKd) return 'PvP K/D';
  if (boardKey.startsWith(skillBoardPrefix)) {
    final skillId = boardKey.substring(skillBoardPrefix.length);
    final skill = db.skills.where((row) => row.raw['Skill ID'] == skillId).firstOrNull;
    final name = skill?.raw['Display Name'];
    return name is String ? name : skillId;
  }
  return boardKey;
}

/// Puts the signed-in account's live score on the board, replacing whatever row
/// was stored for it.
///
/// A board is a snapshot table, so the account's own standing would otherwise
/// wait for the next submit to appear. Guild boards are left alone: their value
/// is the whole roster, which only the backend can total.
List<LeaderboardEntry> mergeLiveLeaderboardScore({
  required List<LeaderboardEntry> stored,
  required MultiplayerBoardKey boardKey,
  required GameDatabase db,
  required PlayerSave save,
  required String userId,
  required String username,
  required PlayerAppearance appearance,
  String? guildName,
}) {
  if (boardKey == boardGuildTotalLevel) return stored;
  final mine = buildLeaderboardSnapshot(
    db,
    save,
  ).boards.firstWhereOrNull((board) => board.boardKey == boardKey);
  if (mine == null) return stored;

  // A board the player does not qualify for shows them nothing of their own.
  if (boardHidesZeroes(boardKey) && mine.value <= 0) {
    return stored.where((entry) => entry.userId != userId).toList();
  }

  final merged = <LeaderboardEntry>[
    ...stored.where((entry) => entry.userId != userId),
    LeaderboardEntry(
      userId: userId,
      username: username,
      appearance: appearance,
      guildName: guildName,
      boardKey: boardKey,
      value: mine.value,
      rank: 0,
      secondaryValue: mine.secondaryValue,
    ),
  ];
  return rankLeaderboardEntries(merged);
}

/// Orders a board and stamps places on it.
///
/// Highest value first, then the second number where a board carries one, then
/// name, so two players on the same total level are split by experience.
List<LeaderboardEntry> rankLeaderboardEntries(List<LeaderboardEntry> entries) {
  final ordered = <LeaderboardEntry>[...entries];
  mergeSort(
    ordered,
    compare: (a, b) => jsCompareThen(
      b.value - a.value,
      () => jsCompareThen(
        (b.secondaryValue ?? 0) - (a.secondaryValue ?? 0),
        () => jsLocaleCompare(a.username, b.username),
      ),
    ),
  );
  return ordered.indexed.map((entry) => entry.$2.withRank(entry.$1 + 1)).toList();
}

/// The boards a launch build shows, in the order the picker lists them.
///
/// Total XP has no board of its own: it rides along on Total Level & XP.
List<MultiplayerBoardKey> launchBoardKeys(GameDatabase db) => <MultiplayerBoardKey>[
  boardTotalLevel,
  boardGuildTotalLevel,
  boardPacifistTotalLevel,
  boardGoldEarned,
  boardMonstersKilled,
  boardCrittersCollected,
  boardBountiesCompleted,
  boardPvpKd,
  for (final skill in db.skills.where((row) => row.raw['Release Phase'] == 'Launch'))
    skillBoardKey(skill.raw['Skill ID']! as String),
];

/// Public skill levels and total level reconstructed from ranking snapshots.
///
/// The same rows the leaderboard lists. Past 100 a skill board stores XP, not
/// level, matching [buildLeaderboardSnapshot].
class PublicProfileStats {
  const PublicProfileStats({required this.totalLevel, required this.skills, this.totalXp});

  final num totalLevel;
  final num? totalXp;
  final List<PublicSkillLine> skills;
}

/// Turns `leaderboard_snapshots` rows for one account into profile stats.
PublicProfileStats publicProfileStatsFromLeaderboardRows(
  Iterable<Map<String, Object?>> rows, {
  GameDatabase? db,
}) {
  num totalLevel = 0;
  num? totalXp;
  final skills = <PublicSkillLine>[];
  for (final row in rows) {
    final key = jsString(row['board_key'] ?? row['boardKey'] ?? '');
    final value = jsNumber(row['value'] ?? 0);
    if (key == boardTotalLevel) {
      totalLevel = value;
      final secondary = row['value_secondary'] ?? row['secondaryValue'];
      if (secondary is num) totalXp = secondary;
      continue;
    }
    if (!key.startsWith(skillBoardPrefix)) continue;
    final skillId = key.substring(skillBoardPrefix.length);
    if (skillId.isEmpty) continue;
    if (value > 100) {
      skills.add(
        PublicSkillLine(
          skillId: skillId,
          level: db == null ? 101 : levelForTotalXp(db, value),
          xp: value,
        ),
      );
    } else {
      skills.add(PublicSkillLine(skillId: skillId, level: value < 1 ? 1 : value, xp: 0));
    }
  }
  return PublicProfileStats(totalLevel: totalLevel, skills: skills, totalXp: totalXp);
}
