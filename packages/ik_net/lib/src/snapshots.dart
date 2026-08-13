import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'types.dart';

/// One board and the value the player currently holds on it.
class LeaderboardBoardValue {
  const LeaderboardBoardValue({required this.boardKey, required this.value});

  final MultiplayerBoardKey boardKey;
  final num value;

  Map<String, Object?> toJson() => <String, Object?>{'boardKey': boardKey, 'value': value};
}

class LeaderboardSnapshotValues {
  const LeaderboardSnapshotValues({required this.boards});

  final List<LeaderboardBoardValue> boards;

  Map<String, Object?> toJson() => <String, Object?>{
    'boards': boards.map((board) => board.toJson()).toList(),
  };
}

/// Every board value a save implies, submitted on logout or a safe sync.
LeaderboardSnapshotValues buildLeaderboardSnapshot(GameDatabase db, PlayerSave save) {
  num crittersCollected = 0;
  for (final row in save.critterCollections) {
    crittersCollected += math.max(0, row.count);
  }

  final boards = <LeaderboardBoardValue>[
    LeaderboardBoardValue(boardKey: boardTotalLevel, value: totalLevel(save)),
    LeaderboardBoardValue(boardKey: boardTotalExperience, value: totalSkillXp(save)),
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
  if (boardKey == boardTotalLevel) return 'Total Level';
  if (boardKey == boardGuildTotalLevel) return 'Guild Total Level';
  if (boardKey == boardTotalExperience) return 'Total XP';
  if (boardKey == boardGoldEarned) return 'Gold Earned';
  if (boardKey == boardMonstersKilled) return 'Monsters Killed';
  if (boardKey == boardCrittersCollected) return 'Critters Collected';
  if (boardKey == boardBountiesCompleted) return 'Bounties Completed';
  if (boardKey.startsWith(skillBoardPrefix)) {
    final skillId = boardKey.substring(skillBoardPrefix.length);
    final skill = db.skills.where((row) => row.raw['Skill ID'] == skillId).firstOrNull;
    final name = skill?.raw['Display Name'];
    return name is String ? name : skillId;
  }
  return boardKey;
}

/// The boards a launch build shows, in the order the picker lists them.
List<MultiplayerBoardKey> launchBoardKeys(GameDatabase db) => <MultiplayerBoardKey>[
  boardTotalLevel,
  boardGuildTotalLevel,
  boardTotalExperience,
  boardGoldEarned,
  boardMonstersKilled,
  boardCrittersCollected,
  boardBountiesCompleted,
  for (final skill in db.skills.where((row) => row.raw['Release Phase'] == 'Launch'))
    skillBoardKey(skill.raw['Skill ID']! as String),
];
