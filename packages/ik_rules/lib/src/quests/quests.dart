import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/xp.dart';
import '../combat/stats.dart';
import '../cosmetics/cosmetics.dart';
import '../inventory/add_items.dart';
import '../js_compat.dart';
import '../production/inventory.dart';
import '../production/recipes.dart';
import '../recipes/knowledge.dart';
import '../save/generated/save_models.dart';
import '../world/submaps.dart';
import 'objectives.dart';
import 'progress.dart';

/// Quests live in an untyped content table, so rows stay raw maps here.
typedef QuestRow = Map<String, Object?>;

List<QuestRow> asQuestRows(GameDatabase db) => db.quests;

QuestRow? getQuest(GameDatabase db, String questId) {
  return asQuestRows(db).firstWhereOrNull((quest) => quest['Quest ID'] == questId);
}

List<QuestRow> questsForNpc(GameDatabase db, String npcId) {
  return asQuestRows(db).where((quest) => quest['NPC ID'] == npcId).toList();
}

QuestProgress getQuestProgress(PlayerSave save, String questId) {
  return save.quests.firstWhereOrNull((quest) => quest.questId == questId) ??
      QuestProgress(questId: questId, status: 'inactive', progress: 0);
}

bool isQuestRepeatable(QuestRow quest) {
  final flag = quest['Repeatable'] is String
      ? (quest['Repeatable']! as String).toLowerCase()
      : 'no';
  return flag == 'yes' || flag == 'true' || flag == 'repeatable';
}

/// Either the updated save or the reason the change was refused.
class QuestActionResult {
  const QuestActionResult.ok(this.save) : reason = null;

  const QuestActionResult.failed(this.reason) : save = null;

  bool get ok => reason == null;
  final PlayerSave? save;
  final String? reason;
}

List<QuestRow> questsTouchingNpc(GameDatabase db, String npcId) {
  return asQuestRows(db).where((quest) {
    if (quest['NPC ID'] == npcId) return true;
    final parsed = parseStructuredObjectives(quest);
    return parsed.talkNpcIds.contains(npcId) ||
        parsed.turnInNpcId == npcId ||
        parsed.choiceNpcId == npcId;
  }).toList();
}

QuestActionResult acceptQuest(
  GameDatabase db,
  PlayerSave save,
  String questId, {
  bool ignoreLocation = false,
}) {
  final quest = getQuest(db, questId);
  if (quest == null) return const QuestActionResult.failed('Quest not found.');
  final parsed = parseStructuredObjectives(quest);
  if (!ignoreLocation) {
    final npc = db.npcs.firstWhereOrNull((row) => row.raw['NPC ID'] == quest['NPC ID']);
    if (npc == null || npc.raw['Location ID'] != save.currentLocationId) {
      return const QuestActionResult.failed('Speak with the quest giver at their location.');
    }
  }
  final progress = getQuestProgress(save, questId);
  if (progress.status == 'active') {
    return const QuestActionResult.failed('This quest is already active.');
  }
  if (progress.status == 'completed' && !isQuestRepeatable(quest)) {
    return const QuestActionResult.failed('This quest is already completed.');
  }
  if (parsed.acceptGoldCost > 0 && save.gold < parsed.acceptGoldCost) {
    return QuestActionResult.failed(
      'Need ${jsLocaleNumber(parsed.acceptGoldCost)} gold to start this quest.',
    );
  }

  var next = save;
  if (parsed.acceptGoldCost > 0) {
    next = next.copyWith(gold: next.gold - parsed.acceptGoldCost);
  }

  return QuestActionResult.ok(
    next.copyWith(
      quests: [
        ...next.quests.where((row) => row.questId != questId),
        QuestProgress(questId: questId, status: 'active', progress: 0),
      ],
    ),
  );
}

class QuestCompletion {
  const QuestCompletion.ok({
    required this.save,
    required this.message,
    required this.questName,
    required this.rewards,
    this.pendingSkillXp = 0,
  }) : reason = null;

  const QuestCompletion.failed(this.reason)
    : save = null,
      message = null,
      questName = null,
      rewards = const <String>[],
      pendingSkillXp = 0;

  bool get ok => reason == null;
  final PlayerSave? save;
  final String? message;
  final String? questName;

  /// Reward lines shown on turn-in, in the order they were granted.
  final List<String> rewards;

  /// Bribe-route XP the player still has to assign to a non-combat skill.
  final num pendingSkillXp;
  final String? reason;
}

String _skillName(GameDatabase db, String skillId) {
  final displayName = db.skills
      .firstWhereOrNull((skill) => skill.raw['Skill ID'] == skillId)
      ?.raw['Display Name'];
  return displayName is String ? displayName : 'skill';
}

final RegExp _objectiveVerb = RegExp(r'^(Deliver|Defeat|Craft|Learn)\s+', caseSensitive: false);

