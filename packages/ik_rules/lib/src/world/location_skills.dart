import 'package:ik_content/ik_content.dart';

import '../activity/pools.dart';
import '../activity/requirements.dart';
import '../js_compat.dart';
import '../production/recipes.dart';
import '../projects/projects.dart';
import '../save/generated/save_models.dart';

/// Skill IDs that have a visible gathering, combat, or production action here.
///
/// Arena / PvP is not a skill-tagged activity, so it is omitted on purpose.
List<String> skillIdsForLocation(GameDatabase db, PlayerSave save, String locationId) {
  final ids = <String>{};

  for (final activity in db.activities) {
    if (activity.locationId != locationId) continue;
    if (!activityVisibleForSave(db, save, activity.activityId)) continue;

    final poolId = activity.poolId;
    if (poolId != null && poolId.isNotEmpty) {
      for (final candidate in eligiblePoolEntries(db, poolId)) {
        final skillId = candidate.action.relevantSkillId;
        if (skillId.isNotEmpty) ids.add(skillId);
      }
    }

    if (isStandardProductionActivity(db, activity)) {
      final facilityId = facilityIdForActivity(db, activity.activityId);
      if (facilityId == null) continue;
      for (final recipe in db.recipes) {
        if (!isCompleteRecipe(recipe)) continue;
        if (!recipeMatchesFacility(jsString(recipe.raw['Facility ID']), facilityId)) continue;
        if (recipe.skillId.isNotEmpty) ids.add(recipe.skillId);
      }
    }
  }

  for (final station in specialProductionStationsVisibleAt(db, save, locationId)) {
    if (station.skillId.isNotEmpty) ids.add(station.skillId);
  }

  final ordered = ids.toList();
  ordered.sort((a, b) => _skillOrder(db, a).compareTo(_skillOrder(db, b)));
  return ordered;
}

int _skillOrder(GameDatabase db, String skillId) {
  final index = db.skills.indexWhere((row) => row.skillId == skillId);
  return index < 0 ? 1 << 20 : index;
}
