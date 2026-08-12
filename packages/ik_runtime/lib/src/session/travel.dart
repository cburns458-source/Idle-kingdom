import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

/// An arrival, with the hostility outcome already turned into one line of text.
class TravelArrival {
  const TravelArrival({
    required this.save,
    required this.forcedActivityId,
    required this.blockedReason,
    required this.message,
  });

  final PlayerSave save;

  /// Set when a hostile area force-started combat on arrival.
  final String? forcedActivityId;

  /// Set when the area is hostile but combat could not be forced.
  final String? blockedReason;

  /// The hostility line to show, or null when the arrival was uneventful.
  final String? message;

  Map<String, Object?> toJson() => <String, Object?>{
    'save': save.toJson(),
    'forcedActivityId': forcedActivityId,
    'blockedReason': blockedReason,
    'message': message,
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

/// Adjacent enough to arrive with no journey; [arrival] has already happened.
class TravelInstant extends TravelPlan {
  const TravelInstant(this.arrival);

  final TravelArrival arrival;

  @override
  String get kind => 'instant';

  @override
  Map<String, Object?> toJson() => <String, Object?>{'kind': kind, 'arrival': arrival.toJson()};
}

/// A journey the client animates. [save] has the current activity stopped, and
/// the client calls [arriveFromTravel] once [durationMs] has passed.
class TravelTimed extends TravelPlan {
  const TravelTimed({required this.save, required this.durationMs});

  final PlayerSave save;
  final num durationMs;

  @override
  String get kind => 'timed';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'durationMs': durationMs,
    'save': save.toJson(),
  };
}

TravelArrival _arrivalOf(GameDatabase db, HostileTravelArrivalResult result) {
  return TravelArrival(
    save: result.save,
    forcedActivityId: result.forcedActivityId,
    blockedReason: result.forceBlockedReason,
    message: hostileForceMessage(db, result),
  );
}

/// Decides what travelling to [destinationId] does right now.
///
/// The journey itself is the client's to animate, but everything that touches the
/// save — the route check, stopping the current activity, and the arrival — is
/// decided here so every client behaves the same.
TravelPlan planTravel(
  GameDatabase db,
  PlayerSave save,
  String destinationId,
  String browseMapId,
  num nowMs,
  RandomFn random,
) {
  if (isDeathPaused(save, nowMs)) return const TravelBlocked();
  if (!canTravelTo(
    db,
    save.currentLocationId,
    destinationId,
    browseMapId,
    save.unlockedLocationIds,
  )) {
    return const TravelBlocked();
  }

  final durationMs = travelDurationMs(findConnection(db, save.currentLocationId, destinationId));
  if (durationMs <= 0) {
    return TravelInstant(
      _arrivalOf(db, applyHostileTravelArrival(db, save, destinationId, nowMs, random)),
    );
  }

  // Timed travel stops the current activity the moment the journey begins.
  return TravelTimed(save: beginTravelActivityChange(db, save, nowMs), durationMs: durationMs);
}

/// Completes a timed journey started from a [TravelTimed] plan.
TravelArrival arriveFromTravel(
  GameDatabase db,
  PlayerSave save,
  String destinationId,
  num nowMs,
  RandomFn random,
) {
  return _arrivalOf(db, applyHostileTravelArrival(db, save, destinationId, nowMs, random));
}
