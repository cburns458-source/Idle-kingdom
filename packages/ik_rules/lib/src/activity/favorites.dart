import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../production/recipes.dart';
import '../save/generated/save_models.dart';

/// Whether [activityId] is the kind of work a star can start on arrival.
///
/// Only work the world does to a schedule qualifies — a combat or gathering pool.
/// A station has nothing to run until the player picks a recipe, so starring one
/// would put the character at a bench doing nothing.
bool canFavoriteActivity(GameDatabase db, String activityId) {
  final activity = db.activities.firstWhereOrNull((row) => row.activityId == activityId);
  if (activity == null) return false;
  return !isStandardProductionActivity(db, activity);
}

/// The starred activity at a location, if the player picked one.
String? favoriteActivityAt(PlayerSave save, [String? locationId]) {
  final id = save.favoriteActivityByLocationId[locationId ?? save.currentLocationId];
  return id == null || id.isEmpty ? null : id;
}

/// Stars [activityId] at [locationId], or clears the star when it is already set.
PlayerSave toggleFavoriteActivity(PlayerSave save, String locationId, String activityId) {
  final current = save.favoriteActivityByLocationId[locationId];
  final next = Map<String, String>.from(save.favoriteActivityByLocationId);
  if (current == activityId) {
    next.remove(locationId);
  } else {
    next[locationId] = activityId;
  }
  return save.copyWith(favoriteActivityByLocationId: next);
}