QuestCompletion completeQuest(GameDatabase db, PlayerSave save, String questId) {
  final quest = getQuest(db, questId);
  if (quest == null) return const QuestCompletion.failed('Quest not found.');
  final parsed = parseStructuredObjectives(quest);
  final npcId = parsed.turnInNpcId ?? quest['NPC ID'];
  final npc = db.npcs.firstWhereOrNull((row) => row.raw['NPC ID'] == npcId);
  if (npc == null || npc.raw['Location ID'] != save.currentLocationId) {
    return const QuestCompletion.failed('Return to the quest giver to turn this in.');
  }

  final progress = getQuestProgress(save, questId);
  if (progress.status == 'completed') {
    return QuestCompletion.failed(
      isQuestRepeatable(quest)
          ? 'Accept this quest again before turning it in.'
          : 'This quest is already completed.',
    );
  }
  if (progress.status != 'active') {
    return const QuestCompletion.failed('Accept this quest before turning it in.');
  }

  final hasObjectives =
      parsed.delivers.isNotEmpty ||
      parsed.defeatTargets.isNotEmpty ||
      parsed.processTargets.isNotEmpty ||
      parsed.learnRecipeIds.isNotEmpty ||
      parsed.talkNpcIds.isNotEmpty ||
      parsed.visitLocationIds.isNotEmpty ||
      parsed.inspectIds.isNotEmpty ||
      parsed.goldCost > 0;
  if (!hasObjectives) {
    return const QuestCompletion.failed('Quest objectives are incomplete in data.');
  }

  final status = questObjectiveProgress(db, save, quest);
  if (!status.ready) {
    final missing = status.progressLines
        .where((line) => line.current < line.required)
        .map(
          (line) =>
              '${jsNumberToString(line.required)} ${line.label.replaceFirst(_objectiveVerb, '')}',
        )
        .toList();
    return QuestCompletion.failed(
      missing.isNotEmpty ? 'Need ${missing.join(', ')}.' : 'Objectives incomplete.',
    );
  }

  var next = save;
  if (parsed.delivers.isNotEmpty) {
    final removed = removeIngredients(
      next,
      parsed.delivers
          .map((line) => RecipeIngredient(itemId: line.targetId, quantity: line.quantity))
          .toList(),
    );
    if (removed == null) return const QuestCompletion.failed('Missing required items.');
    next = removed;
  }

  if (parsed.goldCost > 0) {
    if (next.gold < parsed.goldCost) {
      return QuestCompletion.failed('Need ${jsLocaleNumber(parsed.goldCost)} gold.');
    }
    next = next.copyWith(gold: next.gold - parsed.goldCost);
  }

  final rewards = <String>[];
  num pendingSkillXp = 0;
  final bribed = hasQuestFlag(save, questId, 'choice:bribe');
  final xpSkill = quest['Reward XP Skill ID'];
  final xpAmount = quest['Reward XP Amount'];
  if (bribed && parsed.branchSkillXp > 0) {
    pendingSkillXp = parsed.branchSkillXp;
    rewards.add('Choose ${jsLocaleNumber(pendingSkillXp)} XP in a non-combat skill');
  } else if (xpSkill is String && xpSkill.isNotEmpty && xpAmount is num && xpAmount > 0) {
    next = applyXp(next, db, xpSkill, xpAmount).save;
    rewards.add('${jsLocaleNumber(xpAmount)} ${_skillName(db, xpSkill)} XP');
  }

  if (parsed.rewardGold > 0) {
    next = next.copyWith(gold: next.gold + parsed.rewardGold);
    rewards.add('${jsLocaleNumber(parsed.rewardGold)} gold');
  }

  final rewardItemId = quest['Reward Item ID'];
  final rewardQty = quest['Reward Item Quantity'];
  if (rewardItemId is String && rewardItemId.isNotEmpty && rewardQty is num && rewardQty > 0) {
    next = addItemToInventory(next, rewardItemId, rewardQty);
    final itemName = db.items
        .firstWhereOrNull((item) => item.raw['Item ID'] == rewardItemId)
        ?.raw['Display Name'];
    rewards.add('${jsNumberToString(rewardQty)}× ${itemName is String ? itemName : 'item'}');
  }

  var unlocked = next.unlockedLocationIds;
  for (final locationId in parsed.unlockLocationIds) {
    final before = unlocked.length;
    unlocked = unlockLocation(unlocked, locationId);
    if (unlocked.length > before) {
      final locationName = db.locations
          .firstWhereOrNull((location) => location.raw['Location ID'] == locationId)
          ?.raw['Display Name'];
      rewards.add('Unlocked ${locationName is String ? locationName : locationId}');
    }
  }

  for (final recipeId in parsed.rewardRecipeIds) {
    final before = next.unlockedRecipeIds.length;
    next = unlockRecipeId(next, recipeId);
    if (next.unlockedRecipeIds.length > before) {
      next = applyQuestLearnRecipeProgress(db, next, recipeId);
      final recipeName = db.recipes
          .firstWhereOrNull((recipe) => recipe.raw['Recipe ID'] == recipeId)
          ?.raw['Display Name'];
      rewards.add('Learned ${recipeName is String ? recipeName : recipeId}');
    }
  }

  for (final npcId in parsed.rewardProjectNpcIds) {
    if (next.unlockedNpcIds.contains(npcId)) continue;
    next = next.copyWith(unlockedNpcIds: [...next.unlockedNpcIds, npcId]);
    final npcName = db.npcs
        .firstWhereOrNull((row) => row.raw['NPC ID'] == npcId)
        ?.raw['Display Name'];
    rewards.add('Project knowledge from ${npcName is String ? npcName : npcId}');
  }

  for (final cosmeticId in parsed.rewardCosmeticIds) {
    final granted = grantCosmetic(next, cosmeticId);
    next = granted.save;
    if (granted.granted) {
      final cosmetic = cosmeticById(db, cosmeticId);
      final itemId = cosmetic?.raw['Item ID'];
      final itemName = itemId is String
          ? db.items.firstWhereOrNull((item) => item.raw['Item ID'] == itemId)?.raw['Display Name']
          : null;
      rewards.add(itemName is String ? itemName : cosmeticId);
    }
  }

  final progressTotal = status.progressLines.fold<num>(0, (sum, line) => sum + line.required);
  next = next.copyWith(
    quests: [
      ...next.quests.where((row) => row.questId != questId),
      QuestProgress(
        questId: questId,
        status: 'completed',
        progress: progressTotal,
        counters: const <String, num>{},
      ),
    ],
    unlockedLocationIds: unlocked,
  );

  return QuestCompletion.ok(
    save: next,
    questName: jsString(quest['Display Name']),
    rewards: rewards,
    pendingSkillXp: pendingSkillXp,
    message: rewards.isNotEmpty ? 'Quest complete — ${rewards.join(' and ')}.' : 'Quest complete.',
  );
}

