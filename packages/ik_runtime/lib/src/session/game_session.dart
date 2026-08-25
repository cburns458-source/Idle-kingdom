import 'dart:math' as math;

import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../save_storage.dart';
import 'persist.dart';
import 'progress.dart';
import 'tick.dart';
import 'travel.dart';

/// Smallest background gap treated as time away instead of live frames.
///
/// A lock-screen glance is shorter than one combat round, so those ticks stay
/// live. A longer hide would replay many steps on screen; the next tick
/// batch-resolves like a boot.
num foregroundCatchUpFloorMs(GameDatabase db) {
  return math.max(1000, configNumber(db, 'combat_round_duration', 4) * 1000);
}

/// What a boot found: the save to play, and what happened while away.
class SessionBoot {
  const SessionBoot({required this.save, required this.created, required this.unattended});

  final PlayerSave save;

  /// True when there was no save yet and a fresh character was started.
  final bool created;

  /// The catch-up that ran on the way in, for the "while you were away" panel.
  final UnattendedResult unattended;
}

/// Owns the save and the loop, so a client only has to draw and forward intents.
///
/// Everything time-dependent comes from [clock] and everything random from
/// [random], both injected, so a test drives a session by moving the clock
/// instead of waiting. The rules underneath stay pure: this class is only the
/// place the save, the storage, and the clock are held together.
class GameSession {
  GameSession({
    required this.db,
    required this.repository,
    required this.clock,
    required this.random,
  });

  final GameDatabase db;
  final SaveRepository repository;

  /// Wall clock in milliseconds.
  final num Function() clock;

  final RandomFn random;

  PlayerSave? _save;

  /// Last clock reading that was credited into [PlayerSave.playTimeMs].
  ///
  /// Session-local on purpose: a second persisted timestamp would fight the
  /// unattended anchor. Boot and adopt credit catch-up first, then this is
  /// set so the next live frame does not add that window again.
  num? _playAccruedAt;

  /// The save being played. Throws before [boot], which is what loads it.
  PlayerSave get save {
    final current = _save;
    if (current == null) {
      throw StateError('GameSession has no save yet; call boot() first');
    }
    return current;
  }

  bool get hasSave => _save != null;

  /// Loads or creates the save, credits time away, and stores the result.
  SessionBoot boot() {
    final loaded = repository.loadOrCreate(db);
    final nowMs = clock();
    final unattended = resolveUnattendedProgress(db, loaded.save, nowMs, random);
    // The resolver has already moved the unattended anchor, and deliberately
    // leaves it short when a long absence ran out of steps, so the boot write
    // must not stamp it again.
    final synced = syncProgressionMeta(db, unattended.save, nowMs);
    _save = repository.write(synced);
    _playAccruedAt = nowMs;
    return SessionBoot(save: save, created: loaded.created, unattended: unattended);
  }

  /// Replaces the in-memory save with the account's row and credits time away.
  ///
  /// [nowMs] is the catch-up clock. Hosted play should pass the server's time
  /// so a skewed device clock cannot invent progress.
  SessionBoot adoptAccount(PlayerSave incoming, {num? nowMs}) {
    final at = nowMs ?? clock();
    final unattended = resolveUnattendedProgress(db, incoming, at, random);
    final synced = syncProgressionMeta(db, unattended.save, at);
    _save = repository.write(synced);
    _playAccruedAt = at;
    return SessionBoot(save: save, created: false, unattended: unattended);
  }

  /// Clears the playable character after sign-out or a kick.
  void resetUnsigned() {
    final nowMs = clock();
    _save = repository.write(createNewSave(db, nowMs));
    _playAccruedAt = nowMs;
  }

  /// Advances whatever is due, storing the save only when something happened.
  ///
  /// A client calls this as often as it likes — once a frame, or on a timer —
  /// and applies the returned events. A long pause (tab hide, app switcher)
  /// is batch-resolved like a boot so the UI is not fed one overdue step per
  /// frame.
  SessionTickResult tick() {
    final nowMs = clock();
    final catchUp = _catchUpForegroundGap(nowMs);
    if (catchUp != null) return catchUp;
    _save = _creditLivePlayTime(save, nowMs);
    final result = advanceSession(db, save, nowMs, random);
    if (result.changed) apply(result.save);
    return result;
  }

  /// Batch-resolves a long foreground gap. Returns null when the live tick
  /// should run — including a short lock that is at most one combat round.
  SessionTickResult? _catchUpForegroundGap(num nowMs) {
    final last = _playAccruedAt;
    if (last == null) return null;
    if (nowMs - last <= foregroundCatchUpFloorMs(db)) return null;

    // Catch-up from the last live frame so present time already in playTimeMs
    // is not added again.
    final anchored = stampUnattendedProgressAt(save, last);
    final unattended = resolveUnattendedProgress(db, anchored, nowMs, random);
    final synced = syncProgressionMeta(db, unattended.save, nowMs);
    _save = repository.write(synced);
    _playAccruedAt = nowMs;
    return SessionTickResult(
      save: save,
      changed: unattended.changed,
      events: const [],
      awayCatchUp: unattended,
    );
  }

  /// Stores the result of a player action, whatever rule produced it.
  ///
  /// Intents are the rules functions themselves (`requestActivityStart`,
  /// `buyFromShop`, `equipInventoryIndex`, …); this is where their new save
  /// lands, so no caller can skip the write pipeline.
  PlayerSave apply(PlayerSave next) {
    final nowMs = clock();
    final credited = _creditLivePlayTime(next, nowMs);
    _save = repository.write(prepareSaveForWrite(db, credited, nowMs));
    return save;
  }

  /// Credits the gap since the last live reading, capped like unattended time.
  ///
  /// Also moves the unattended anchor in memory so a pause flush, then a kill,
  /// catch-up from this frame instead of replaying time the player was here.
  PlayerSave _creditLivePlayTime(PlayerSave current, num nowMs) {
    final last = _playAccruedAt;
    _playAccruedAt = nowMs;
    final credited = last == null
        ? current
        : creditElapsedPlayTime(current, nowMs - last, unattendedCapMs(db));
    if (credited.unattendedProgressAt == isoFromMs(nowMs)) return credited;
    return stampUnattendedProgressAt(credited, nowMs);
  }

  /// How far along the action in progress is, from 0 to 1.
  num get actionProgress => actionProgressAt(save, clock());

  /// Milliseconds left of a death pause, or 0 when not recovering.
  num get deathPauseRemaining => deathPauseRemainingMs(save, clock());

  /// Starts travel. An instant arrival is already stored when this returns; a
  /// journey stores the stopped activity and is finished with [arrive].
  TravelPlan travelTo(String destinationId, String browseMapId) {
    final plan = planTravel(db, save, destinationId, browseMapId, clock(), random);
    switch (plan) {
      case TravelBlocked():
        break;
      case TravelInstant(arrival: final arrival):
        apply(arrival.save);
      case TravelTimed(save: final stopped):
        apply(stopped);
    }
    return plan;
  }

  /// Instant travel into this player's guild hall, from anywhere.
  TravelPlan travelToGuildHall() {
    final plan = planGuildHallTravel(db, save, clock(), random);
    switch (plan) {
      case TravelBlocked():
        break;
      case TravelInstant(arrival: final arrival):
        apply(arrival.save);
      case TravelTimed():
        break;
    }
    return plan;
  }

  /// Completes a journey the client has finished animating.
  TravelArrival arrive(String destinationId) {
    final arrival = arriveFromTravel(db, save, destinationId, clock(), random);
    apply(arrival.save);
    return arrival;
  }
}
