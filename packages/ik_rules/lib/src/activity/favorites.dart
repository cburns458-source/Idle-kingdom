import '../save/generated/save_models.dart';

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
