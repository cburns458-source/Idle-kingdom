import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';
import 'package:test/test.dart';

/// The real shared content, which is also what the parity recorder reads.
GameDatabase contentDatabase() => assertGameDatabaseShape(contentDatabaseJson());

void main() {
  const startMs = 1767225600000; // 2026-01-01T00:00:00.000Z
  const meadowLocationId = 'LOC-0009';
  const meadowActivityId = 'ACT-0012';

  late GameDatabase db;
  late num now;
  late GameSession session;

  setUp(() {
    db = contentDatabase();
    now = startMs;
    session = GameSession(
      db: db,
      repository: SaveRepository(storage: MemorySaveStorage(), clock: () => now),
      clock: () => now,
      // Always takes the first pool entry, so runs are reproducible.
      random: () => 0,
    );
  });

  test('boots a new character and stores it', () {
    final boot = session.boot();
    expect(boot.created, isTrue);
    expect(boot.save.currentLocationId, startingLocationId);
    expect(session.save.toJson(), boot.save.toJson());
    expect(session.repository.read()!.toJson(), boot.save.toJson());
  });

  test('ticks only when something is due, and stores what it advances', () {
    session.boot();
    session.apply(
      beginActivitySave(
        session.save.copyWith(currentLocationId: meadowLocationId),
        meadowActivityId,
        isoFromMs(now),
      ),
    );

    // The first tick rolls an action, the next has nothing to do until it is due.
    expect(session.tick().changed, isTrue);
    expect(session.save.currentActionId, isNotNull);
    expect(session.tick().changed, isFalse);
    expect(session.actionProgress, 0);

    now += session.save.actionDurationMs! / 2;
    expect(session.tick().changed, isFalse);
    expect(session.actionProgress, closeTo(0.5, 0.001));

    now += session.save.actionDurationMs! / 2;
    final due = session.tick();
    expect(due.changed, isTrue);
    expect(due.events.whereType<RewardsEvent>(), isNotEmpty);
    // The advanced save was stored, not just returned.
    expect(session.repository.read()!.toJson(), session.save.toJson());
  });

  test('credits time away on boot', () {
    session.boot();
    session.apply(
      beginActivitySave(
        session.save.copyWith(currentLocationId: meadowLocationId),
        meadowActivityId,
        isoFromMs(now),
      ),
    );
    session.tick();

    // A fresh session over the same storage, an hour later.
    now += 3600000;
    final returning = GameSession(
      db: db,
      repository: session.repository,
      clock: () => now,
      random: () => 0,
    );
    final boot = returning.boot();
    expect(boot.created, isFalse);
    expect(boot.unattended.gatheringActions, greaterThan(0));
    expect(boot.save.unattendedProgressAt, isoFromMs(now));
  });

  test('adoptAccount can catch up on an injected server clock', () {
    session.boot();
    session.apply(
      beginActivitySave(
        session.save.copyWith(currentLocationId: meadowLocationId),
        meadowActivityId,
        isoFromMs(now),
      ),
    );
    session.tick();
    final parked = session.save;

    // Device clock stays put; server time is an hour ahead.
    final serverNow = now + 3600000;
    final adopted = session.adoptAccount(parked, nowMs: serverNow);
    expect(adopted.unattended.gatheringActions, greaterThan(0));
    expect(adopted.save.unattendedProgressAt, isoFromMs(serverNow));
  });

  test('travels instantly on the shipped connections', () {
    session.boot();
    final plan = session.travelTo(meadowLocationId, mainMapId);
    expect(plan, isA<TravelInstant>());
    expect(session.save.currentLocationId, meadowLocationId);
    expect(session.repository.read()!.currentLocationId, meadowLocationId);
  });

  test('refuses to travel while recovering from defeat', () {
    session.boot();
    session.apply(session.save.copyWith(deathPauseUntil: isoFromMs(now + 30000)));
    expect(session.travelTo(meadowLocationId, mainMapId), isA<TravelBlocked>());
    expect(session.save.currentLocationId, startingLocationId);
    expect(session.deathPauseRemaining, 30000);
  });

  test('has no save before boot', () {
    expect(session.hasSave, isFalse);
    expect(() => session.save, throwsStateError);
  });
}
