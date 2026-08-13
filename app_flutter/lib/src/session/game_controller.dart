import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'local_player_art.dart';

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

/// A finished craft, held so the production stage can pop the item icon.
class CraftPopup {
  const CraftPopup({required this.itemId, required this.displayName, required this.seq});

  final String itemId;
  final String displayName;

  /// Bumps each craft so a new pop can restart even when the item repeats.
  final int seq;
}

/// The screen-facing half of the session.
///
/// The rules and the tick live in `ik_runtime`; this holds the things that are
/// only true of a screen — the last few reward lines, the current message, the
/// journey being animated — and notifies listeners once per frame. Player
/// intents call the shared rules and hand the result to [GameSession.apply], so
/// nothing on a screen can put a save into storage by another route.
class GameController extends ChangeNotifier {
  GameController({required this.database, required this.session, LocalPlayerArt? localArt})
    : localArt = localArt ?? LocalPlayerArt();

  final LoadedDatabase database;

  /// The headless session: the save, the tick, and the write pipeline.
  final GameSession session;

  /// Client-only PNG override for this device's player sprite.
  final LocalPlayerArt localArt;

  /// How many completed actions the reward strip keeps.
  static const int _rewardHistory = 3;

  final List<ActionRewardBundle> _recentRewards = <ActionRewardBundle>[];
  String? _message;
  String? _activityError;
  TravelInFlight? _travel;
  double _travelProgress = 0;
  UnattendedResult? _awaySummary;
  CosmeticUnlockNotice? _cosmeticUnlock;
  AutoEquipProposal? _autoEquip;
  CombatRoundEvent? _lastRound;
  int _roundSeq = 0;
  CraftPopup? _craftPopup;

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

  /// The tool an activity wants, offered rather than demanded.
  AutoEquipProposal? get autoEquip => _autoEquip;

  /// The last resolved combat round, kept so the stage can float damage.
  CombatRoundEvent? get lastRound => _lastRound;

  /// Bumps when [lastRound] is replaced, so a floater can restart its layout.
  int get lastRoundSeq => _roundSeq;

  /// The last finished craft, kept so the station can pop the item icon.
  CraftPopup? get craftPopup => _craftPopup;

  /// True after a victory until the next round replaces [lastRound].
  bool get defeatedFlash {
    final round = _lastRound;
    return round != null && round.outcome == 'victory';
  }

  /// How far the current combat round has run, from 0 to 1.
  ///
  /// Derived from `combatRoundStartedAt` and the configured round length; the
  /// shell's frame tick is what makes this move.
  double get combatRoundProgress {
    if (isRecovering || defeatedFlash) return 0;
    final startedAt = save.combatRoundStartedAt;
    if (startedAt == null || startedAt.isEmpty) return 0;
    final roundMs = configNumber(db, 'combat_round_duration', 4) * 1000;
    final started = jsDateParse(startedAt);
    if (!started.isFinite || roundMs <= 0) return 0;
    return ((session.clock() - started) / roundMs).clamp(0, 1).toDouble();
  }

  double get actionProgress => session.actionProgress.toDouble();
  num get deathPauseRemainingMs => session.deathPauseRemaining;
  bool get isRecovering => deathPauseRemainingMs > 0;

  LocationRow? get location => indexes.locationsById[save.currentLocationId];

  /// Bytes of the local PNG override, if this device has one.
  Uint8List? get localPlayerPng => localArt.bytes;

  /// Stores a PNG for this client only. Returns a reason when it is refused.
  String? applyLocalPlayerPng(Uint8List bytes) {
    final error = localArt.setPng(bytes);
    if (error == null) notifyListeners();
    return error;
  }

  /// Drops the PNG override so the bundled adventurer shows again.
  void resetLocalPlayerPng() {
    if (!localArt.hasOverride) return;
    localArt.clear();
    notifyListeners();
  }

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
        _clearStageFx();
      case InventoryFullEvent():
        _activityError = 'Inventory full — free a slot to keep crafting.';
      case CraftCompletedEvent(itemId: final itemId, displayName: final displayName):
        _craftPopup = CraftPopup(
          itemId: itemId,
          displayName: displayName,
          seq: (_craftPopup?.seq ?? 0) + 1,
        );
      case final CombatRoundEvent round:
        _lastRound = round;
        _roundSeq += 1;
      case EnemyDefeatedEvent():
      case PlayerDefeatedEvent():
      case RecoveredEvent():
      case CritterSpawnedEvent():
        break;
    }
  }

  void _clearStageFx() {
    _lastRound = null;
    _craftPopup = null;
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
  ///
  /// When the only thing missing is a tool the bag already holds, this asks
  /// rather than refuses: [autoEquip] carries the offer until it is answered.
  void startActivity(String activityId, {bool allowAutoEquip = true}) {
    final result = requestActivityStart(db, save, activityId, session.clock(), _random);
    if (!result.ok) {
      // Nothing is startable during a death pause, so there is nothing to offer.
      if (allowAutoEquip && !isRecovering) {
        final proposal = proposeAutoEquipForActivity(db, save, activityId, result.reason!);
        if (proposal != null) {
          _autoEquip = proposal;
          _activityError = null;
          notifyListeners();
          return;
        }
      }
      _activityError = result.reason;
      notifyListeners();
      return;
    }
    _autoEquip = null;
    session.apply(result.save!);
    _recentRewards.clear();
    _activityError = null;
    _message = null;
    _clearStageFx();
    notifyListeners();
  }

  /// Equips the offered tool and starts what wanted it.
  ///
  /// The second start cannot ask again: the tool is on, and if that was not
  /// enough the player deserves the reason instead of another prompt.
  void confirmAutoEquip() {
    final proposal = _autoEquip;
    if (proposal == null) return;
    _autoEquip = null;
    final equipped = applyAutoEquipProposal(db, save, proposal);
    if (!equipped.ok) {
      _activityError = equipped.reason;
      notifyListeners();
      return;
    }
    session.apply(withRecalculatedVitals(db, equipped.save!));
    startActivity(proposal.activityId, allowAutoEquip: false);
  }

  /// Turns the offer down, leaving the refusal that prompted it on screen.
  void declineAutoEquip() {
    final proposal = _autoEquip;
    if (proposal == null) return;
    _autoEquip = null;
    _activityError = proposal.failureReason;
    notifyListeners();
  }

  /// Pockets whatever is loitering at the current location.
  void collectCritterHere() {
    final result = collectCritter(save, save.currentLocationId);
    if (!result.ok) return;
    commit(result.save!);
    announce(result.message!);
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
    _clearStageFx();
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

  /// Travels into the player's guild hall from the Guilds screen.
  bool travelToGuildHall() {
    if (_travel != null) return false;
    final plan = session.travelToGuildHall();
    switch (plan) {
      case TravelBlocked():
        return false;
      case TravelInstant(arrival: final arrival):
        _recentRewards.clear();
        _showArrival(arrival);
      case TravelTimed():
        return false;
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