/// Skills the bribe-route popup may grant, Combat excluded.
List<SkillRow> selectableNonCombatSkills(GameDatabase db) {
  return db.skills.where((skill) => skill.skillId != combatSkillId).toList();
}

QuestActionResult applyQuestBranchSkillXp(
  GameDatabase db,
  PlayerSave save,
  String skillId,
  num amount,
) {
  if (amount <= 0) return QuestActionResult.ok(save);
  if (skillId == combatSkillId) {
    return const QuestActionResult.failed('Pick a skill other than Combat.');
  }
  if (db.skills.every((skill) => skill.skillId != skillId)) {
    return const QuestActionResult.failed('Unknown skill.');
  }
  return QuestActionResult.ok(applyXp(save, db, skillId, amount).save);
}

/// Pays a quest bribe: gold out, a stolen purse in, and the bribe flag.
QuestActionResult bribeQuestNpc(GameDatabase db, PlayerSave save, String questId) {
  final quest = getQuest(db, questId);
  if (quest == null) return const QuestActionResult.failed('Quest not found.');
  final parsed = parseStructuredObjectives(quest);
  if (getQuestProgress(save, questId).status != 'active') {
    return const QuestActionResult.failed('This quest is not active.');
  }
  if (hasQuestFlag(save, questId, 'choice:bribe') || hasQuestFlag(save, questId, 'choice:combat')) {
    return const QuestActionResult.failed('You already chose how to handle this.');
  }
  if (parsed.bribeGold <= 0) return const QuestActionResult.failed('This quest has no bribe.');
  if (save.gold < parsed.bribeGold) {
    return QuestActionResult.failed('Need ${jsLocaleNumber(parsed.bribeGold)} gold.');
  }
  var next = save.copyWith(gold: save.gold - parsed.bribeGold);
  next = setQuestFlag(next, questId, 'choice:bribe');
  if (parsed.delivers.isNotEmpty) {
    final purse = parsed.delivers.first;
    next = addItemToInventory(next, purse.targetId, purse.quantity);
  }
  return QuestActionResult.ok(next);
}

QuestActionResult chooseQuestCombatRoute(PlayerSave save, String questId) {
  if (getQuestProgress(save, questId).status != 'active') {
    return const QuestActionResult.failed('This quest is not active.');
  }
  if (hasQuestFlag(save, questId, 'choice:bribe') || hasQuestFlag(save, questId, 'choice:combat')) {
    return const QuestActionResult.failed('You already chose how to handle this.');
  }
  return QuestActionResult.ok(setQuestFlag(save, questId, 'choice:combat'));
}

String questStatusLabel(String status) {
  if (status == 'completed') return 'Completed';
  if (status == 'active') return 'Active';
  return 'Not started';
}
