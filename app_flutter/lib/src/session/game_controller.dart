import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

/// A journey in progress, which the client animates itself.
class TravelInFlight {
  const TravelInFlight({
    required this.fromLocationId,
    required this.toLocationId,
    required this.startedAtMs,
    required this.durationMs,
  });

  final String fromLocationId;
  final String toLocationId;
  final num startedAtMs;
  final num durationMs;

  double progressAt(num nowMs) {
    if (durationMs <= 0) return 1;
    return math.min(1, math.max(0, (nowMs - startedAtMs) / durationMs));
  }
}

/// The screen-facing half of the session.
///
/// The rules and the tick live in `ik_runtime`; this holds the things that are
/// only true of a screen — the last few reward lines, the current message, the
/// journey being animated — and notifies listeners once per frame. Player
/// intents call the shared rules and hand the result to [GameSession.apply], so
/// the Flutter client stores saves through exactly the path the React one does.
class GameController extends ChangeNotifier {
  GameController({required this.database, required this.session});

  final LoadedDatabase database;

  /// The headless session: the save, the tick, and the write pipeline.
  final GameSession session;

  /// How many completed actions the reward strip keeps.
  static const int _rewardHistory = 3;

  final List<ActionRewardBundle> _recentRewards = <ActionRewardBundle>[];
  String? _message;
  String? _activityError;
  TravelInFlight? _travel;
  double _travelProgress = 0;
  UnattendedResult? _awaySummary;
  CosmeticUnlockNotice? _cosmeticUnlock;

  GameDatabase get db => database.launch;
  DatabaseIndexes get indexes => database.launchIndexes;
  PlayerSave get save => session.save;

  List<ActionRewardBundle> get recentRewards => List.unmodifiable(_recentRewards);
  String? get message => _message;
  String? get activityError => _activityError;
  TravelInFlight? get travel => _travel;
  double get travelProgress => _travelProgress;

  /// The catch-up from the last boot, until the player dismisses it.
  UnattendedResult? get awaySummary => _awaySummary;

  /// A cosmetic that was just unlocked and has not been shown off yet.
  CosmeticUnlockNotice? get cosmeticUnlock => _cosmeticUnlock;

  double get actionProgress => session.actionProgress.toDouble();
  num get deathPauseRemainingMs => session.deathPauseRemaining;
  bool get isRecovering => deathPauseRemainingMs > 0;

  LocationRow? get location => indexes.locationsById[save.currentLocationId];

  /// Keeps the boot's catch-up if it actually credited something.
  ///
  /// A fresh character, or a return after a few seconds, has nothing to report
  /// and should not be met with a summary panel.
  void adoptBoot(SessionBoot boot) {
    final away = boot.unattended;
    final credited =
        away.gatheringActions +
        away.craftsCompleted +
        away.combatVictories +
        away.combatDeaths +
        away.crittersSpawned;
    _awaySummary = boot.created || credited <= 0 ? null : away;
  }

  void dismissAwaySummary() {
    _awaySummary = null;
    notifyListeners();
  }

  /// Queues the unlock popup for the first of [grants].
  ///
  /// One purchase can unlock several cosmetics, and popups stacked over each
  /// other read worse than one popup and a wardrobe holding the rest.
  void noteCosmeticUnlocks(List<ShopCosmeticGrant> grants) {
    if (grants.isEmpty) return;
    final grant = grants.first;
    _cosmeticUnlock = cosmeticUnlockNotice(db, grant.cosmeticId, grant.isFirstEver);
    notifyListeners();
  }

  void dismissCosmeticUnlock() {
    _cosmeticUnlock = null;
    notifyListeners();
  }

  void clearMessages() {
    _message = null;
    _activityError = null;
    notifyListeners();
  }

  /// Stores the save a panel's intent produced, and repaints.
  ///
  /// Panels call the shared rules themselves and pass the result here, which is
  /// the only way a save reaches storage.
  void commit(PlayerSave next) {
    session.apply(next);
    notifyListeners();
  }

  /// Reports why an intent was refused, in the place activity errors appear.
  void report(String? reason) {
    _activityError = reason;
    notifyListeners();
  }

