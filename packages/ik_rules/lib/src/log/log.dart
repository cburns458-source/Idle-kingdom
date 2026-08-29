import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../achievements/progress.dart';
import '../critters/critters.dart';
import '../js_compat.dart';
import '../quests/objectives.dart';
import '../quests/quests.dart';
import '../quests/steps.dart';
import '../recipes/knowledge.dart';
import '../save/generated/save_models.dart';
import 'milestones.dart';

export 'milestones.dart';

/// One skill milestone, and whether this save has reached it.
class AchievementLogRow {
  const AchievementLogRow({
    required this.achievementId,
    required this.name,
    required this.note,
    required this.unlocked,
    this.difficulty = 'Easy',
  });

  final String achievementId;
  final String name;

  /// What it takes, even after the deed is finished.
  final String note;
  final bool unlocked;
  final String difficulty;

  Map<String, Object?> toJson() => <String, Object?>{
    'achievementId': achievementId,
    'name': name,
    'note': note,
    'unlocked': unlocked,
    'difficulty': difficulty,
  };
}

List<AchievementLogRow> achievementLog(GameDatabase db, PlayerSave save) {
  return achievementRows(db).map((achievement) {
    final achievementId = jsString(achievement['Achievement ID']);
    final unlocked = save.achievements.any(
      (row) => row.achievementId == achievementId && row.unlocked,
    );
    final difficulty = jsString(achievement['Difficulty']).isEmpty
        ? 'Easy'
        : jsString(achievement['Difficulty']);
    if (achievement['Category'] == revocableAchievementCategory) {
      final held = critterDefs.where((critter) => collectionCount(save, critter.id) > 0).length;
      return AchievementLogRow(
        achievementId: achievementId,
        name: jsString(achievement['Display Name']),
        note:
            'Collect one of every critter '
            '(${jsNumberToString(held)}/${jsNumberToString(critterDefs.length)})',
        unlocked: unlocked,
        difficulty: difficulty,
      );
    }
    return AchievementLogRow(
      achievementId: achievementId,
      name: jsString(achievement['Display Name']),
      note: _achievementNote(achievement),
      unlocked: unlocked,
      difficulty: difficulty,
    );
  }).toList();
}

String _achievementNote(Map<String, Object?> achievement) {
  final check = jsString(achievement['Check Type']);
  final count = achievement['Required Count'];
  final level = achievement['Required Level'];
  switch (check) {
    case 'skill_all':
      return 'Reach level ${jsNumberToString(level is num ? level : 50)} in every skill';
    case 'gold':
      return 'Earn ${formatLogCount(count is num ? count : 0)} gold';
    case 'spell_projects':
      final notes = achievement['Notes'];
      if (notes is String && notes.isNotEmpty) return notes;
      final n = count is num ? count : 1;
      return 'Complete ${jsNumberToString(n)} spell project${n == 1 ? '' : 's'}';
    case 'enchant':
      return 'Enchant an item';
    case 'potion':
      return 'Create a potion';
    case 'consume':
    case 'project':
    case 'output_item':
      final notes = achievement['Notes'];
      return notes is String && notes.isNotEmpty ? notes : 'Complete the required work';
    default:
      final notes = achievement['Notes'];
      return notes is String && notes.isNotEmpty ? notes : 'Locked';
  }
}

