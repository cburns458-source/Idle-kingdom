import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/requirements.dart';
import '../activity/reward_summary.dart';
import '../activity/rewards.dart';
import '../activity/types.dart';
import '../achievements/progress.dart';
import '../activity/gathering.dart';
import '../activity/xp.dart';
import '../bounties/progress.dart';
import '../inventory/add_items.dart';
import '../inventory/capacity.dart';
import '../js_compat.dart';
import '../equipment/specialist.dart';
import '../equipment/loadout.dart';
import '../potions/effects.dart';
import '../quests/progress.dart';
import '../recipes/knowledge.dart';
import '../rng/mulberry32.dart';
import '../spells/spells.dart';
import '../trackers/trackers.dart';
import '../save/generated/save_models.dart';
import '../time.dart';
import '../tutorial/tutorial.dart';
import 'inventory.dart';
import 'recipes.dart';

num productionCraftDurationMs(
  GameDatabase db,
  PlayerSave save,
  RecipeRow recipe,
  ActivePotionEffect? potionEffect,
) {
  final baseDurationMs = jsNumber(recipe.raw['Base Duration Seconds']) * 1000;
  final reduced = baseDurationMs * activeSpellProductionDurationMultiplier(db, save);
  return applyPotionDurationMs(reduced, potionEffect, db, jsString(recipe.raw['Skill ID']));
}

PotionConsumption _consumeProductionPotion(GameDatabase db, PlayerSave save, String skillId) {
  final existing = save.activePotionEffect;
  if (existing != null && potionActionsRemaining(existing) > 0) {
    if (!potionAppliesToProductionSkill(db, existing.itemId, skillId)) {
      return PotionConsumption(save: save, consumed: false, effect: null, potionName: null);
    }
  } else {
    final equipped = slotStack(save, potionSlotId);
    if (equipped != null && !potionAppliesToProductionSkill(db, equipped.itemId, skillId)) {
      return PotionConsumption(save: save, consumed: false, effect: null, potionName: null);
    }
  }
  return tryConsumePotionForScope(db, save, 'one_standard_production_action');
}

PlayerSave _tickProductionPotion(GameDatabase db, PlayerSave save, String skillId) {
  final effect = save.activePotionEffect;
  if (effect != null && !potionAppliesToProductionSkill(db, effect.itemId, skillId)) return save;
  return tickPotionAction(save);
}

PlayerSave clearProductionSave(PlayerSave save) {
  return save.copyWith(
    productionRecipeId: null,
    productionQuantityTotal: null,
    productionQuantityRemaining: null,
    currentActionId: null,
    actionStartedAt: null,
    actionDurationMs: null,
  );
}

/// Stops production and refunds materials for crafts still remaining in the queue.
PlayerSave cancelProductionActivity(GameDatabase db, PlayerSave save) {
  var next = save;
  final remaining = save.productionQuantityRemaining ?? 0;
  if (isNotBlank(save.productionRecipeId) && remaining > 0) {
    final recipe = getRecipe(db, save.productionRecipeId!);
    if (recipe != null) {
      for (final ingredient in recipeIngredients(recipe)) {
        if (isAmbientIngredientAt(db, save, ingredient.itemId)) continue;
        next = addItemToInventory(next, ingredient.itemId, ingredient.quantity * remaining);
      }
    }
  }
  return clearProductionSave(next.copyWith(currentActivityId: null, activityStartedAt: null));
}

/// Either the queued save or the reason the queue was refused.
class ProductionQueueResult {
  const ProductionQueueResult.ok(this.save) : reason = null;

  const ProductionQueueResult.failed(this.reason) : save = null;

  bool get ok => reason == null;
  final PlayerSave? save;
  final String? reason;
}

