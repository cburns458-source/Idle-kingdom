import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

GameDatabase _database() => assertGameDatabaseShape(contentDatabaseJson());

void main() {
  test('rebuilds public profile skills from the same snapshot rows', () {
    final db = _database();
    final base = createNewSave(db, 1786568400000);
    final save = base.copyWith(
      skills: [
        for (final skill in base.skills)
          skill.skillId == combatSkillId ? skill.copyWith(level: 18, xp: 4000) : skill,
      ],
    );
    final snapshot = buildLeaderboardSnapshot(db, save);
    final rows = [
      for (final board in snapshot.boards)
        <String, Object?>{
          'board_key': board.boardKey,
          'value': board.value,
          if (board.secondaryValue != null) 'value_secondary': board.secondaryValue,
        },
    ];

    final stats = publicProfileStatsFromLeaderboardRows(rows, db: db);
    expect(stats.totalLevel, totalLevel(save));
    expect(stats.totalXp, totalSkillXp(save));
    expect(stats.logCompletionPercent, logCompletion(db, save).overall.percent);
    expect(stats.skills.where((skill) => skill.skillId == combatSkillId).single.level, 18);
    expect(stats.skills.where((skill) => skill.skillId == combatSkillId).single.xp, 4000);
    expect(
      snapshot.boards
          .where((board) => board.boardKey == skillBoardKey(combatSkillId))
          .single
          .secondaryValue,
      4000,
    );
    expect(
      stats.skills,
      hasLength(db.skills.where((row) => row.raw['Release Phase'] == 'Launch').length),
    );
  });
}
