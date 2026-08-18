import '../js_compat.dart';
import '../save/generated/save_models.dart';

/// The unfinished pool action remembered for [activityId], if any.
String? heldActionIdFor(PlayerSave save, String? activityId) {
  if (isBlank(activityId)) return null;
  final id = save.heldActionByActivityId[activityId];
  return isBlank(id) ? null : id;
}

/// Remembers [actionId] for [activityId] until that action finishes.
PlayerSave withHeldAction(PlayerSave save, String activityId, String actionId) {
  return save.copyWith(
    heldActionByActivityId: <String, String>{...save.heldActionByActivityId, activityId: actionId},
  );
}

/// Forgets the unfinished action for [activityId] after it completes or a defeat.
PlayerSave withoutHeldAction(PlayerSave save, String? activityId) {
  if (isBlank(activityId) || !save.heldActionByActivityId.containsKey(activityId)) {
    return save;
  }
  return save.copyWith(
    heldActionByActivityId: <String, String>{
      for (final entry in save.heldActionByActivityId.entries)
        if (entry.key != activityId) entry.key: entry.value,
    },
  );
}
