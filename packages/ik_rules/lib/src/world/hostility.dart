import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/engine.dart';
import '../activity/transition.dart';
import '../activity/xp.dart';
import '../combat/stats.dart';
import '../js_compat.dart';
import '../races/races.dart';
import '../rng/mulberry32.dart';
import '../save/generated/save_models.dart';
import '../time.dart';
import 'travel.dart';

/// Activities marked hostile through Danger Warning Combat Level.
List<ActivityRow> hostileActivitiesAt(GameDatabase db, String locationId) {
  final rows = db.activities.where((activity) {
    if (activity.raw['Location ID'] != locationId) return false;
    final warning = activity.raw['Danger Warning Combat Level'];
    return warning is num && warning.isFinite && warning > 0;
  }).toList();

  mergeSort(
    rows,
    compare: (a, b) => jsCompareThen(
      jsNumberOrZero(a.raw['Danger Warning Combat Level']) -
          jsNumberOrZero(b.raw['Danger Warning Combat Level']),
      () => jsLocaleCompare(jsString(a.raw['Activity ID']), jsString(b.raw['Activity ID'])),
    ),
  );
  return rows;
}

/// The hostile activity at this location the player is under-level for, if any.
ActivityRow? forcedHostileActivity(GameDatabase db, PlayerSave save, String locationId) {
  if (raceBypassesForcedHostilityAt(db, save, locationId)) return null;
  final combatLevel = getSkillProgress(save, combatSkillId).level;
  for (final activity in hostileActivitiesAt(db, locationId)) {
    final warning = activity.raw['Danger Warning Combat Level'];
    if (warning is num && combatLevel < warning) return activity;
  }
  return null;
}

class HostileTravelArrivalResult {
  const HostileTravelArrivalResult({
    required this.save,
    required this.forcedActivityId,
    required this.forceBlockedReason,
    required this.threatenedActivityId,
  });

  final PlayerSave save;
  final String? forcedActivityId;

  /// Set when the player is under-level but the hostile activity could not start.
  final String? forceBlockedReason;
  final String? threatenedActivityId;

  Map<String, Object?> toJson() => <String, Object?>{
    'save': save.toJson(),
    'forcedActivityId': forcedActivityId,
    'forceBlockedReason': forceBlockedReason,
    'threatenedActivityId': threatenedActivityId,
  };
}

/// Arrives at a destination, stopping any running primary activity. Arriving
/// under-level in a hostile area force-starts its combat.
HostileTravelArrivalResult applyHostileTravelArrival(
  GameDatabase db,
  PlayerSave save,
  String destinationLocationId,
  num nowMs,
  RandomFn random,
) {
  var next = applyTravelArrival(db, save, destinationLocationId, nowMs);
  next = clearActivityTransition(next);

  final threatened = forcedHostileActivity(db, next, destinationLocationId);
  if (threatened == null) {
    return HostileTravelArrivalResult(
      save: next,
      forcedActivityId: null,
      forceBlockedReason: null,
      threatenedActivityId: null,
    );
  }

  final activityId = jsString(threatened.raw['Activity ID']);
  final validation = validateActivityStart(db, next, activityId);
  if (!validation.ok) {
    return HostileTravelArrivalResult(
      save: next,
      forcedActivityId: null,
      forceBlockedReason: validation.reason,
      threatenedActivityId: activityId,
    );
  }

  final started = beginActivitySave(next, activityId, isoFromMs(nowMs));
  final generated = generateNextAction(db, started, activityId, random, nowMs);

  return HostileTravelArrivalResult(
    save: generated?.save ?? started,
    forcedActivityId: activityId,
    forceBlockedReason: null,
    threatenedActivityId: activityId,
  );
}

String? hostileForceMessage(GameDatabase db, HostileTravelArrivalResult result) {
  if (result.threatenedActivityId == null) return null;
  final activity = db.activities.firstWhereOrNull(
    (row) => row.raw['Activity ID'] == result.threatenedActivityId,
  );
  final contextualName = activity?.raw['Contextual Name'];
  final label = contextualName is String ? contextualName : 'hostile combat';
  final warningText = jsRawString(activity?.raw, 'Danger Warning Combat Level');
  if (result.forcedActivityId != null) {
    return 'Hostile area (Combat Level $warningText+) — forced into $label.';
  }
  if (result.forceBlockedReason != null) {
    return 'Hostile area (Combat Level $warningText+) — ${result.forceBlockedReason}';
  }
  return null;
}
