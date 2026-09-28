import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../inventory/add_items.dart';
import '../js_compat.dart';
import '../production/inventory.dart';
import '../production/recipes.dart';
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
  if (!save.quests.any((row) => row.status == 'active')) return save;
  var next = save;
  for (final quest in asQuestRows(db)) {
    final questId = jsString(quest['Quest ID']);
    if (getQuestProgress(next, questId).status != 'active') continue;
    final matches = questObjectiveSources(
      db,
      quest,
    ).any((structured) => targetsOf(structured).any((row) => row.targetId == targetId));
    if (!matches) continue;
    next = _bumpCounter(next, questId, '$counterPrefix:$targetId', amount);
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
  return applyQuestStepUnlocks(
    db,
    _applyProgress(db, save, 'process', (row) => row.processTargets, recipeOrProjectId, amount),
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

bool questIsComplete(PlayerSave save, String questId) {
  return getQuestProgress(save, questId).status == 'completed';
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

bool _saveHasBotanySeed(GameDatabase db, PlayerSave save) {
  bool isSeed(String itemId) {
    final item = db.items.where((row) => row.raw['Item ID'] == itemId).firstOrNull;
    final tags = (item?.functionalSourceTags ?? '').toLowerCase();
    return tags.contains('botany_seed') || tags.contains('botany_sapling');
  }

  return [
    ...save.inventory,
    ...save.bank,
  ].any((stack) => stack.quantity > 0 && isSeed(stack.itemId));
}

/// Auto-accepts quests whose AutoStartOnSeed note is set and a seed is owned.
PlayerSave applyQuestAutoStartOnSeed(GameDatabase db, PlayerSave save) {
  if (!_saveHasBotanySeed(db, save)) return save;
  var next = save;
  for (final quest in asQuestRows(db)) {
    final structured = parseStructuredObjectives(quest);
    if (!structured.autoStartOnSeed) continue;
    final questId = jsString(quest['Quest ID']);
    final progress = getQuestProgress(next, questId);
    if (progress.status != 'inactive') continue;
    if (structured.requiresQuestIds.any(
      (requiredQuestId) => getQuestProgress(next, requiredQuestId).status != 'completed',
    )) {
      continue;
    }
    next = next.copyWith(
      quests: [
        ...next.quests.where((row) => row.questId != questId),
        QuestProgress(questId: questId, status: 'active', progress: 0),
      ],
    );
  }
  return next;
}

PlayerSave _grantGiveOnTalk(
  GameDatabase db,
  PlayerSave save,
  String questId,
  List<QuestCounterTarget> grants,
) {
  var next = save;
  for (final grant in grants) {
    final flag = 'give:${grant.targetId}';
    if (hasQuestFlag(next, questId, flag)) continue;
    next = addItemToInventory(next, grant.targetId, grant.quantity, null, false, db);
    next = recordQuestFlag(next, questId, flag);
  }
  return next;
}

/// Marks a Talk objective when the player hears that NPC's quest line.
PlayerSave applyQuestTalkProgress(GameDatabase db, PlayerSave save, String npcId) {
  var next = applyQuestAutoStartOnSeed(db, save);
  for (final quest in asQuestRows(db)) {
    final questId = jsString(quest['Quest ID']);
    if (getQuestProgress(next, questId).status != 'active') continue;
    if (!questCanTalkToNpc(db, next, quest, npcId)) continue;
    final stepObjectives =
        questActiveStepObjectives(db, next, quest) ?? parseStructuredObjectives(quest);
    if (stepObjectives.giveOnTalk.isNotEmpty && !hasQuestFlag(next, questId, 'talk:$npcId')) {
      next = _grantGiveOnTalk(db, next, questId, stepObjectives.giveOnTalk);
    }
    final stepKey = currentStepTalkKey(db, next, quest, npcId);
    next = setQuestFlag(next, questId, 'talk:$npcId');
    next = setQuestFlag(next, questId, stepKey);
  }
  return applyQuestStepUnlocks(db, applyQuestAutoStartOnSeed(db, next));
}

/// Marks Plant objectives after seeds go into a patch.
PlayerSave applyQuestPlantProgress(
  GameDatabase db,
  PlayerSave save,
  List<String> plantedItemIds, {
  bool usedCompost = false,
}) {
  if (plantedItemIds.isEmpty) return save;
  var next = save;
  for (final itemId in plantedItemIds.toSet()) {
    for (final quest in asQuestRows(db)) {
      final questId = jsString(quest['Quest ID']);
      if (getQuestProgress(next, questId).status != 'active') continue;
      final current =
          questActiveStepObjectives(db, next, quest) ?? parseStructuredObjectives(quest);
      if (!current.plantTargets.any((target) => target.targetId == itemId)) continue;
      if (current.requiresCompost && !usedCompost) continue;
      next = _bumpCounter(next, questId, 'plant:$itemId', 1);
    }
  }
  return next;
}

/// True when an unfinished plant step still needs compost for these seeds.
bool questPlantRequiresCompost(GameDatabase db, PlayerSave save, List<String> plantedItemIds) {
  if (plantedItemIds.isEmpty) return false;
  for (final quest in asQuestRows(db)) {
    final questId = jsString(quest['Quest ID']);
    if (getQuestProgress(save, questId).status != 'active') continue;
    if (questUsesSteps(db, questId)) {
      final steps = getQuestSteps(db, questId);
      final start = getCurrentStepIndex(db, save, quest);
      for (final step in steps.skip(start)) {
        final current = parseNotesObjectives(step.notes ?? '');
        if (current.requiresCompost &&
            current.plantTargets.any((target) => plantedItemIds.contains(target.targetId))) {
          return true;
        }
      }
      continue;
    }
    final current = parseStructuredObjectives(quest);
    if (current.requiresCompost &&
        current.plantTargets.any((target) => plantedItemIds.contains(target.targetId))) {
      return true;
    }
  }
  return false;
}

/// Marks Action objectives after a gathering action completes.
PlayerSave applyQuestActionProgress(
  GameDatabase db,
  PlayerSave save,
  String actionId, [
  num amount = 1,
]) {
  if (!save.quests.any((row) => row.status == 'active')) return save;
  var next = save;
  for (final quest in asQuestRows(db)) {
    final questId = jsString(quest['Quest ID']);
    if (getQuestProgress(next, questId).status != 'active') continue;
    if (!questObjectiveSources(
      db,
      quest,
    ).any((row) => row.actionTargets.any((target) => target.targetId == actionId))) {
      continue;
    }
    next = _bumpCounter(next, questId, 'action:$actionId', amount);
  }
  return applyQuestStepUnlocks(db, next);
}

/// Popup when an offering is consumed on arrival.
const String forestOfferingPlacedMessage = 'You place the offering for the forest';

class QuestOfferingArrival {
  const QuestOfferingArrival({required this.save, required this.message});

  final PlayerSave save;
  final String? message;
}

/// Consumes `Offering:` items on Visit steps. Silent without the item.
QuestOfferingArrival applyQuestOfferingArrival(
  GameDatabase db,
  PlayerSave save,
  String locationId,
) {
  var next = save;
  String? message;
  for (final quest in asQuestRows(db)) {
    final questId = jsString(quest['Quest ID']);
    if (getQuestProgress(next, questId).status != 'active') continue;
    if (!questUsesSteps(db, questId)) continue;
    final current = questActiveStepObjectives(db, next, quest);
    final offeringId = current?.offeringItemId;
    if (offeringId == null || offeringId.isEmpty) continue;
    if (!current!.visitLocationIds.contains(locationId)) continue;
    if (hasQuestFlag(next, questId, 'visit:$locationId')) continue;
    if (inventoryCount(next, offeringId) < 1) continue;
    final removed = removeIngredients(next, [RecipeIngredient(itemId: offeringId, quantity: 1)]);
    if (removed == null) continue;
    next = setQuestFlag(removed, questId, 'visit:$locationId');
    message = forestOfferingPlacedMessage;
  }
  return QuestOfferingArrival(save: applyQuestStepUnlocks(db, next), message: message);
}

bool _currentStepRequiresOfferingVisit(
  GameDatabase db,
  PlayerSave save,
  QuestRow quest,
  String locationId,
) {
  final questId = jsString(quest['Quest ID']);
  if (!questUsesSteps(db, questId)) return false;
  final current = questActiveStepObjectives(db, save, quest);
  final offeringId = current?.offeringItemId;
  return offeringId != null &&
      offeringId.isNotEmpty &&
      current!.visitLocationIds.contains(locationId);
}

/// Marks Visit objectives on arrival.
PlayerSave applyQuestVisitProgress(GameDatabase db, PlayerSave save, String locationId) {
  var next = save;
  for (final quest in asQuestRows(db)) {
    if (_currentStepRequiresOfferingVisit(db, next, quest, locationId)) continue;
    if (!questObjectiveSources(db, quest).any((row) => row.visitLocationIds.contains(locationId))) {
      continue;
    }
    next = setQuestFlag(next, jsString(quest['Quest ID']), 'visit:$locationId');
  }
  return applyQuestStepUnlocks(db, next);
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
  return applyQuestLocationProgressResult(db, save, locationId).save;
}

QuestOfferingArrival applyQuestLocationProgressResult(
  GameDatabase db,
  PlayerSave save,
  String locationId,
) {
  final started = applyQuestAutoStartOnSeed(db, applyQuestAutoStart(db, save, locationId));
  final offering = applyQuestOfferingArrival(db, started, locationId);
  return QuestOfferingArrival(
    save: applyQuestVisitProgress(db, offering.save, locationId),
    message: offering.message,
  );
}
