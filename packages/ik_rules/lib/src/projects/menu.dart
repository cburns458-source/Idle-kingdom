import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../npcs/knowledge.dart';
import '../production/recipes.dart';
import '../recipes/knowledge.dart';
import '../save/generated/save_models.dart';
import '../spells/spells.dart';
import 'enchantments.dart';
import 'engine.dart';
import 'projects.dart';

String _skillName(GameDatabase db, String skillId) {
  final displayName = db.skills
      .firstWhereOrNull((skill) => skill.raw['Skill ID'] == skillId)
      ?.raw['Display Name'];
  return displayName is String ? displayName : skillId;
}

String? _itemName(GameDatabase db, String itemId) {
  final displayName = db.items
      .firstWhereOrNull((item) => item.raw['Item ID'] == itemId)
      ?.raw['Display Name'];
  return displayName is String ? displayName : null;
}

/// One row of a station's project list.
class ProjectListItem {
  const ProjectListItem({required this.projectId, required this.label, required this.locked});

  final String projectId;

  /// What the project makes, at what level: `Bronze bar → Bronze Bar (Lv 1)`.
  final String label;
  final bool locked;

  Map<String, Object?> toJson() => <String, Object?>{
    'projectId': projectId,
    'label': label,
    'locked': locked,
  };
}

String _listLabel(GameDatabase db, ProjectRow project) {
  final outputId = jsString(project.raw['Output Item / Target ID']);
  final rawLevel = project.raw['Required Skill 1 Level'];
  final level = jsNumberToString(rawLevel is num ? rawLevel : 1);
  final name = jsString(project.raw['Display Name']);
  if (isEnchantmentOutput(outputId)) return '$name (Lv $level)';
  return '$name → ${_itemName(db, outputId) ?? name} (Lv $level)';
}

/// Whether [project] answers to [query], by its own name or by what it makes.
bool projectMatchesQuery(GameDatabase db, ProjectRow project, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  final outputId = jsString(project.raw['Output Item / Target ID']);
  final enchantmentName = getEnchantment(db, outputId)?.raw['Display Name'];
  final candidates = <String?>[
    project.raw['Display Name'] is String ? project.raw['Display Name']! as String : null,
    project.raw['Internal Key'] is String ? project.raw['Internal Key']! as String : null,
    _itemName(db, outputId),
    enchantmentName is String ? enchantmentName : null,
  ];
  return candidates.any((value) => value != null && value.toLowerCase().contains(needle));
}

/// Whether this project can be completed right now: level, mentor, materials,
/// gold, and (for an enchantment) a valid target.
bool canMakeProject(GameDatabase db, PlayerSave save, ProjectRow project) {
  if (!meetsProjectSkills(save, project) || !meetsProjectKnowledge(db, save, project)) {
    return false;
  }
  if (maxProjectQuantity(save, project) < 1) return false;
  final outputId = jsString(project.raw['Output Item / Target ID']);
  if (!isEnchantmentOutput(outputId)) return true;
  final enchantment = getEnchantment(db, outputId);
  return enchantment != null && eligibleEnchantmentTargets(db, save, enchantment).isNotEmpty;
}

/// The projects a station offers, in menu order, narrowed by [query].
///
/// Locked rows stay in the list: seeing what the next mentor or level unlocks is
/// the point of the book. The start dropdown uses [readyProjectMenuList].
List<ProjectListItem> projectMenuList(
  GameDatabase db,
  PlayerSave save,
  String facilityId,
  String skillId, [
  String query = '',
]) {
  return projectsForFacility(db, facilityId, skillId)
      .where((project) => projectMatchesQuery(db, project, query))
      .map(
        (project) => ProjectListItem(
          projectId: jsString(project.raw['Project ID']),
          label: _listLabel(db, project),
          locked: !canMakeProject(db, save, project),
        ),
      )
      .toList();
}

/// Projects this station can complete right now.
List<ProjectListItem> readyProjectMenuList(
  GameDatabase db,
  PlayerSave save,
  String facilityId,
  String skillId, [
  String query = '',
]) {
  return projectMenuList(db, save, facilityId, skillId, query).where((row) => !row.locked).toList();
}

