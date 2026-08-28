import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../save/generated/save_models.dart';
import '../world/constants.dart';
import '../world/travel.dart';
import 'quests.dart';
import 'steps.dart';

/// First Hint target on an active quest step, or the step's Visit target.
String? questVisitHintLocationId(GameDatabase db, PlayerSave save) {
  for (final quest in asQuestRows(db)) {
    final questId = quest['Quest ID'];
    if (questId is! String) continue;
    if (getQuestProgress(save, questId).status != 'active') continue;
    final step = questActiveStepObjectives(db, save, quest);
    if (step == null) continue;
    if (step.hintLocationIds.isNotEmpty) return step.hintLocationIds.first;
    if (step.visitLocationIds.isNotEmpty) return step.visitLocationIds.first;
  }
  return null;
}

/// Map node to pulse on [browseMapId], or null.
String? questHintNodeId(GameDatabase db, PlayerSave save, String browseMapId) {
  final hintId = questVisitHintLocationId(db, save);
  if (hintId == null) return null;
  final hint = db.locations.where((row) => row.locationId == hintId).firstOrNull;
  if (hint == null) return null;
  if (getLocationMapId(hint) == browseMapId) return hintId;

  var parentId = hint.parentLocationId;
  while (parentId != null && parentId.isNotEmpty) {
    final parent = db.locations.where((row) => row.locationId == parentId).firstOrNull;
    if (parent == null) break;
    if (getLocationMapId(parent) == browseMapId) return parentId;
    parentId = parent.parentLocationId;
  }

  if (browseMapId == mainMapId) {
    final hintMapId = getLocationMapId(hint);
    for (final row in db.locations) {
      if (getLocationMapId(row) != mainMapId) continue;
      if (!(row.locationType ?? '').toLowerCase().contains('sub-map gateway')) continue;
      final opensHintMap = db.locations.any(
        (child) => child.parentLocationId == row.locationId && getLocationMapId(child) == hintMapId,
      );
      if (opensHintMap) return row.locationId;
    }
  }
  return null;
}

/// Pulse the location-screen world-map chip while a Visit hint is outstanding.
bool questHintsWorldMapButton(GameDatabase db, PlayerSave save) {
  final hintId = questVisitHintLocationId(db, save);
  return hintId != null && save.currentLocationId != hintId;
}
