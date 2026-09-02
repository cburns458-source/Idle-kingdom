import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/requirements.dart';
import '../activity/reward_summary.dart';
import '../activity/rewards.dart';
import '../activity/types.dart';
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
import 'miniquests.dart';
import 'objectives.dart';
import 'progress.dart';
import 'steps.dart';

/// Set when the player pays AcceptGold without starting the quest yet.
const String acceptGoldFlag = 'accept-gold';

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
  final notes = quest['Notes'] is String ? quest['Notes']! as String : '';
  return RegExp(r'(?:^|;)\s*Repeatable:\s*\d+\s*d', caseSensitive: false).hasMatch(notes);
}

/// Either the updated save or the reason the change was refused.
class QuestActionResult {
  const QuestActionResult.ok(this.save) : reason = null;

  const QuestActionResult.failed(this.reason) : save = null;

  bool get ok => reason == null;
  final PlayerSave? save;
  final String? reason;
}

List<QuestRow> questsTouchingNpc(GameDatabase db, PlayerSave save, String npcId) {
  return asQuestRows(db).where((quest) => questTouchesNpcForSave(db, save, quest, npcId)).toList();
}

bool questAvailableForSave(GameDatabase db, PlayerSave save, QuestRow quest) {
  final notes = quest['Notes'] is String ? quest['Notes']! as String : null;
  if (!meetsTotalLevelRequirement(save, notes)) return false;
  final parsed = parseStructuredObjectives(quest);
  for (final requirement in parsed.requiresSkills) {
    if (getSkillProgress(save, requirement.targetId).level < requirement.quantity) {
      return false;
    }
  }
  for (final requiredQuestId in parsed.requiresQuestIds) {
    if (getQuestProgress(save, requiredQuestId).status != 'completed') return false;
  }
  return true;
}

QuestActionResult acceptQuest(
  GameDatabase db,
  PlayerSave save,
  String questId, {
  bool ignoreLocation = false,
}) {
  final quest = getQuest(db, questId);
  if (quest == null) return const QuestActionResult.failed('Quest not found.');
  if (isMiniquest(quest)) {
    return const QuestActionResult.failed('Speak with Vesper to change race.');
  }
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
  if (progress.status == 'completed') {
    return const QuestActionResult.failed('This quest is already completed.');
  }
  if (parsed.acceptGoldCost > 0 && !hasQuestFlag(save, questId, acceptGoldFlag)) {
    return QuestActionResult.failed(
      'Donate ${jsLocaleNumber(parsed.acceptGoldCost)} gold before starting this quest.',
    );
  }
  if (!questAvailableForSave(db, save, quest)) {
    return const QuestActionResult.failed('You are not ready for this quest yet.');
  }

  var unlocked = save.unlockedLocationIds;
  for (final locationId in parsed.unlockOnAcceptLocationIds) {
    unlocked = unlockLocation(unlocked, locationId);
  }
  return QuestActionResult.ok(
    save.copyWith(
      quests: [
        ...save.quests.where((row) => row.questId != questId),
        QuestProgress(
          questId: questId,
          status: 'active',
          progress: 0,
          counters: getQuestProgress(save, questId).counters,
        ),
      ],
      unlockedLocationIds: unlocked,
    ),
  );
}

/// Pays AcceptGold and remembers it. Does not start the quest.
QuestActionResult donateForQuest(
  GameDatabase db,
  PlayerSave save,
  String questId, {
  bool ignoreLocation = false,
}) {
  final quest = getQuest(db, questId);
  if (quest == null) return const QuestActionResult.failed('Quest not found.');
  final parsed = parseStructuredObjectives(quest);
  if (parsed.acceptGoldCost <= 0) {
    return const QuestActionResult.failed('This quest does not ask for gold.');
  }
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
  if (progress.status == 'completed') {
    return const QuestActionResult.failed('This quest is already completed.');
  }
  if (hasQuestFlag(save, questId, acceptGoldFlag)) {
    return const QuestActionResult.failed('You already donated.');
  }
  if (save.gold < parsed.acceptGoldCost) {
    return QuestActionResult.failed(
      'Need ${jsLocaleNumber(parsed.acceptGoldCost)} gold to donate.',
    );
  }

  final next = recordQuestFlag(
    save.copyWith(gold: save.gold - parsed.acceptGoldCost),
    questId,
    acceptGoldFlag,
  );
  return QuestActionResult.ok(next);
}

