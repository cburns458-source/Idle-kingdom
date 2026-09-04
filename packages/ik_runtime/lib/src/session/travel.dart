import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

/// An arrival, with the hostility outcome already turned into one line of text.
class TravelArrival {
  const TravelArrival({
    required this.save,
    required this.forcedActivityId,
    required this.blockedReason,
    required this.message,
    this.questCompletions = const <QuestArrivalCompletion>[],
  });

  final PlayerSave save;

  /// Set when a hostile area force-started combat on arrival.
  final String? forcedActivityId;

  /// Set when the area is hostile but combat could not be forced.
  final String? blockedReason;

  /// The hostility line to show, or null when the arrival was uneventful.
  final String? message;

  /// Visit-complete quests that should show a reward popup.
  final List<QuestArrivalCompletion> questCompletions;

  Map<String, Object?> toJson() => <String, Object?>{
    'save': save.toJson(),
    'forcedActivityId': forcedActivityId,
    'blockedReason': blockedReason,
    'message': message,
    'questCompletions': questCompletions.map((row) => row.toJson()).toList(),
  };
}

/// What a travel request turns into, once the rules have had their say.
sealed class TravelPlan {
  const TravelPlan();

  String get kind;

  Map<String, Object?> toJson();
}

/// The route is unavailable, or recovery from defeat is still locking travel.
class TravelBlocked extends TravelPlan {
  const TravelBlocked();

  @override
  String get kind => 'blocked';

  @override
  Map<String, Object?> toJson() => <String, Object?>{'kind': kind};
}

/// Adjacent enough to arrive immediately; [arrival] has already happened.
class TravelInstant extends TravelPlan {
  const TravelInstant(this.arrival);

  final TravelArrival arrival;

  @override
  String get kind => 'instant';

  @override
  Map<String, Object?> toJson() => <String, Object?>{'kind': kind, 'arrival': arrival.toJson()};
}

TravelArrival _arrivalOf(GameDatabase db, HostileTravelArrivalResult result) {
  return TravelArrival(
    save: result.save,
    forcedActivityId: result.forcedActivityId,
    blockedReason: result.forceBlockedReason,
    message: hostileForceMessage(db, result),
    questCompletions: result.questCompletions,
  );
}

/// Decides what travelling to [destinationId] does right now.
///
/// Destinations open immediately. A client may play a walk animation first, but
/// the save only changes here — route check, activity stop, and arrival — so
/// every client lands the same way.
TravelPlan planTravel(
  GameDatabase db,
  PlayerSave save,
  String destinationId,
  String browseMapId,
  num nowMs,
  RandomFn random,
) {
  if (isDeathPaused(save, nowMs)) return const TravelBlocked();
  final arrivalId = resolveSubMapTravelDestination(
    db,
    destinationId,
    browseMapId,
    save.currentLocationId,
  );
  final destOk = destinationId == save.currentLocationId
      ? arrivalId != destinationId
      : canTravelTo(
          db,
          save.currentLocationId,
          destinationId,
          browseMapId,
          save.unlockedLocationIds,
          save,
        );
  if (!destOk) {
    return const TravelBlocked();
  }

  return TravelInstant(
    _arrivalOf(db, applyHostileTravelArrival(db, save, arrivalId, nowMs, random)),
  );
}

/// Guild Travel: the hall is a per-guild instance, reachable from the guild
/// screen even when the player is not standing next to it.
TravelPlan planGuildHallTravel(GameDatabase db, PlayerSave save, num nowMs, RandomFn random) {
  if (isDeathPaused(save, nowMs)) return const TravelBlocked();
  return TravelInstant(
    _arrivalOf(db, applyHostileTravelArrival(db, save, guildHallLocationId, nowMs, random)),
  );
}
