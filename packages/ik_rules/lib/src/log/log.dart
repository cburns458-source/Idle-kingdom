import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../achievements/progress.dart';
import '../critters/critters.dart';
import '../js_compat.dart';
import '../quests/objectives.dart';
import '../quests/quests.dart';
import '../recipes/knowledge.dart';
import '../save/generated/save_models.dart';

/// One skill milestone, and whether this save has reached it.
class AchievementLogRow {
  const AchievementLogRow({
    required this.achievementId,
    required this.name,
    required this.note,
    required this.unlocked,
  });

  final String achievementId;
  final String name;

  /// `Unlocked`, or what it takes: `Reach Mining level 50`.
  final String note;
  final bool unlocked;

  Map<String, Object?> toJson() => <String, Object?>{
    'achievementId': achievementId,
    'name': name,
    'note': note,
    'unlocked': unlocked,
  };
}

List<AchievementLogRow> achievementLog(GameDatabase db, PlayerSave save) {
  return achievementRows(db).map((achievement) {
    final achievementId = jsString(achievement['Achievement ID']);
    final unlocked = save.achievements.any(
      (row) => row.achievementId == achievementId && row.unlocked,
    );
    final skill = db.skills.firstWhereOrNull(
      (row) => row.raw['Skill ID'] == achievement['Target Skill ID'],
    );
    final skillName = skill?.raw['Display Name'] is String
        ? skill!.raw['Display Name']! as String
        : 'Skill';
    final level = achievement['Required Level'];
    return AchievementLogRow(
      achievementId: achievementId,
      name: jsString(achievement['Display Name']),
      note: unlocked
          ? 'Unlocked'
          : 'Reach $skillName level ${jsNumberToString(level is num ? level : 50)}',
      unlocked: unlocked,
    );
  }).toList();
}

/// One objective of an active quest, with its bar already worked out.
class QuestLogObjective {
  const QuestLogObjective({required this.key, required this.label, required this.percent});

  final String key;

  /// `Deliver Cabbage: 3/5`.
  final String label;

  /// 0–100, capped, for the bar.
  final num percent;

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'label': label,
    'percent': percent,
  };
}

class QuestLogRow {
  const QuestLogRow({
    required this.questId,
    required this.name,
    required this.detail,
    required this.statusLabel,
    required this.completed,
    required this.objectives,
  });

  final String questId;
  final String name;

  /// `Rose needs herbs. · Rose`, the summary and who gave it.
  final String detail;
  final String statusLabel;
  final bool completed;

  /// Empty unless the quest is active and asks for something countable.
  final List<QuestLogObjective> objectives;

  Map<String, Object?> toJson() => <String, Object?>{
    'questId': questId,
    'name': name,
    'detail': detail,
    'statusLabel': statusLabel,
    'completed': completed,
    'objectives': objectives.map((objective) => objective.toJson()).toList(),
  };
}

List<QuestLogRow> questLog(GameDatabase db, PlayerSave save) {
  return asQuestRows(db).map((quest) {
    final questId = jsString(quest['Quest ID']);
    final status = getQuestProgress(save, questId).status;
    final npc = db.npcs.firstWhereOrNull((row) => row.raw['NPC ID'] == quest['NPC ID']);
    final npcName = npc?.raw['Display Name'] is String
        ? npc!.raw['Display Name']! as String
        : 'NPC';
    final summary = quest['Summary'];
    final objectives = status == 'active'
        ? questObjectiveProgress(db, save, quest).progressLines
        : const <QuestProgressLine>[];

    return QuestLogRow(
      questId: questId,
      name: jsString(quest['Display Name']),
      detail: '${summary is String ? summary : 'No summary.'} · $npcName',
      statusLabel: questStatusLabel(status),
      completed: status == 'completed',
      objectives: objectives
          .map(
            (line) => QuestLogObjective(
              key: line.key,
              label:
                  '${line.label}: ${jsNumberToString(math.min(line.current, line.required))}'
                  '/${jsNumberToString(line.required)}',
              percent: math.min(
                100,
                (line.current / math.max(1, line.required) * 100).floor(),
              ),
            ),
          )
          .toList(),
    );
  }).toList();
}

/// One line of the recipe book, said the way a locked one has to be said.
class RecipeLogRow {
  const RecipeLogRow({
    required this.key,
    required this.title,
    required this.detail,
    required this.known,
  });

  final String key;

  /// The recipe's name, or what little a locked one gives away.
  final String title;
  final String detail;
  final bool known;

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'title': title,
    'detail': detail,
    'known': known,
  };
}

List<RecipeLogRow> recipeLog(GameDatabase db, PlayerSave save) {
  return listRecipeBookEntries(save, db).map((entry) {
    final kind = entry.kind == 'project' ? 'Project' : 'Recipe';
    final proficiency = jsNumberToString(entry.proficiency);
    if (entry.known) {
      return RecipeLogRow(
        key: '${entry.kind}-${entry.id}',
        title: entry.name,
        detail:
            '$kind · ${entry.skill} $proficiency · '
            '${entry.station} (${entry.location}) · ${entry.materials} → ${entry.output}',
        known: true,
      );
    }
    // A mentor-taught recipe is not even named until somebody teaches it.
    return RecipeLogRow(
      key: '${entry.kind}-${entry.id}',
      title: entry.hintUnknown ? 'Unknown recipe' : 'Locked · ${entry.skill} $proficiency',
      detail: entry.hintUnknown
          ? entry.knowledgeSource
          : 'Unlocks at ${entry.skill} level $proficiency',
      known: false,
    );
  }).toList();
}

/// One page of the critter collection, blank until one has been caught.
class CritterLogRow {
  const CritterLogRow({
    required this.critterId,
    required this.internalKey,
    required this.name,
    required this.description,
    required this.count,
    required this.found,
  });

  final String critterId;
  final String internalKey;

  /// `Unknown` until the player has met it.
  final String name;

  /// Null while unknown, so nothing is given away.
  final String? description;
  final num count;
  final bool found;

  Map<String, Object?> toJson() => <String, Object?>{
    'critterId': critterId,
    'internalKey': internalKey,
    'name': name,
    'description': description,
    'count': count,
    'found': found,
  };
}

List<CritterLogRow> critterLog(PlayerSave save) {
  return critterDefs.map((critter) {
    final count = collectionCount(save, critter.id);
    final found = count > 0;
    return CritterLogRow(
      critterId: critter.id,
      internalKey: critter.internalKey,
      name: found ? critter.displayName : 'Unknown',
      description: found ? critter.description : null,
      count: count,
      found: found,
    );
  }).toList();
}