/// Every project at this station, including locked ones, as recipe-book rows.
List<RecipeBookEntry> recipeBookForProjectStation(
  PlayerSave save,
  GameDatabase db,
  String facilityId,
  String skillId,
) {
  final ids = projectsForFacility(
    db,
    facilityId,
    skillId,
  ).map((project) => jsString(project.raw['Project ID'])).toSet();
  return listRecipeBookEntries(
    save,
    db,
  ).where((entry) => entry.kind == 'project' && ids.contains(entry.id)).toList();
}

/// The project a station opens on: the first one that can actually be made.
String? defaultProjectId(GameDatabase db, PlayerSave save, String facilityId, String skillId) {
  final projects = projectsForFacility(db, facilityId, skillId);
  final ready = projects.firstWhereOrNull((project) => canMakeProject(db, save, project));
  final unlocked = projects.firstWhereOrNull(
    (project) => meetsProjectSkills(save, project) && meetsProjectKnowledge(db, save, project),
  );
  final chosen = ready ?? unlocked ?? projects.firstOrNull;
  return chosen == null ? null : jsString(chosen.raw['Project ID']);
}

class ProjectIngredientLine {
  const ProjectIngredientLine({
    required this.itemId,
    required this.name,
    required this.need,
    required this.owned,
  });

  final String itemId;
  final String name;
  final num need;
  final num owned;

  Map<String, Object?> toJson() => <String, Object?>{
    'itemId': itemId,
    'name': name,
    'need': need,
    'owned': owned,
  };
}

/// Everything shown about the selected project, with no numbers left to derive.
class ProjectDetail {
  const ProjectDetail({
    required this.projectId,
    required this.name,
    required this.outputItemId,
    required this.outputName,
    required this.outputQuantity,
    required this.summaryLine,
    required this.effectLine,
    required this.skillLine,
    required this.ingredients,
    required this.goldCost,
    required this.goldOwned,
    required this.isEnchantment,
    required this.lockedReason,
    required this.maxQuantity,
    required this.enchantTargets,
  });

  final String projectId;
  final String name;

  /// Null for an enchantment, which is applied rather than handed over.
  final String? outputItemId;
  final String outputName;
  final num outputQuantity;

  /// `Instant · 1,000 XP · 50 gold`.
  final String summaryLine;

  /// What an enchantment or a spell does, when the output has an effect.
  final String? effectLine;

  /// `Smithing 10 · Artisanry 5`, or null when the project asks for no skills.
  final String? skillLine;
  final List<ProjectIngredientLine> ingredients;
  final num goldCost;
  final num goldOwned;
  final bool isEnchantment;

  /// Null when the project can be made; otherwise why it cannot.
  final String? lockedReason;
  final num maxQuantity;

  /// Empty for anything but an enchantment.
  final List<EnchantTargetOption> enchantTargets;

  Map<String, Object?> toJson() => <String, Object?>{
    'projectId': projectId,
    'name': name,
    'outputItemId': outputItemId,
    'outputName': outputName,
    'outputQuantity': outputQuantity,
    'summaryLine': summaryLine,
    'effectLine': effectLine,
    'skillLine': skillLine,
    'ingredients': ingredients.map((line) => line.toJson()).toList(),
    'goldCost': goldCost,
    'goldOwned': goldOwned,
    'isEnchantment': isEnchantment,
    'lockedReason': lockedReason,
    'maxQuantity': maxQuantity,
    'enchantTargets': enchantTargets.map((option) => option.toJson()).toList(),
  };
}

String _summaryLine(ProjectRow project) {
  final parts = <String>['Instant', '${jsLocaleNumber(jsNumber(project.raw['XP Reward']))} XP'];
  final goldCost = jsNumber(project.raw['Gold Cost']);
  if (goldCost > 0) parts.add('${jsLocaleNumber(goldCost)} gold');
  return parts.join(' · ');
}

String? _lockedReason(GameDatabase db, PlayerSave save, ProjectRow project, String skillId) {
  final knowledge = hasProjectKnowledge(db, save, skillId);
  if (!knowledge.ok) {
    return 'Locked — speak with the ${knowledge.npcName} to unlock '
        '${_skillName(db, skillId)} projects.';
  }
  if (meetsProjectSkills(save, project)) return null;
  final unmet = unmetProjectSkillRequirements(db, save, project)
      .map((requirement) => '${requirement.skillName} ${jsNumberToString(requirement.level)}')
      .toList();
  return unmet.isEmpty ? 'Locked.' : 'Locked — needs ${unmet.join(', ')}.';
}