ProductionQueueResult beginProductionQueue(
  GameDatabase db,
  PlayerSave save,
  String activityId,
  String recipeId,
  num quantity,
  num nowMs,
) {
  final recipe = getRecipe(db, recipeId);
  if (recipe == null || !isCompleteRecipe(recipe)) {
    return const ProductionQueueResult.failed('That recipe is not available.');
  }
  if (!canKnowRecipe(save, db, recipe)) {
    if (!knowsRecipe(save, db, recipeId)) {
      return const ProductionQueueResult.failed('You have not learned that recipe yet.');
    }
    final unmet = unmetHardRequirements(db, save, requirementsForEntity(db, 'Recipe', recipeId));
    return ProductionQueueResult.failed(unmet.isEmpty ? 'You cannot make that yet.' : unmet.first);
  }
  if (!recipeMatchesFacility(
    jsString(recipe.raw['Facility ID']),
    facilityIdForActivity(db, activityId) ?? '',
  )) {
    return const ProductionQueueResult.failed('That recipe cannot be made at this station.');
  }

  final crafts = quantity.floor();
  if (crafts <= 0) {
    return const ProductionQueueResult.failed('Choose a quantity of at least 1.');
  }
  if (crafts > maxCraftsFromQueueCap(db, recipe)) {
    return const ProductionQueueResult.failed('That queue exceeds the 24-hour production cap.');
  }
  if (crafts > maxCraftsFromMaterials(db, save, recipe)) {
    return const ProductionQueueResult.failed('Missing required materials for that quantity.');
  }

  // Reserve/consume materials for the full queue up front so they cannot be spent elsewhere.
  final withMaterials = removeIngredients(db, save, recipeIngredients(recipe), crafts);
  if (withMaterials == null) {
    return const ProductionQueueResult.failed('Missing required materials.');
  }

  final outputItemId = jsString(recipe.raw['Output Item ID']);
  final outputTotal =
      productionOutputReservePerCraft(
        db,
        jsString(recipe.raw['Skill ID']),
        jsNumber(recipe.raw['Output Quantity']),
        outputItemId,
      ) *
      crafts;
  if (!canFitItemQuantity(withMaterials, outputItemId, outputTotal)) {
    return ProductionQueueResult.failed(
      'Not enough inventory space for that queue ($inventorySlotLimit slots, stacks to max).',
    );
  }

  final startedAt = isoFromMs(nowMs);
  final skillId = jsString(recipe.raw['Skill ID']);
  final potion = _consumeProductionPotion(db, withMaterials, skillId);
  return ProductionQueueResult.ok(
    potion.save.copyWith(
      currentActivityId: activityId,
      activityStartedAt: potion.save.activityStartedAt ?? startedAt,
      productionRecipeId: recipeId,
      productionQuantityTotal: crafts,
      productionQuantityRemaining: crafts,
      currentActionId: recipe.raw['Action ID'] as String?,
      actionStartedAt: startedAt,
      actionDurationMs: productionCraftDurationMs(db, potion.save, recipe, potion.effect),
    ),
  );
}

/// One finished craft, with the same reward shape the gathering panels use.
class ProductionCraftResult {
  const ProductionCraftResult({
    required this.save,
    required this.finishedQueue,
    required this.xpGained,
    required this.outputName,
    required this.outputQty,
    required this.failed,
    required this.reward,
  });

  final PlayerSave save;
  final bool finishedQueue;
  final num xpGained;
  final String outputName;
  final num outputQty;

  /// True when the craft was botched: the materials are gone, nothing came back.
  final bool failed;
  final ActionRewardBundle reward;
}