  /// Says what an intent did, in the place tick messages appear.
  void announce(String text) {
    _message = text;
    notifyListeners();
  }

  /// [commit] for anything that changed the loadout, so max HP follows the gear.
  void commitLoadout(PlayerSave next) => commit(withRecalculatedVitals(db, next));

  /// Advances the game by one frame. The shell drives this from a ticker, so it
  /// stops when the app is backgrounded and picks up from the clock on return.
  void tick() {
    final result = session.tick();
    for (final event in result.events) {
      _applyEvent(event);
    }
    _advanceTravel();
    // A frame always repaints: the progress bars and timers are read from the
    // clock, so they move even on the ticks where nothing was due.
    notifyListeners();
  }

  void _applyEvent(SessionEvent event) {
    switch (event) {
      case RewardsEvent(bundle: final bundle):
        _recentRewards.insert(0, bundle);
        if (_recentRewards.length > _rewardHistory) _recentRewards.removeLast();
      case MessageEvent(text: final text):
        _message = text;
      case ActivityStoppedEvent(reason: final reason):
        _activityError = reason;
      case InventoryFullEvent():
        _activityError = 'Inventory full — free a slot to keep crafting.';
      case CraftCompletedEvent():
      case CombatRoundEvent():
      case EnemyDefeatedEvent():
      case PlayerDefeatedEvent():
      case RecoveredEvent():
      case CritterSpawnedEvent():
        break;
    }
  }

  void _advanceTravel() {
    final journey = _travel;
    if (journey == null) return;
    final nowMs = session.clock();
    _travelProgress = journey.progressAt(nowMs);
    if (_travelProgress < 1) return;
    _travel = null;
    _travelProgress = 0;
    _showArrival(session.arrive(journey.toLocationId));
  }

  /// Starts or replaces the primary activity at the current location.
  void startActivity(String activityId) {
    final result = requestActivityStart(db, save, activityId, session.clock(), _random);
    if (!result.ok) {
      _activityError = result.reason;
      notifyListeners();
      return;
    }
    session.apply(result.save!);
    _recentRewards.clear();
    _activityError = null;
    _message = null;
    notifyListeners();
  }

  void stopActivity() {
    final result = requestActivityStop(db, save, session.clock());
    if (!result.ok) {
      _activityError = result.reason;
      notifyListeners();
      return;
    }
    session.apply(result.save!);
    _activityError = null;
    notifyListeners();
  }

  /// Travels to [destinationId], reporting whether the request was accepted.
  bool travelTo(String destinationId, String browseMapId) {
    if (_travel != null) return false;
    final nowMs = session.clock();
    final from = save.currentLocationId;
    final plan = session.travelTo(destinationId, browseMapId);
    switch (plan) {
      case TravelBlocked():
        return false;
      case TravelInstant(arrival: final arrival):
        _recentRewards.clear();
        _showArrival(arrival);
      case TravelTimed(durationMs: final durationMs):
        _recentRewards.clear();
        _travel = TravelInFlight(
          fromLocationId: from,
          toLocationId: destinationId,
          startedAtMs: nowMs,
          durationMs: durationMs,
        );
        _travelProgress = 0;
        notifyListeners();
    }
    return true;
  }

  /// Names a new character, gives them a look, and grants their race's kit.
  ///
  /// Returns the reason it was refused, or null on success.
  String? createCharacter(String name, String raceId, {PlayerAppearance? appearance}) {
    final cleaned = normalizeCharacterName(name);
    if (cleaned == null) return 'Enter a name to continue.';
    final named = save.copyWith(characterName: cleaned, appearance: appearance);
    final assigned = assignRace(db, named, raceId);
    if (!assigned.ok) return assigned.reason;
    session.apply(assigned.save!);
    notifyListeners();
    return null;
  }

  void _showArrival(TravelArrival arrival) {
    _message = arrival.forcedActivityId != null ? arrival.message : null;
    _activityError = arrival.blockedReason != null ? arrival.message : null;
    notifyListeners();
  }

  double _random() => _rng.nextDouble();
  final math.Random _rng = math.Random();
}
