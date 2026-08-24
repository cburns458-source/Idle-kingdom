import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../achievements/progress.dart';
import '../activity/xp.dart';
import '../bounties/progress.dart';
import '../inventory/add_items.dart';
import '../js_compat.dart';
import '../npcs/knowledge.dart';
import '../production/inventory.dart';
import '../production/recipes.dart';
import '../quests/progress.dart';
import '../races/races.dart';
import '../save/generated/save_models.dart';
import 'enchantments.dart';
import 'projects.dart';

/// Either a green light or the reason a project cannot be completed.
class ProjectValidation {
  const ProjectValidation.ok() : reason = null;

  const ProjectValidation.failed(this.reason);

  bool get ok => reason == null;
  final String? reason;
}

class ProjectCompleteResult {
  const ProjectCompleteResult.ok({
    required this.save,
    required this.outputLabel,
    required this.outputQty,
    required this.xpGained,
    required this.goldSpent,
  }) : reason = null;

  const ProjectCompleteResult.failed(this.reason)
    : save = null,
      outputLabel = null,
      outputQty = 0,
      xpGained = 0,
      goldSpent = 0;

  bool get ok => reason == null;
  final PlayerSave? save;
  final String? outputLabel;
  final num outputQty;
  final num xpGained;
  final num goldSpent;
  final String? reason;
}

ProjectValidation validateProjectCompletion(
  GameDatabase db,
  PlayerSave save,
  String projectId,
  num quantity, [
  String? enchantTargetId,
]) {
  final project = getProject(db, projectId);
  if (project == null || !isCompleteProject(project)) {
    return const ProjectValidation.failed('That project is not available.');
  }

  final atLocation = db.facilities.any(
    (row) =>
        row.raw['Location ID'] == save.currentLocationId &&
        projectFacilityIdForLookup(jsString(row.raw['Facility ID'])) == project.raw['Facility ID'],
  );
  if (!atLocation) {
    return const ProjectValidation.failed('Travel to the required facility first.');
  }

  if (!meetsProjectKnowledge(db, save, project)) {
    final knowledge = hasProjectKnowledge(db, save, jsString(project.raw['Skill ID']));
    if (!knowledge.ok) {
      return ProjectValidation.failed(
        'Speak with the ${knowledge.npcName} to unlock these projects.',
      );
    }
  }

  if (!meetsProjectSkills(save, project)) {
    final missing = projectSkillRequirements(project).firstWhereOrNull(
      (requirement) => getSkillProgress(save, requirement.skillId).level < requirement.level,
    );
    if (missing == null) {
      return const ProjectValidation.failed('Skill requirements are not met.');
    }
    final displayName = db.skills
        .firstWhereOrNull((skill) => skill.raw['Skill ID'] == missing.skillId)
        ?.raw['Display Name'];
    final skillName = displayName is String ? displayName : missing.skillId;
    return ProjectValidation.failed(
      'Requires $skillName level ${jsNumberToString(missing.level)}.',
    );
  }

  final crafts = quantity.floor();
  if (crafts <= 0) return const ProjectValidation.failed('Choose a quantity of at least 1.');
  if (crafts > maxProjectQuantity(save, project)) {
    return const ProjectValidation.failed('Missing materials or gold for that quantity.');
  }

  final outputId = jsString(project.raw['Output Item / Target ID']);
  if (isEnchantmentOutput(outputId)) {
    final enchantment = getEnchantment(db, outputId);
    if (enchantment == null || enchantment.raw['Status'] == 'Needs Data') {
      return const ProjectValidation.failed('That enchantment is not ready yet.');
    }
    if (crafts != 1) {
      return const ProjectValidation.failed('Enchantment projects complete one at a time.');
    }
    final targets = eligibleEnchantmentTargets(db, save, enchantment);
    if (targets.isEmpty) {
      return const ProjectValidation.failed(
        'Select a valid equipped or inventory item to enchant.',
      );
    }
    if (isBlank(enchantTargetId) || !targets.any((target) => target.id == enchantTargetId)) {
      return const ProjectValidation.failed('Choose a valid item to enchant.');
    }
  } else if (!db.items.any((row) => row.raw['Item ID'] == outputId)) {
    return const ProjectValidation.failed('Project output item is missing from data.');
  }

  return const ProjectValidation.ok();
}