ProductionCraftResult? completeProductionCraft(
  GameDatabase db,
  PlayerSave save,
  num nowMs,
  RandomFn random,
) {
  final recipeId = save.productionRecipeId;
  final remainingBefore = save.productionQuantityRemaining ?? 0;
  if (isBlank(recipeId) || remainingBefore == 0) return null;
  final recipe = getRecipe(db, recipeId!);
  if (recipe == null) return null;

  final skillId = jsString(recipe.raw['Skill ID']);
  final outputItemId = jsString(recipe.raw['Output Item ID']);
  // The materials left the bag when the queue was placed, so a botched craft
  // costs them: rolling before the output means a full bag cannot save them.
  final craftLevel = getSkillProgress(save, skillId).level;
  final successBonus = equippedSuccessChanceBonusPercent(db, save, skillId);
  final recipeId = jsString(recipe.raw['Recipe ID']);
  final tutorialCook = shouldGuaranteeTutorialCook(save, recipeId);
  if (!tutorialCook &&
      !rollProductionSuccess(
        craftLevel,
        random,
        jsNumber(recipe.raw['Proficiency Level']),
        successBonus,
      )) {
    final ruinedName = db.items
        .firstWhereOrNull((item) => item.raw['Item ID'] == outputItemId)
        ?.raw['Display Name'];
    return _finishProductionCraft(
      db,
      save,
      recipe,
      nowMs,
      next: save,
      outputName: ruinedName is String ? ruinedName : jsString(recipe.raw['Display Name']),
      outputQty: 0,
      xpGained: 0,
      failed: true,
      reward: ActionRewardBundle(
        id:
            'craft-${recipe.raw['Recipe ID']}-${jsNumberToString(nowMs)}-'
            '${jsNumberToString(remainingBefore - 1)}',
        xpRewards: const <ActionXpRewardSummary>[],
        loot: const <LootGrant>[],
        goldGained: 0,
      ),
    );
  }

  final baseQty = jsNumber(recipe.raw['Output Quantity']);
  final usesPotionDie = skillId == alchemySkillId && alchemyRecipeUsesPotionDie(db, outputItemId);
  var outputQty = usesPotionDie
      ? alchemyPotionOutputQuantity(db, baseQty, save, skillId, random)
      : chefHatOutputQuantity(db, baseQty, save, skillId, random);
  if (outputQty > baseQty && !canFitItemQuantity(save, outputItemId, outputQty)) {
    if (usesPotionDie) {
      outputQty = math.min(outputQty, maxAddableQuantity(save, outputItemId));
      if (outputQty <= 0) return null;
    } else {
      outputQty = baseQty;
    }
  }
  final granted = addItemToInventoryExact(save, outputItemId, outputQty);
  if (!granted.ok) return null;
  var next = granted.save!;
  if (tutorialCook) next = noteTutorialGuaranteedCook(next, recipeId);

  final xpGained = jsNumber(recipe.raw['XP Reward']);
  final xpApplied = applyXp(next, db, skillId, xpGained);
  next = xpApplied.save;

  final remaining = remainingBefore - 1;
  next = applyQuestProcessProgress(db, next, jsString(recipe.raw['Recipe ID']), 1);
  next = applyBountyProcessProgress(next, jsString(recipe.raw['Recipe ID']), 1, nowMs);
  next = recordProductionMilestones(db, next, outputItemId, outputQty);
  next = creditXpAwards(next, [(skillId: skillId, xp: xpGained)], nowMs);

  final itemName = db.items
      .firstWhereOrNull((item) => item.raw['Item ID'] == outputItemId)
      ?.raw['Display Name'];
  final outputName = itemName is String ? itemName : jsString(recipe.raw['Display Name']);
  final xpReward = summarizeXpReward(db, next, skillId, xpGained, xpApplied.leveledUpTo);
  final reward = ActionRewardBundle(
    id: 'craft-${recipe.raw['Recipe ID']}-${jsNumberToString(nowMs)}-${jsNumberToString(remaining)}',
    xpRewards: xpReward == null
        ? const <ActionXpRewardSummary>[]
        : <ActionXpRewardSummary>[xpReward],
    loot: <LootGrant>[
      LootGrant(itemId: outputItemId, quantity: outputQty, displayName: outputName),
    ],
    goldGained: 0,
  );

  return _finishProductionCraft(
    db,
    save,
    recipe,
    nowMs,
    next: next,
    outputName: outputName,
    outputQty: outputQty,
    xpGained: xpGained,
    failed: false,
    reward: reward,
  );
}

