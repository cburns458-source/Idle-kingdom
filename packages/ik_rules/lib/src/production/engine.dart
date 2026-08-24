import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/reward_summary.dart';
import '../activity/rewards.dart';
import '../activity/types.dart';
import '../achievements/progress.dart';
import '../activity/xp.dart';
import '../bounties/progress.dart';
import '../inventory/add_items.dart';
import '../inventory/capacity.dart';
import '../js_compat.dart';
import '../equipment/specialist.dart';
import '../potions/effects.dart';
import '../quests/progress.dart';
import '../recipes/knowledge.dart';
import '../rng/mulberry32.dart';
import '../save/generated/save_models.dart';
import '../time.dart';
import 'inventory.dart';
import 'recipes.dart';

PlayerSave clearProductionSave(PlayerSave save) {
  return clearActivePotionEffect(
    save.copyWith(
      productionRecipeId: null,
      productionQuantityTotal: null,
      productionQuantityRemaining: null,
      currentActionId: null,
      actionStartedAt: null,
      actionDurationMs: null,
    ),
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
    return const ProductionQueueResult.failed('You have not learned that recipe yet.');
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
  if (crafts > maxCraftsFromMaterials(save, recipe)) {
    return const ProductionQueueResult.failed('Missing required materials for that quantity.');
  }

  // Reserve/consume materials for the full queue up front so they cannot be spent elsewhere.
  final withMaterials = removeIngredients(save, recipeIngredients(recipe), crafts);
  if (withMaterials == null) {
    return const ProductionQueueResult.failed('Missing required materials.');
  }

  final outputTotal = jsNumber(recipe.raw['Output Quantity']) * crafts;
  if (!canFitItemQuantity(withMaterials, jsString(recipe.raw['Output Item ID']), outputTotal)) {
    return const ProductionQueueResult.failed(
      'Not enough inventory space for that queue (180 slots, stacks to max).',
    );
  }

  final startedAt = isoFromMs(nowMs);
  final baseDurationMs = jsNumber(recipe.raw['Base Duration Seconds']) * 1000;
  final potion = tryConsumePotionForScope(db, withMaterials, 'one_standard_production_action');
  return ProductionQueueResult.ok(
    potion.save.copyWith(
      currentActivityId: activityId,
      activityStartedAt: potion.save.activityStartedAt ?? startedAt,
      productionRecipeId: recipeId,
      productionQuantityTotal: crafts,
      productionQuantityRemaining: crafts,
      currentActionId: recipe.raw['Action ID'] as String?,
      actionStartedAt: startedAt,
      actionDurationMs: applyPotionDurationMs(baseDurationMs, potion.effect),
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
    required this.reward,
  });

  final PlayerSave save;
  final bool finishedQueue;
  final num xpGained;
  final String outputName;
  final num outputQty;
  final ActionRewardBundle reward;
}

ProductionCraftResult? completeProductionCraft(
  GameDatabase db,
  PlayerSave save,
  num nowMs, [
  RandomFn random = _noChefProc,
]) {
  final recipeId = save.productionRecipeId;
  final remainingBefore = save.productionQuantityRemaining ?? 0;
  if (isBlank(recipeId) || remainingBefore == 0) return null;
  final recipe = getRecipe(db, recipeId!);
  if (recipe == null) return null;

  final baseQty = jsNumber(recipe.raw['Output Quantity']);
  var outputQty = chefHatOutputQuantity(baseQty, save, jsString(recipe.raw['Skill ID']), random);
  final outputItemId = jsString(recipe.raw['Output Item ID']);
  if (outputQty > baseQty && !canFitItemQuantity(save, outputItemId, outputQty)) {
    outputQty = baseQty;
  }
  final granted = addItemToInventoryExact(save, outputItemId, outputQty);
  if (!granted.ok) return null;
  var next = granted.save!;

  final skillId = jsString(recipe.raw['Skill ID']);
  final xpGained = jsNumber(recipe.raw['XP Reward']);
  final xpApplied = applyXp(next, db, skillId, xpGained);
  next = xpApplied.save;

  final remaining = remainingBefore - 1;
  next = applyQuestProcessProgress(db, next, jsString(recipe.raw['Recipe ID']), 1);
  next = applyBountyProcessProgress(next, jsString(recipe.raw['Recipe ID']), 1, nowMs);
  next = recordProductionMilestones(db, next, outputItemId, outputQty);

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

  if (remaining <= 0) {
    return ProductionCraftResult(
      save: clearProductionSave(next.copyWith(currentActivityId: null, activityStartedAt: null)),
      finishedQueue: true,
      xpGained: xpGained,
      outputName: outputName,
      outputQty: outputQty,
      reward: reward,
    );
  }

  final cleared = clearActivePotionEffect(next.copyWith(productionQuantityRemaining: remaining));
  final potion = tryConsumePotionForScope(db, cleared, 'one_standard_production_action');
  final baseDurationMs = jsNumber(recipe.raw['Base Duration Seconds']) * 1000;
  return ProductionCraftResult(
    save: potion.save.copyWith(
      productionQuantityRemaining: remaining,
      currentActionId: recipe.raw['Action ID'] as String?,
      actionStartedAt: isoFromMs(nowMs),
      actionDurationMs: applyPotionDurationMs(baseDurationMs, potion.effect),
    ),
    finishedQueue: false,
    xpGained: xpGained,
    outputName: outputName,
    outputQty: outputQty,
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
  _CraftTotal(this.qty, this.xp);

  num qty;
  num xp;
}

double _noChefProc() => 1;

/// Advances a production queue by elapsed offline/online time.
ProductionProgressResult resolveProductionProgress(
  GameDatabase db,
  PlayerSave save,
  num nowMs, [
  RandomFn random = _noChefProc,
]) {
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
      craftTotals[completed.outputName] = _CraftTotal(completed.outputQty, completed.xpGained);
    } else {
      existing.qty += completed.outputQty;
      existing.xp += completed.xpGained;
    }
    if (completed.finishedQueue) break;
  }

  return ProductionProgressResult(
    save: current,
    craftsCompleted: craftsCompleted,
    messages: craftTotals.entries
        .map(
          (entry) =>
              'Crafted ${jsNumberToString(entry.value.qty)} ${entry.key} '
              '(+${jsNumberToString(entry.value.xp)} XP)',
        )
        .toList(),
    activityMs: activityMs,
    blockedByInventory: blockedByInventory,
  );
}
