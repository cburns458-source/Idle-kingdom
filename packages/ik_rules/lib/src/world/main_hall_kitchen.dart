import 'package:ik_content/ik_content.dart';

import '../save/generated/save_models.dart';
import '../timers/location_timers.dart' show grandFeastQuestId;

/// Castle Main Hall cook station.
const String mainHallCookActivityId = 'ACT-0023';

const String mainHallKitchenLockedMessage = "I shouldn't cook here without permission";

/// True once Grand Feast is active or finished on this save.
bool grandFeastStarted(PlayerSave save) {
  return save.quests.any(
    (row) =>
        row.questId == grandFeastQuestId && (row.status == 'active' || row.status == 'completed'),
  );
}

/// [db] is unused; kept for TypeScript signature parity.
bool mainHallKitchenLocked(GameDatabase db, PlayerSave save, String activityId) {
  return activityId == mainHallCookActivityId && !grandFeastStarted(save);
}