/// Closes one craft off: ends the queue or starts the next craft's timer.
///
/// Shared by the craft that worked and the craft that was botched, so a failure
/// moves the queue along exactly as a success does — it just brings nothing back.
ProductionCraftResult _finishProductionCraft(
  GameDatabase db,
  PlayerSave save,
  RecipeRow recipe,
  num nowMs, {
  required PlayerSave next,
  required String outputName,
  required num outputQty,
  required num xpGained,
  required bool failed,
  required ActionRewardBundle reward,
}) {
  final remaining = (save.productionQuantityRemaining ?? 1) - 1;
  final skillId = jsString(recipe.raw['Skill ID']);
  if (remaining <= 0) {
    return ProductionCraftResult(
      save: clearProductionSave(
        _tickProductionPotion(
          db,
          next.copyWith(currentActivityId: null, activityStartedAt: null),
          skillId,
        ),
      ),
      finishedQueue: true,
      xpGained: xpGained,
      outputName: outputName,
      outputQty: outputQty,
      failed: failed,
      reward: reward,
    );
  }

  final ticked = _tickProductionPotion(
    db,
    next.copyWith(productionQuantityRemaining: remaining),
    skillId,
  );
  final potion = _consumeProductionPotion(db, ticked, skillId);
  return ProductionCraftResult(
    save: potion.save.copyWith(
      productionQuantityRemaining: remaining,
      currentActionId: recipe.raw['Action ID'] as String?,
      actionStartedAt: isoFromMs(nowMs),
      actionDurationMs: productionCraftDurationMs(db, potion.save, recipe, potion.effect),
    ),
    finishedQueue: false,
    xpGained: xpGained,
    outputName: outputName,
    outputQty: outputQty,
    failed: failed,
    reward: reward,
  );
}

class ProductionProgressResult {
  const ProductionProgressResult({
    required this.save,
    required this.craftsCompleted,
    required this.messages,
    required this.activityMs,
    this.blockedByInventory = false,
  });

  final PlayerSave save;
  final num craftsCompleted;
  final List<String> messages;
  final num activityMs;
  final bool blockedByInventory;

  Map<String, Object?> toJson() => <String, Object?>{
    'save': save.toJson(),
    'craftsCompleted': craftsCompleted,
    'messages': messages,
    'activityMs': activityMs,
  };
}

class _CraftTotal {
  _CraftTotal(this.qty, this.xp, this.ruined);

  num qty;
  num xp;
  num ruined;
}

/// Advances a production queue by elapsed offline/online time.
ProductionProgressResult resolveProductionProgress(
  GameDatabase db,
  PlayerSave save,
  num nowMs,
  RandomFn random,
) {
  var current = save;
  num craftsCompleted = 0;
  num activityMs = 0;
  var blockedByInventory = false;
  // Aggregate identical outputs so AFK summaries show one line per item.
  final craftTotals = <String, _CraftTotal>{};

  while (isNotBlank(current.productionRecipeId) &&
      (current.productionQuantityRemaining ?? 0) != 0 &&
      isNotBlank(current.actionStartedAt) &&
      (current.actionDurationMs ?? 0) != 0) {
    final durationMs = current.actionDurationMs!;
    final due = jsDateParse(current.actionStartedAt) + durationMs;
    if (due > nowMs) break;
    final completed = completeProductionCraft(db, current, due, random);
    if (completed == null) {
      blockedByInventory = true;
      break;
    }
    current = completed.save;
    craftsCompleted += 1;
    activityMs += durationMs;
    final existing = craftTotals[completed.outputName];
    if (existing == null) {
      craftTotals[completed.outputName] = _CraftTotal(
        completed.outputQty,
        completed.xpGained,
        completed.failed ? 1 : 0,
      );
    } else {
      existing.qty += completed.outputQty;
      existing.xp += completed.xpGained;
      if (completed.failed) existing.ruined += 1;
    }
    if (completed.finishedQueue) break;
  }

  return ProductionProgressResult(
    save: current,
    craftsCompleted: craftsCompleted,
    messages: craftTotals.entries.expand((entry) {
      final lines = <String>[];
      if (entry.value.qty > 0) {
        lines.add(
          'Crafted ${jsNumberToString(entry.value.qty)} ${entry.key} '
          '(+${jsNumberToString(entry.value.xp)} XP)',
        );
      }
      if (entry.value.ruined > 0) {
        lines.add('Ruined ${jsNumberToString(entry.value.ruined)} ${entry.key}');
      }
      return lines;
    }).toList(),
    activityMs: activityMs,
    blockedByInventory: blockedByInventory,
  );
}