class QuestCompletion {
  const QuestCompletion.ok({
    required this.save,
    required this.message,
    required this.questName,
    required this.rewards,
    this.pendingSkillXp = 0,
    this.rewardBundle,
  }) : reason = null;

  const QuestCompletion.failed(this.reason)
    : save = null,
      message = null,
      questName = null,
      rewards = const <String>[],
      pendingSkillXp = 0,
      rewardBundle = null;

  bool get ok => reason == null;
  final PlayerSave? save;
  final String? message;
  final String? questName;

  /// Reward lines shown on turn-in, in the order they were granted.
  final List<String> rewards;

  /// Bribe-route XP the player still has to assign to a non-combat skill.
  final num pendingSkillXp;
  final ActionRewardBundle? rewardBundle;
  final String? reason;
}

String _skillName(GameDatabase db, String skillId) {
  final displayName = db.skills
      .firstWhereOrNull((skill) => skill.raw['Skill ID'] == skillId)
      ?.raw['Display Name'];
  return displayName is String ? displayName : 'skill';
}

final RegExp _objectiveVerb = RegExp(r'^(Deliver|Defeat|Craft|Learn)\s+', caseSensitive: false);

QuestCompletion completeQuest(
  GameDatabase db,
  PlayerSave save,
  String questId, {
  bool ignoreLocation = false,
}) {
  final quest = getQuest(db, questId);
  if (quest == null) return const QuestCompletion.failed('Quest not found.');
  final parsed = parseStructuredObjectives(quest);
  final npcId = parsed.turnInNpcId ?? quest['NPC ID'];
  final npc = db.npcs.firstWhereOrNull((row) => row.raw['NPC ID'] == npcId);
  if (!ignoreLocation && (npc == null || npc.raw['Location ID'] != save.currentLocationId)) {
    return const QuestCompletion.failed('Return to the quest giver to turn this in.');
  }

  final progress = getQuestProgress(save, questId);
  if (progress.status == 'completed') {
    return const QuestCompletion.failed('This quest is already completed.');
  }
  if (progress.status != 'active') {
    return const QuestCompletion.failed('Accept this quest before turning it in.');
  }

  final stepDelivers = questAllStepDelivers(db, quest);
  final hasObjectives =
      stepDelivers.isNotEmpty ||
      parsed.delivers.isNotEmpty ||
      parsed.defeatTargets.isNotEmpty ||
      parsed.processTargets.isNotEmpty ||
      parsed.learnRecipeIds.isNotEmpty ||
      parsed.talkNpcIds.isNotEmpty ||
      parsed.visitLocationIds.isNotEmpty ||
      parsed.inspectIds.isNotEmpty ||
      parsed.goldCost > 0 ||
      questUsesSteps(db, questId);
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
  final deliverItems = questUsesSteps(db, questId) ? stepDelivers : parsed.delivers;
  if (deliverItems.isNotEmpty) {
    final removed = removeIngredients(
      next,
      deliverItems
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
  final xpRewards = <ActionXpRewardSummary>[];
  final loot = <LootGrant>[];
  var goldGained = 0.0;
  num pendingSkillXp = 0;
  final bribed = hasQuestFlag(save, questId, 'choice:bribe');
  final xpGrants = parsed.rewardXp.isNotEmpty
      ? parsed.rewardXp
      : (quest['Reward XP Skill ID'] is String &&
            (quest['Reward XP Skill ID'] as String).isNotEmpty &&
            quest['Reward XP Amount'] is num)
      ? <QuestCounterTarget>[
          QuestCounterTarget(
            targetId: quest['Reward XP Skill ID']! as String,
            quantity: quest['Reward XP Amount']! as num,
          ),
        ]
      : const <QuestCounterTarget>[];
  if (bribed && parsed.branchSkillXp > 0) {
    pendingSkillXp = parsed.branchSkillXp;
    rewards.add('Choose ${jsLocaleNumber(pendingSkillXp)} XP in a non-combat skill');
  } else {
    for (final grant in xpGrants) {
      if (grant.quantity <= 0) continue;
      final applied = applyXp(next, db, grant.targetId, grant.quantity);
      next = applied.save;
      rewards.add('${jsLocaleNumber(grant.quantity)} ${_skillName(db, grant.targetId)} XP');
      final xpLine = summarizeXpReward(
        db,
        next,
        grant.targetId,
        grant.quantity,
        applied.leveledUpTo,
      );
      if (xpLine != null) xpRewards.add(xpLine);
    }
  }

  if (parsed.rewardGold > 0) {
    goldGained = parsed.rewardGold.toDouble();
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
    final displayName = itemName is String ? itemName : 'item';
    rewards.add('${jsNumberToString(rewardQty)}× $displayName');
    loot.add(LootGrant(itemId: rewardItemId, quantity: rewardQty, displayName: displayName));
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

  rewards.addAll(facilityUnlockRewardLabels(db, questId));

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
    rewardBundle: ActionRewardBundle(
      id: 'quest-$questId',
      xpRewards: xpRewards,
      loot: loot,
      goldGained: goldGained,
    ),
    message: rewards.isNotEmpty ? 'Thank you — ${rewards.join(' and ')}.' : 'Thank you.',
  );
}

class QuestArrivalCompletion {
  const QuestArrivalCompletion({
    required this.questId,
    required this.questName,
    required this.rewards,
    required this.pendingSkillXp,
    required this.message,
    this.rewardBundle,
  });

  final String questId;
  final String questName;
  final List<String> rewards;
  final num pendingSkillXp;
  final ActionRewardBundle? rewardBundle;
  final String message;

  Map<String, Object?> toJson() => <String, Object?>{
    'questId': questId,
    'questName': questName,
    'rewards': rewards,
    'pendingSkillXp': pendingSkillXp,
    'rewardBundle': rewardBundle?.toJson(),
    'message': message,
  };
}

class QuestVisitAutoComplete {
  const QuestVisitAutoComplete({required this.save, required this.completions});

  final PlayerSave save;
  final List<QuestArrivalCompletion> completions;
}

QuestVisitAutoComplete applyQuestAutoCompleteOnVisit(GameDatabase db, PlayerSave save) {
  var next = save;
  final completions = <QuestArrivalCompletion>[];
  for (final quest in asQuestRows(db)) {
    final parsed = parseStructuredObjectives(quest);
    if (!parsed.autoCompleteOnVisit) continue;
    final questId = jsString(quest['Quest ID']);
    if (getQuestProgress(next, questId).status != 'active') continue;
    if (!questAllStepsComplete(db, next, quest)) continue;
    final completed = completeQuest(db, next, questId, ignoreLocation: true);
    if (completed.ok) {
      next = completed.save!;
      completions.add(
        QuestArrivalCompletion(
          questId: questId,
          questName: completed.questName!,
          rewards: completed.rewards,
          pendingSkillXp: completed.pendingSkillXp,
          rewardBundle: completed.rewardBundle,
          message: completed.message!,
        ),
      );
    }
  }
  return QuestVisitAutoComplete(save: next, completions: completions);
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

/// Facilities gated by `Quest Complete` on [questId], listed when that quest finishes.
List<String> facilityUnlockRewardLabels(GameDatabase db, String questId) {
  final labels = <String>[];
  for (final facility in db.facilities) {
    final facilityId = jsString(facility.raw['Facility ID']);
    final gated = requirementsForEntity(db, 'Facility', facilityId).any((requirement) {
      if (requirement.requirementType != 'Quest Complete') return false;
      final reference = requirement.referenceIdValue;
      return reference is String && reference == questId;
    });
    if (!gated) continue;
    final name = facility.raw['Display Name'];
    labels.add('Unlocked ${name is String && name.isNotEmpty ? name : facilityId}');
  }
  return labels;
}
