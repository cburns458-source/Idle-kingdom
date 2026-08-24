import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/xp.dart';
import '../js_compat.dart';
import '../npcs/knowledge.dart';
import '../production/recipes.dart';
import '../projects/projects.dart';
import '../save/generated/save_models.dart';

String _knowledgeSourceOf(RecipeRow recipe) {
  final source = recipe.raw['Knowledge Source'];
  return (source == null ? '' : jsString(source)).trim();
}

/// Level-unlock recipes (empty / "automatic" / "level unlock") appear as soon
/// as the player reaches the proficiency. Any other Knowledge Source is a
/// taught recipe: it stays locked until [PlayerSave.unlockedRecipeIds]
/// includes it.
///
/// Smithing is skill-taught via a mentor ([knowsProject] /
/// [hasProjectKnowledge]), so individual smithing rows are not separately
/// locked. Cooking and crafting currently have no teacher — they stay
/// automatic. Later taught recipes just need a non-automatic Knowledge
/// Source; this gate already handles them.
bool isAutomaticLevelUnlock(RecipeRow recipe) {
  final source = _knowledgeSourceOf(recipe).toLowerCase();
  return source.isEmpty || source.contains('automatic') || source.contains('level unlock');
}

/// Whether the player knows a production recipe (can craft if otherwise eligible).
bool knowsRecipe(PlayerSave save, GameDatabase db, String recipeId) {
  if (save.unlockedRecipeIds.contains(recipeId)) return true;
  final recipe = getRecipe(db, recipeId);
  if (recipe == null || !isCompleteRecipe(recipe)) return false;
  if (!isAutomaticLevelUnlock(recipe)) return false;
  final level = getSkillProgress(save, jsString(recipe.raw['Skill ID'])).level;
  return level >= jsNumber(recipe.raw['Proficiency Level']);
}

/// Hard proficiency + knowledge-source gate used by production lists.
bool canKnowRecipe(PlayerSave save, GameDatabase db, RecipeRow recipe) {
  return knowsRecipe(save, db, jsString(recipe.raw['Recipe ID']));
}

PlayerSave unlockRecipeId(PlayerSave save, String recipeId) {
  final id = recipeId.trim();
  if (id.isEmpty) return save;
  if (save.unlockedRecipeIds.contains(id)) return save;
  return save.copyWith(unlockedRecipeIds: [...save.unlockedRecipeIds, id]);
}

bool knowsProject(PlayerSave save, GameDatabase db, String projectId) {
  final project = getProject(db, projectId);
  if (project == null || !isCompleteProject(project)) return false;
  return hasProjectKnowledge(db, save, jsString(project.raw['Skill ID'])).ok;
}

/// One row of the recipe book: a production recipe or a special project.
class RecipeBookEntry {
  const RecipeBookEntry({
    required this.kind,
    required this.id,
    required this.known,
    required this.name,
    required this.skill,
    required this.proficiency,
    required this.station,
    required this.location,
    required this.output,
    required this.materials,
    required this.knowledgeSource,
    required this.hintUnknown,
  });

  /// `recipe` or `project`.
  final String kind;
  final String id;
  final bool known;
  final String name;
  final String skill;
  final num proficiency;
  final String station;
  final String location;
  final String output;
  final String materials;
  final String knowledgeSource;
  final bool hintUnknown;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'id': id,
    'known': known,
    'name': name,
    'skill': skill,
    'proficiency': proficiency,
    'station': station,
    'location': location,
    'output': output,
    'materials': materials,
    'knowledgeSource': knowledgeSource,
    'hintUnknown': hintUnknown,
  };
}

String _itemName(GameDatabase db, Object? itemId) {
  if (itemId is! String || itemId.isEmpty) return '—';
  final displayName = db.items
      .firstWhereOrNull((item) => item.raw['Item ID'] == itemId)
      ?.raw['Display Name'];
  return displayName is String ? displayName : itemId;
}

class _FacilityLabel {
  const _FacilityLabel(this.station, this.location);

  final String station;
  final String location;
}

_FacilityLabel _facilityLabel(GameDatabase db, Object? facilityId) {
  if (facilityId is! String || facilityId.isEmpty) return const _FacilityLabel('—', '—');
  final facility = db.facilities.firstWhereOrNull((row) => row.raw['Facility ID'] == facilityId);
  if (facility == null) return _FacilityLabel(facilityId, '—');
  final locationName = db.locations
      .firstWhereOrNull((row) => row.raw['Location ID'] == facility.raw['Location ID'])
      ?.raw['Display Name'];
  final station = facility.raw['Display Name'];
  return _FacilityLabel(
    station is String ? station : facilityId,
    locationName is String ? locationName : '—',
  );
}