String formatLogCount(num value) {
  final whole = value.round();
  final text = jsNumberToString(whole);
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final fromEnd = text.length - i;
    if (i > 0 && fromEnd % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return buffer.toString();
}

List<AchievementLogRow> achievementLogForDifficulty(
  List<AchievementLogRow> rows,
  String difficulty,
) => rows.where((row) => row.difficulty == difficulty).toList();

LogSectionCompletion achievementDifficultyCompletion(
  List<AchievementLogRow> rows,
  String difficulty,
) {
  final group = achievementLogForDifficulty(rows, difficulty);
  return LogSectionCompletion(
    section: difficulty.toLowerCase(),
    done: group.where((row) => row.unlocked).length,
    total: group.length,
  );
}

class QuestLogRow {
  const QuestLogRow({
    required this.questId,
    required this.name,
    required this.detail,
    required this.statusLabel,
    required this.completed,
    required this.steps,
  });

  final String questId;
  final String name;

  /// Vague report of the situation, plus who gave it.
  final String detail;
  final String statusLabel;
  final bool completed;

  /// Revealed steps for active quests.
  final List<QuestJournalStep> steps;

  Map<String, Object?> toJson() => <String, Object?>{
    'questId': questId,
    'name': name,
    'detail': detail,
    'statusLabel': statusLabel,
    'completed': completed,
    'steps': steps.map((step) => step.toJson()).toList(),
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
    final steps = status == 'active'
        ? questUsesSteps(db, questId)
              ? questStepJournal(db, save, quest)
              : questLegacyJournalSteps(db, save, quest)
        : status == 'inactive'
        ? questRequirementJournal(db, save, quest)
        : questCompletedJournal(db, quest);

    return QuestLogRow(
      questId: questId,
      name: jsString(quest['Display Name']),
      detail: '${summary is String ? summary : 'No summary.'} · $npcName',
      statusLabel: questStatusLabel(status),
      completed: status == 'completed',
      steps: steps,
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

String sentenceCase(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return trimmed;
  return '${trimmed[0].toUpperCase()}${trimmed.substring(1).toLowerCase()}';
}

String formatRecipeMaterials(String materials) {
  return materials
      .split(', ')
      .map((part) {
        final match = RegExp(r'^(.*?)\s*×\s*(\d+)\s*$').firstMatch(part);
        if (match != null) {
          return '${sentenceCase(match.group(1) ?? '')} × ${match.group(2)}';
        }
        return sentenceCase(part);
      })
      .join(', ');
}

RecipeLogRow recipeLogRowFromEntry(RecipeBookEntry entry) {
  final proficiency = jsNumberToString(entry.proficiency);
  if (entry.known) {
    return RecipeLogRow(
      key: '${entry.kind}-${entry.id}',
      title: '$proficiency. ${sentenceCase(entry.name)}: ${formatRecipeMaterials(entry.materials)}',
      detail: '',
      known: true,
    );
  }
  // A mentor-taught recipe is not even named until somebody teaches it.
  if (entry.hintUnknown) {
    return RecipeLogRow(
      key: '${entry.kind}-${entry.id}',
      title: 'Unknown recipe',
      detail: entry.knowledgeSource,
      known: false,
    );
  }
  return RecipeLogRow(
    key: '${entry.kind}-${entry.id}',
    title: '$proficiency. ${sentenceCase(entry.name)}',
    detail: 'Unlocks at ${entry.skill} level $proficiency',
    known: false,
  );
}

List<RecipeLogRow> recipeLog(GameDatabase db, PlayerSave save) {
  return listRecipeBookEntries(save, db).map(recipeLogRowFromEntry).toList();
}

List<RecipeLogRow> recipeLogForEntries(List<RecipeBookEntry> entries) {
  return entries.map(recipeLogRowFromEntry).toList();
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

/// How far through one page of the Log a save has got.
class LogSectionCompletion {
  const LogSectionCompletion({required this.section, required this.done, required this.total});

  /// `achievements`, `quests`, or `critters`.
  final String section;
  final num done;
  final num total;

  /// Whole percent, so a page that is nearly done does not read as finished.
  num get percent => total <= 0 ? 0 : (done * 100 / total).floor();

  /// `3/13 · 23%`, the way the Log tabs say it.
  String get label =>
      '${jsNumberToString(done)}/${jsNumberToString(total)} · '
      '${jsNumberToString(percent)}%';

  Map<String, Object?> toJson() => <String, Object?>{
    'section': section,
    'done': done,
    'total': total,
    'percent': percent,
    'label': label,
  };
}

/// Every page of the Log, plus the whole thing counted together.
class LogCompletion {
  const LogCompletion({required this.sections, required this.overall});

  final List<LogSectionCompletion> sections;

  /// Every entry of every page, so one big page cannot be outvoted by a small
  /// one. Its `section` reads `total`.
  final LogSectionCompletion overall;

  LogSectionCompletion? section(String name) =>
      sections.firstWhereOrNull((row) => row.section == name);

  Map<String, Object?> toJson() => <String, Object?>{
    'sections': sections.map((row) => row.toJson()).toList(),
    'overall': overall.toJson(),
  };
}

LogCompletion logCompletion(GameDatabase db, PlayerSave save) {
  final achievements = achievementLog(db, save);
  final milestones = milestoneLog(db, save);
  final quests = questLog(db, save);
  final critters = critterLog(save);

  final sections = <LogSectionCompletion>[
    LogSectionCompletion(
      section: 'achievements',
      done: achievements.where((row) => row.unlocked).length,
      total: achievements.length,
    ),
    LogSectionCompletion(
      section: 'milestones',
      done: milestones.where((row) => row.unlocked).length,
      total: milestones.length,
    ),
    LogSectionCompletion(
      section: 'quests',
      done: quests.where((row) => row.completed).length,
      total: quests.length,
    ),
    LogSectionCompletion(
      section: 'critters',
      done: critters.where((row) => row.found).length,
      total: critters.length,
    ),
  ];

  return LogCompletion(
    sections: sections,
    overall: LogSectionCompletion(
      section: 'total',
      done: sections.fold<num>(0, (sum, row) => sum + row.done),
      total: sections.fold<num>(0, (sum, row) => sum + row.total),
    ),
  );
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
