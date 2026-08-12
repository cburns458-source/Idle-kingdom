import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../save/generated/save_models.dart';
import 'objectives.dart';
import 'quests.dart';

PlayerSave _bumpCounter(PlayerSave save, String questId, String key, num amount) {
  if (amount <= 0) return save;
  final progress = getQuestProgress(save, questId);
  if (progress.status != 'active') return save;
  final counters = <String, num>{...?progress.counters};
  counters[key] = (counters[key] ?? 0) + amount;
  return save.copyWith(
    quests: [
      ...save.quests.where((row) => row.questId != questId),
      QuestProgress(
        questId: progress.questId,
        status: progress.status,
        counters: counters,
        progress: counters.values.fold<num>(0, (sum, value) => sum + value),
      ),
    ],
  );
}

/// Bumps every active quest that counts this target.
PlayerSave _applyProgress(
  GameDatabase db,
  PlayerSave save,
  String counterPrefix,
  List<QuestCounterTarget> Function(StructuredQuestObjectives) targetsOf,
  String targetId,
  num amount,
) {
  var next = save;
  for (final quest in asQuestRows(db)) {
    final structured = parseStructuredObjectives(quest);
    if (!targetsOf(structured).any((row) => row.targetId == targetId)) continue;
    next = _bumpCounter(next, jsString(quest['Quest ID']), '$counterPrefix:$targetId', amount);
  }
  return next;
}

/// Call after defeating an enemy (combat victory).
PlayerSave applyQuestDefeatProgress(
  GameDatabase db,
  PlayerSave save,
  String enemyId, [
  num amount = 1,
]) {
  return _applyProgress(db, save, 'defeat', (row) => row.defeatTargets, enemyId, amount);
}

/// Call after completing a production recipe or special project.
PlayerSave applyQuestProcessProgress(
  GameDatabase db,
  PlayerSave save,
  String recipeOrProjectId, [
  num amount = 1,
]) {
  return _applyProgress(
    db,
    save,
    'process',
    (row) => row.processTargets,
    recipeOrProjectId,
    amount,
  );
}

/// Call when a recipe ID is newly unlocked.
PlayerSave applyQuestLearnRecipeProgress(GameDatabase db, PlayerSave save, String recipeId) {
  var next = save;
  for (final quest in asQuestRows(db)) {
    final structured = parseStructuredObjectives(quest);
    if (!structured.learnRecipeIds.contains(recipeId)) continue;
    next = _bumpCounter(next, jsString(quest['Quest ID']), 'learn:$recipeId', 1);
  }
  return next;
}