/// Instantly completes one or more Special Production projects.
ProjectCompleteResult completeSpecialProject(
  GameDatabase db,
  PlayerSave save,
  String projectId,
  num quantity, {
  String? enchantTargetId,
  required num nowMs,
}) {
  final validation = validateProjectCompletion(db, save, projectId, quantity, enchantTargetId);
  if (!validation.ok) return ProjectCompleteResult.failed(validation.reason);

  final project = getProject(db, projectId)!;
  final crafts = quantity.floor();
  final withMaterials = removeIngredients(
    save,
    projectInputsForSave(
      save,
      project,
    ).map((input) => RecipeIngredient(itemId: input.itemId, quantity: input.quantity)).toList(),
    crafts,
  );
  if (withMaterials == null) {
    return const ProjectCompleteResult.failed('Missing required materials.');
  }

  final goldCost = jsNumber(project.raw['Gold Cost']) * crafts;
  if (withMaterials.gold < goldCost) {
    return const ProjectCompleteResult.failed('Not enough gold.');
  }

  var next = withMaterials.copyWith(gold: withMaterials.gold - goldCost);
  final outputId = jsString(project.raw['Output Item / Target ID']);
  final outputQty = jsNumber(project.raw['Output Quantity']) * crafts;
  var outputLabel = jsString(project.raw['Display Name']);

  if (isEnchantmentOutput(outputId)) {
    outputLabel = jsString(getEnchantment(db, outputId)!.raw['Display Name']);
    final target = decodeEnchantTarget(enchantTargetId);
    if (target == null) {
      return const ProjectCompleteResult.failed('Choose a valid item to enchant.');
    }

    // Inventory indexes can shift when materials are removed; re-resolve by item id.
    var resolved = target;
    if (target is InventoryEnchantTarget) {
      final prior = target.index >= 0 && target.index < save.inventory.length
          ? save.inventory[target.index]
          : null;
      if (prior == null || isNotBlank(prior.enchantmentId)) {
        return const ProjectCompleteResult.failed('Choose a valid item to enchant.');
      }
      final refreshed = next.inventory.indexWhere(
        (stack) => stack.itemId == prior.itemId && isBlank(stack.enchantmentId),
      );
      if (refreshed < 0) {
        return const ProjectCompleteResult.failed('Choose a valid item to enchant.');
      }
      resolved = InventoryEnchantTarget(refreshed);
    }

    final enchanted = applyEnchantmentToTarget(next, resolved, outputId);
    if (enchanted == null) {
      return const ProjectCompleteResult.failed('Could not apply the enchantment.');
    }
    next = enchanted;
  } else {
    final granted = addItemToInventoryExact(next, outputId, outputQty);
    if (!granted.ok) return ProjectCompleteResult.failed(granted.reason);
    next = granted.save!;
    final displayName = db.items
        .firstWhereOrNull((item) => item.raw['Item ID'] == outputId)
        ?.raw['Display Name'];
    if (displayName is String) outputLabel = displayName;
  }

  final skillId = jsString(project.raw['Skill ID']);
  final xpTotal = applyRaceSkillXp(db, save, skillId, jsNumber(project.raw['XP Reward']) * crafts);
  next = applyXp(next, db, skillId, xpTotal).save;
  next = applyQuestProcessProgress(db, next, jsString(project.raw['Project ID']), crafts);
  next = applyBountyProjectProgress(next, jsString(project.raw['Project ID']), crafts, nowMs);
  next = recordProjectMilestones(db, next, jsString(project.raw['Project ID']), crafts);

  return ProjectCompleteResult.ok(
    save: next,
    outputLabel: outputLabel,
    outputQty: isEnchantmentOutput(outputId) ? 1 : outputQty,
    xpGained: xpTotal,
    goldSpent: goldCost,
  );
}