String? _effectLine(GameDatabase db, ProjectRow project) {
  final outputId = jsString(project.raw['Output Item / Target ID']);
  if (isEnchantmentOutput(outputId)) {
    final effect = getEnchantment(db, outputId)?.raw['Effect'];
    return effect is String ? effect : null;
  }
  if (!isSpellItem(db, outputId)) return null;
  final item = db.items.firstWhereOrNull((row) => row.raw['Item ID'] == outputId);
  // The last tooltip line says whether copies stack, which is what a buyer asks.
  return spellTooltipLines(db, item, outputId).lastOrNull;
}

ProjectDetail? projectDetail(GameDatabase db, PlayerSave save, String projectId) {
  final project = getProject(db, projectId);
  if (project == null) return null;
  final outputId = jsString(project.raw['Output Item / Target ID']);
  final enchantment = isEnchantmentOutput(outputId) ? getEnchantment(db, outputId) : null;
  final skillId = jsString(project.raw['Skill ID']);
  final reason = _lockedReason(db, save, project, skillId);
  final skills = projectSkillRequirements(project);
  final name = jsString(project.raw['Display Name']);
  final enchantmentName = enchantment?.raw['Display Name'];

  return ProjectDetail(
    projectId: projectId,
    name: name,
    outputItemId: enchantment != null ? null : outputId,
    outputName:
        (enchantment != null
            ? (enchantmentName is String ? enchantmentName : null)
            : _itemName(db, outputId)) ??
        name,
    outputQuantity: jsNumber(project.raw['Output Quantity']),
    summaryLine: _summaryLine(project),
    effectLine: _effectLine(db, project),
    skillLine: skills.isEmpty
        ? null
        : skills
              .map(
                (requirement) =>
                    '${_skillName(db, requirement.skillId)} '
                    '${jsNumberToString(requirement.level)}',
              )
              .join(' · '),
    ingredients: projectInputsForSave(save, project)
        .map(
          (input) => ProjectIngredientLine(
            itemId: input.itemId,
            name: _itemName(db, input.itemId) ?? input.itemId,
            need: input.quantity,
            owned: inventoryCount(save, input.itemId),
          ),
        )
        .toList(),
    goldCost: jsNumber(project.raw['Gold Cost']),
    goldOwned: save.gold,
    isEnchantment: enchantment != null,
    lockedReason: reason,
    maxQuantity: reason == null ? maxProjectQuantity(save, project) : 0,
    enchantTargets: enchantment == null
        ? const <EnchantTargetOption>[]
        : eligibleEnchantmentTargets(db, save, enchantment),
  );
}

/// What a finished project is worth, as the popup and the message say it.
class ProjectReceipt {
  const ProjectReceipt({required this.projectName, required this.lines, required this.message});

  final String projectName;
  final List<String> lines;
  final String message;

  Map<String, Object?> toJson() => <String, Object?>{
    'projectName': projectName,
    'lines': lines,
    'message': message,
  };
}

/// Describes a completed project.
///
/// [requestedQuantity] is what the player asked for, which can be more than one
/// craft's worth of output and is worth repeating back to them.
ProjectReceipt describeProjectCompletion(
  GameDatabase db,
  String projectId,
  num requestedQuantity,
  ProjectCompleteResult result,
) {
  final outputLabel = result.outputLabel!;
  final lines = <String>[
    if (result.outputQty > 1)
      '$outputLabel ×${jsNumberToString(result.outputQty)}'
    else
      outputLabel,
    if (result.xpGained > 0) '+${jsLocaleNumber(result.xpGained)} XP',
    if (result.goldSpent > 0) 'Spent ${jsLocaleNumber(result.goldSpent)} gold',
    if (requestedQuantity > 1) 'Crafted ${jsNumberToString(requestedQuantity)} times',
  ];
  final projectName = getProject(db, projectId)?.raw['Display Name'];

  return ProjectReceipt(
    projectName: projectName is String ? projectName : outputLabel,
    lines: lines,
    message: <String>[
      'Completed $outputLabel',
      if (result.outputQty > 1) '×${jsNumberToString(result.outputQty)}',
      if (result.xpGained > 0) '+${jsLocaleNumber(result.xpGained)} XP',
      if (result.goldSpent > 0) '-${jsNumberToString(result.goldSpent)} gold',
    ].join(' · '),
  );
}
