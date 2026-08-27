import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../save/generated/save_models.dart';
import 'objectives.dart';
import 'quests.dart';
import 'steps.dart';

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
    final matches = questObjectiveSources(db, quest).any(
      (structured) => targetsOf(structured).any((row) => row.targetId == targetId),
    );
    if (!matches) continue;
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
    if (!questObjectiveSources(db, quest).any((row) => row.learnRecipeIds.contains(recipeId))) {
      continue;
    }
    next = _bumpCounter(next, jsString(quest['Quest ID']), 'learn:$recipeId', 1);
  }
  return next;
}

num questFlag(PlayerSave save, String questId, String key) {
  return getQuestProgress(save, questId).counters?[key] ?? 0;
}

bool hasQuestFlag(PlayerSave save, String questId, String key) =>
    questFlag(save, questId, key) >= 1;

bool questIsActive(PlayerSave save, String questId) {
  return getQuestProgress(save, questId).status == 'active';
}

bool questIsActiveOrComplete(PlayerSave save, String questId) {
  final status = getQuestProgress(save, questId).status;
  return status == 'active' || status == 'completed';
}

PlayerSave setQuestFlag(PlayerSave save, String questId, String key) {
  if (hasQuestFlag(save, questId, key)) return save;
  return _bumpCounter(save, questId, key, 1);
}

/// Records a flag even when the quest is still inactive.
///
/// Donate-before-start needs this: [_bumpCounter] only writes active quests.
PlayerSave recordQuestFlag(PlayerSave save, String questId, String key) {
  if (hasQuestFlag(save, questId, key)) return save;
  final progress = getQuestProgress(save, questId);
  final counters = <String, num>{...?progress.counters, key: 1};
  return save.copyWith(
    quests: [
      ...save.quests.where((row) => row.questId != questId),
      QuestProgress(
        questId: questId,
        status: progress.status,
        counters: counters,
        progress: counters.values.fold<num>(0, (sum, value) => sum + value),
      ),
    ],
  );
}

/// Marks a Talk objective when the player hears that NPC's quest line.
PlayerSave applyQuestTalkProgress(GameDatabase db, PlayerSave save, String npcId) {
  var next = save;
  for (final quest in asQuestRows(db)) {
    if (!questObjectiveSources(db, quest).any((row) => row.talkNpcIds.contains(npcId))) continue;
    next = setQuestFlag(next, jsString(quest['Quest ID']), 'talk:$npcId');
  }
  return next;
}

/// Marks Visit objectives on arrival.
PlayerSave applyQuestVisitProgress(GameDatabase db, PlayerSave save, String locationId) {
  var next = save;
  for (final quest in asQuestRows(db)) {
    if (!questObjectiveSources(db, quest).any((row) => row.visitLocationIds.contains(locationId))) {
      continue;
    }
    next = setQuestFlag(next, jsString(quest['Quest ID']), 'visit:$locationId');
  }
  return next;
}

/// Marks Inspect objectives (bazaar, bounties, processing).
PlayerSave applyQuestInspectProgress(GameDatabase db, PlayerSave save, String inspectId) {
  var next = save;
  for (final quest in asQuestRows(db)) {
    if (!questObjectiveSources(db, quest).any((row) => row.inspectIds.contains(inspectId))) {
      continue;
    }
    next = setQuestFlag(next, jsString(quest['Quest ID']), 'inspect:$inspectId');
  }
  return next;
}

/// Auto-accepts quests whose AutoStart location matches this arrival.
PlayerSave applyQuestAutoStart(GameDatabase db, PlayerSave save, String locationId) {
  var next = save;
  for (final quest in asQuestRows(db)) {
    final structured = parseStructuredObjectives(quest);
    if (structured.autoStartLocationId != locationId) continue;
    final questId = jsString(quest['Quest ID']);
    final progress = getQuestProgress(next, questId);
    if (progress.status != 'inactive') continue;
    if (progress.status == 'completed' && !isQuestRepeatable(quest)) continue;
    next = next.copyWith(
      quests: [
        ...next.quests.where((row) => row.questId != questId),
        QuestProgress(questId: questId, status: 'active', progress: 0),
      ],
    );
  }
  return next;
}

PlayerSave applyQuestLocationProgress(GameDatabase db, PlayerSave save, String locationId) {
  return applyQuestVisitProgress(db, applyQuestAutoStart(db, save, locationId), locationId);
}
