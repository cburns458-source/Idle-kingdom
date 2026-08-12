import 'package:ik_content/ik_content.dart';

import '../equipment/vitals.dart';
import '../save/generated/save_models.dart';
import 'races.dart';

class AssignRaceResult {
  const AssignRaceResult.ok(this.save, {required this.grantedStarterKit}) : reason = null;

  const AssignRaceResult.failed(this.reason) : save = null, grantedStarterKit = false;

  final PlayerSave? save;
  final bool grantedStarterKit;
  final String? reason;

  bool get ok => reason == null;
}

/// Sets the player's race.
///
/// When moving from no race → a race (first pick), grants that race's starting
/// item kit. Later race changes (menu test / future quest) only swap raceId and
/// refresh vitals — kits are not re-granted.
AssignRaceResult assignRace(GameDatabase db, PlayerSave save, String raceId) {
  if (raceById(db, raceId) == null) {
    return const AssignRaceResult.failed('Unknown race.');
  }

  final firstSelection = save.raceId == null;
  var next = save.copyWith(raceId: raceId);
  if (firstSelection) {
    next = grantRaceStartingItems(db, next, raceId);
  }
  return AssignRaceResult.ok(withRecalculatedVitals(db, next), grantedStarterKit: firstSelection);
}
