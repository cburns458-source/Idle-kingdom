import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/requirements.dart';
import '../config.dart';
import '../js_compat.dart';
import '../recipes/knowledge.dart';
import '../save/generated/save_models.dart';

/// One material line of a recipe.
class RecipeIngredient {
  const RecipeIngredient({required this.itemId, required this.quantity});

  final String itemId;
  final num quantity;

  Map<String, Object?> toJson() => <String, Object?>{'itemId': itemId, 'quantity': quantity};
}

bool isCompleteRecipe(RecipeRow recipe) {
  if (recipe.raw['Status'] == 'Needs Data') return false;
  if (recipe.raw['Base Duration Seconds'] is! num) return false;
  if (recipe.raw['XP Reward'] is! num) return false;
  if (recipe.raw['Output Quantity'] is! num) return false;
  if (isBlank(recipe.raw['Output Item ID'] as String?) ||
      isBlank(recipe.raw['Facility ID'] as String?) ||
      isBlank(recipe.raw['Skill ID'] as String?)) {
    return false;
  }
  return recipe.raw['Proficiency Level'] is num;
}

List<RecipeIngredient> recipeIngredients(RecipeRow recipe) {
  final out = <RecipeIngredient>[];
  for (var slot = 1; slot <= 3; slot += 1) {
    final itemId = recipe.raw['Ingredient $slot Item ID'];
    final quantity = recipe.raw['Ingredient $slot Quantity'];
    if (itemId is String && itemId.isNotEmpty && quantity is num && quantity > 0) {
      out.add(RecipeIngredient(itemId: itemId, quantity: quantity));
    }
  }
  return out;
}

num inventoryCount(PlayerSave save, String itemId) {
  return save.inventory.firstWhereOrNull((stack) => stack.itemId == itemId)?.quantity ?? 0;
}

num maxCraftsFromMaterials(PlayerSave save, RecipeRow recipe) {
  final ingredients = recipeIngredients(recipe);
  if (ingredients.isEmpty) return 0;
  num max = double.infinity;
  for (final ingredient in ingredients) {
    max = math.min(max, (inventoryCount(save, ingredient.itemId) / ingredient.quantity).floor());
  }
  return max.isFinite ? math.max(0, max) : 0;
}

num queueCapSeconds(GameDatabase db) {
  return configNumber(db, 'standard_production_queue_cap', 24) * 3600;
}

num maxCraftsFromQueueCap(GameDatabase db, RecipeRow recipe) {
  final duration = math.max(1, jsNumber(recipe.raw['Base Duration Seconds']));
  return math.max(0, (queueCapSeconds(db) / duration).floor());
}

/// Shared recipe books: castle/citadel stations reuse Town facility catalogs.
const Map<String, String> _sharedRecipeFacilityIds = <String, String>{
  'FAC-0010': 'FAC-0001',
  'FAC-0012': 'FAC-0001',
  'FAC-0013': 'FAC-0003',
  'FAC-0014': 'FAC-0004',
  'FAC-0015': 'FAC-0006',
};

/// Citadel special-production facilities reuse Town project catalogs.
const Map<String, String> sharedProjectFacilityIds = <String, String>{
  'FAC-0013': 'FAC-0003',
  'FAC-0016': 'FAC-0005',
};

String projectFacilityIdForLookup(String facilityId) {
  return sharedProjectFacilityIds[facilityId] ?? facilityId;
}

String recipeFacilityIdForLookup(String facilityId) {
  return _sharedRecipeFacilityIds[facilityId] ?? facilityId;
}

bool recipeMatchesFacility(String recipeFacilityId, String activityFacilityId) {
  return recipeFacilityId == recipeFacilityIdForLookup(activityFacilityId);
}

String? facilityIdForActivity(GameDatabase db, String activityId) {
  final station = requirementsForEntity(
    db,
    'Activity',
    activityId,
  ).firstWhereOrNull((row) => row.raw['Requirement Type'] == 'Station');
  final value = station?.raw['Reference ID / Value'];
  return value is String && value.isNotEmpty ? value : null;
}

bool isStandardProductionActivity(GameDatabase db, ActivityRow activity) {
  if (isNotBlank(activity.raw['Pool ID'] as String?)) return false;
  return facilityIdForActivity(db, jsString(activity.raw['Activity ID'])) != null;
}

List<RecipeRow> recipesForActivity(GameDatabase db, PlayerSave save, String activityId) {
  final facilityId = facilityIdForActivity(db, activityId);
  if (facilityId == null) return const <RecipeRow>[];
  final matching = db.recipes
      .where(
        (recipe) =>
            isCompleteRecipe(recipe) &&
            recipeMatchesFacility(jsString(recipe.raw['Facility ID']), facilityId) &&
            canKnowRecipe(save, db, recipe),
      )
      .toList();
  mergeSort(
    matching,
    compare: (a, b) {
      final delta = jsNumber(a.raw['Proficiency Level']) - jsNumber(b.raw['Proficiency Level']);
      return delta == 0 || delta.isNaN ? 0 : (delta > 0 ? 1 : -1);
    },
  );
  return matching;
}

RecipeRow? getRecipe(GameDatabase db, String recipeId) {
  return db.recipes.firstWhereOrNull((recipe) => recipe.raw['Recipe ID'] == recipeId);
}

num clampProductionQuantity(GameDatabase db, PlayerSave save, RecipeRow recipe, num requested) {
  final wanted = requested.floor();
  if (wanted <= 0) return 0;
  return math.min(
    wanted,
    math.min(maxCraftsFromMaterials(save, recipe), maxCraftsFromQueueCap(db, recipe)),
  );
}