String _joinLines(List<String?> parts) => parts.whereType<String>().join(', ');

num _projectSkillFloor(ProjectRow project) {
  final level = project.raw['Required Skill 1 Level'];
  return level is num ? level : 1;
}

List<RecipeBookEntry> listRecipeBookEntries(PlayerSave save, GameDatabase db) {
  final entries = <RecipeBookEntry>[];

  for (final recipe in db.recipes.where(isCompleteRecipe)) {
    final recipeId = jsString(recipe.raw['Recipe ID']);
    final known = knowsRecipe(save, db, recipeId);
    final skillName = db.skills
        .firstWhereOrNull((row) => row.raw['Skill ID'] == recipe.raw['Skill ID'])
        ?.raw['Display Name'];
    final place = _facilityLabel(db, recipe.raw['Facility ID']);
    final ingredients = _joinLines(<String?>[
      for (var slot = 1; slot <= 4; slot += 1)
        if (isNotBlank(recipe.raw['Ingredient $slot Item ID'] as String?))
          '${_itemName(db, recipe.raw['Ingredient $slot Item ID'])} '
              '×${jsNumberToString(jsNumber(recipe.raw['Ingredient $slot Quantity'] ?? 1))}',
    ]);
    final source = _knowledgeSourceOf(recipe);
    entries.add(
      RecipeBookEntry(
        kind: 'recipe',
        id: recipeId,
        known: known,
        name: jsString(recipe.raw['Display Name']),
        skill: skillName is String ? skillName : jsString(recipe.raw['Skill ID']),
        proficiency: jsNumber(recipe.raw['Proficiency Level']),
        station: place.station,
        location: place.location,
        output:
            '${_itemName(db, recipe.raw['Output Item ID'])} '
            '×${jsNumberToString(jsNumber(recipe.raw['Output Quantity']))}',
        materials: ingredients.isEmpty ? '—' : ingredients,
        knowledgeSource: source.isEmpty ? 'Automatic level unlock' : source,
        hintUnknown: !known && !isAutomaticLevelUnlock(recipe),
      ),
    );
  }

  for (final project in db.projects.where(isCompleteProject)) {
    final projectId = jsString(project.raw['Project ID']);
    final known = knowsProject(save, db, projectId);
    final skillName = db.skills
        .firstWhereOrNull((row) => row.raw['Skill ID'] == project.raw['Skill ID'])
        ?.raw['Display Name'];
    final place = _facilityLabel(db, project.raw['Facility ID']);
    final materials = _joinLines(<String?>[
      for (var slot = 1; slot <= 4; slot += 1)
        if (isNotBlank(project.raw['Input $slot Item ID'] as String?))
          '${_itemName(db, project.raw['Input $slot Item ID'])} '
              '×${jsNumberToString(jsNumber(project.raw['Input $slot Quantity'] ?? 1))}',
    ]);
    final knowledge = hasProjectKnowledge(db, save, jsString(project.raw['Skill ID']));
    final goldCost = jsNumber(project.raw['Gold Cost']);
    final outputId = jsString(project.raw['Output Item / Target ID']);
    entries.add(
      RecipeBookEntry(
        kind: 'project',
        id: projectId,
        known: known,
        name: jsString(project.raw['Display Name']),
        skill: skillName is String ? skillName : jsString(project.raw['Skill ID']),
        proficiency: _projectSkillFloor(project),
        station: place.station,
        location: place.location,
        output: isEnchantmentOutput(outputId)
            ? jsString(project.raw['Display Name'])
            : '${_itemName(db, outputId)} '
                  '×${jsNumberToString(jsNumber(project.raw['Output Quantity']))}',
        materials: materials.isNotEmpty
            ? materials
            : (goldCost > 0 ? '${jsNumberToString(goldCost)} gold' : '—'),
        knowledgeSource: knowledge.ok ? 'Mentor unlock' : 'Mentor: ${knowledge.npcName}',
        hintUnknown: !known,
      ),
    );
  }

  mergeSort(
    entries,
    compare: (a, b) =>
        jsCompareThen(a.proficiency - b.proficiency, () => jsLocaleCompare(a.name, b.name)),
  );
  return entries;
}

/// Unlocked recipes and mentor-known projects for one skill.
List<RecipeBookEntry> recipeBookForSkill(PlayerSave save, GameDatabase db, String skillId) {
  return listRecipeBookEntries(save, db).where((entry) {
    if (!entry.known) return false;
    if (entry.kind == 'recipe') {
      return getRecipe(db, entry.id)?.raw['Skill ID'] == skillId;
    }
    return getProject(db, entry.id)?.raw['Skill ID'] == skillId;
  }).toList();
}
