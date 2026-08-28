import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/engine.dart';
import '../activity/favorites.dart';
import '../activity/transition.dart';
import '../activity/xp.dart';
import '../combat/stats.dart';
import '../js_compat.dart';
import '../races/races.dart';
import '../rng/mulberry32.dart';
import '../save/generated/save_models.dart';
import '../time.dart';
import '../activity/requirements.dart';
import '../quests/quests.dart';
import 'travel.dart';

/// True when this location has a hostile activity, so its danger line may show.
bool locationShowsDangerWarning(GameDatabase db, String locationId) {
  return hostileActivitiesAt(db, locationId).isNotEmpty;
}

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

/// The player is under-level for a danger-warning activity here.
bool locationIsHostileFor(GameDatabase db, PlayerSave save, [String? locationId]) {
  return forcedHostileActivity(db, save, locationId ?? save.currentLocationId) != null;
}

const String hostileActivityLockReason =
    'Leave this area to stop. Hostile combat cannot be cancelled.';
const String hostileActivityStartReason =
    'Cannot start another action in a hostile area. Leave to escape.';

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
    this.questCompletions = const <QuestArrivalCompletion>[],
  });

  final PlayerSave save;
  final String? forcedActivityId;

  /// Set when the player is under-level but the hostile activity could not start.
  final String? forceBlockedReason;
  final String? threatenedActivityId;
  final List<QuestArrivalCompletion> questCompletions;

  Map<String, Object?> toJson() => <String, Object?>{
    'save': save.toJson(),
    'forcedActivityId': forcedActivityId,
    'forceBlockedReason': forceBlockedReason,
    'threatenedActivityId': threatenedActivityId,
    'questCompletions': questCompletions.map((row) => row.toJson()).toList(),
  };
}

const String questChoiceCombatActivityId = 'ACT-0034';

/// Starts Pressure the Guards when the combat route is chosen and the player is at the barracks.
({PlayerSave save, String? startedActivityId}) tryStartQuestChoiceCombat(
  GameDatabase db,
  PlayerSave save,
  num nowMs,
  RandomFn random,
) {
  if (save.currentActivityId == questChoiceCombatActivityId) {
    return (save: save, startedActivityId: null);
  }
  final activity = db.activities.firstWhereOrNull(
    (row) => row.raw['Activity ID'] == questChoiceCombatActivityId,
  );
  if (activity == null || activity.raw['Location ID'] != save.currentLocationId) {
    return (save: save, startedActivityId: null);
  }
  if (!activityVisibleForSave(db, save, questChoiceCombatActivityId)) {
    return (save: save, startedActivityId: null);
  }
  final validation = validateActivityStart(db, save, questChoiceCombatActivityId);
  if (!validation.ok) return (save: save, startedActivityId: null);
  final started = beginActivitySave(save, questChoiceCombatActivityId, isoFromMs(nowMs));
  final generated = generateNextAction(db, started, questChoiceCombatActivityId, random, nowMs);
  return (save: generated?.save ?? started, startedActivityId: questChoiceCombatActivityId);
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
  final arrival = applyTravelArrivalResult(db, save, destinationLocationId, nowMs);
  var next = clearActivityTransition(arrival.save);
  final questCompletions = arrival.questCompletions;

  final threatened = forcedHostileActivity(db, next, destinationLocationId);
  if (threatened == null) {
    final questCombat = tryStartQuestChoiceCombat(db, next, nowMs, random);
    if (questCombat.startedActivityId != null) {
      return HostileTravelArrivalResult(
        save: questCombat.save,
        forcedActivityId: null,
        forceBlockedReason: null,
        threatenedActivityId: null,
        questCompletions: questCompletions,
      );
    }
    return HostileTravelArrivalResult(
      save: _startFavoriteActivity(db, next, destinationLocationId, nowMs, random),
      forcedActivityId: null,
      forceBlockedReason: null,
      threatenedActivityId: null,
      questCompletions: questCompletions,
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
      questCompletions: questCompletions,
    );
  }

  final started = beginActivitySave(next, activityId, isoFromMs(nowMs));
  final generated = generateNextAction(db, started, activityId, random, nowMs);

  return HostileTravelArrivalResult(
    save: generated?.save ?? started,
    forcedActivityId: activityId,
    forceBlockedReason: null,
    threatenedActivityId: activityId,
    questCompletions: questCompletions,
  );
}

PlayerSave _startFavoriteActivity(
  GameDatabase db,
  PlayerSave save,
  String locationId,
  num nowMs,
  RandomFn random,
) {
  final favoriteId = favoriteActivityAt(save, locationId);
  if (favoriteId == null) return save;
  final validation = validateActivityStart(db, save, favoriteId);
  if (!validation.ok) return save;
  final started = beginActivitySave(save, favoriteId, isoFromMs(nowMs));
  return generateNextAction(db, started, favoriteId, random, nowMs)?.save ?? started;
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
