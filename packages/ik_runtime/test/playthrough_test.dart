import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';
import 'package:test/test.dart';

/// The release check: one character, played through the shipped content.
///
/// Everything goes through [GameSession], which is what a client has, so this
/// covers the write pipeline as well as the rules — a step that forgot to store
/// its result fails here rather than on someone's phone. The clock is moved by
/// hand, so the whole absence-free playthrough runs in milliseconds.
GameDatabase contentDatabase() => assertGameDatabaseShape(contentDatabaseJson());

void main() {
  const startMs = 1767225600000; // 2026-01-01T00:00:00.000Z
  const pasture = 'LOC-0001';
  const meadow = 'LOC-0009';
  const townKitchen = 'LOC-0023';
  const gatheringActivity = 'ACT-0012';
  const combatActivity = 'ACT-0001';
  const cookingActivity = 'ACT-0017';
  const bakedPotatoRecipe = 'RCP-0001';
  const potato = 'ITEM-0025';

  late GameDatabase db;
  late num now;
  late MemorySaveStorage storage;
  late GameSession session;

  setUp(() {
    db = contentDatabase();
    now = startMs;
    storage = MemorySaveStorage();
    session = GameSession(
      db: db,
      repository: SaveRepository(storage: storage, clock: () => now),
      clock: () => now,
      // Always the first pool entry and the low end of every roll, so the
      // playthrough takes the same path every run.
      random: () => 0,
    );
  });

  /// Runs the loop until [ready] holds, moving the clock the way a player waits.
  ///
  /// The step is a plain five seconds rather than a computed due time: a tick
  /// resolves at most one thing, so waiting in small steps is how a client
  /// actually gets there, and it does not need to know what is pending.
  List<SessionEvent> playUntil(bool Function() ready, {int limit = 400}) {
    final events = <SessionEvent>[];
    for (var pass = 0; pass < limit; pass++) {
      events.addAll(session.tick().events);
      if (ready()) return events;
      now += 5000;
    }
    fail('the game never reached the state this step was waiting for');
  }

  /// Travels to [locationId] the way a player would: browsing the map it is on.
  void travelTo(String locationId) {
    final location = db.locations.firstWhereOrNull((row) => row.locationId == locationId);
    final mapId = location!.raw['Map ID'] as String;
    session.travelTo(locationId, mapId);
    expect(session.save.currentLocationId, locationId);
  }

  test('a new character can be started, named, and sworn to a race', () {
    final boot = session.boot();
    expect(boot.created, isTrue);
    expect(boot.save.saveVersion, saveVersion);
    expect(boot.save.currentLocationId, startingLocationId);
    expect(boot.save.characterName, isNull);

    session.apply(session.save.copyWith(characterName: 'ReleaseCheck'));
    final sworn = assignRace(db, session.save, 'RACE-0001');
    expect(sworn.ok, isTrue);
    expect(sworn.grantedStarterKit, isTrue);
    session.apply(sworn.save!);

    // The kit is what the gathering activities below need, and it arrived with
    // the race rather than being handed out separately.
    expect(session.save.inventory, isNotEmpty);
    expect(session.repository.read()!.characterName, 'ReleaseCheck');
  });

  test('travel, gathering, combat, and cooking all pay out through the session', () {
    session.boot();
    session.apply(assignRace(db, session.save, 'RACE-0001').save!);

    // Travel on the shipped connections.
    travelTo(meadow);

    // Gathering: one action, credited with xp and something to carry.
    final started = requestActivityStart(db, session.save, gatheringActivity, now, () => 0);
    expect(started.ok, isTrue, reason: started.reason);
    session.apply(started.save!);
    final gathered = playUntil(() => session.save.currentActionId != null && _paidOut(session));
    expect(gathered.whereType<RewardsEvent>(), isNotEmpty);
    expect(totalSkillXp(session.save), greaterThan(0));

    // Combat: the player attacks first, and the round is resolved by the tick
    // that it comes due in rather than after any animation.
    travelTo(pasture);
    final fighting = requestActivityStart(db, session.save, combatActivity, now, () => 0);
    expect(fighting.ok, isTrue, reason: fighting.reason);
    session.apply(fighting.save!);
    final fought = playUntil(() => _fightResolved(session));
    expect(fought.whereType<CombatRoundEvent>(), isNotEmpty);
    expect(
      fought.any((event) => event is EnemyDefeatedEvent || event is PlayerDefeatedEvent),
      isTrue,
    );

    // Standard production: queued, timed, and stored as it completes.
    travelTo(townKitchen);
    session.apply(addItemToInventory(session.save, potato, 5));
    final cooking = requestProductionStart(
      db,
      session.save,
      cookingActivity,
      bakedPotatoRecipe,
      1,
      now,
    );
    expect(cooking.ok, isTrue, reason: cooking.reason);
    session.apply(cooking.save!);
    final cooked = playUntil(() => session.save.productionRecipeId == null);
    expect(cooked.whereType<CraftCompletedEvent>(), isNotEmpty);
    expect(inventoryCount(session.save, 'ITEM-0058'), greaterThan(0));
  });

  test('a shop in town can be reached, and quests and achievements keep up', () {
    session.boot();
    session.apply(assignRace(db, session.save, 'RACE-0001').save!);

    final store = db.shops.firstWhereOrNull((shop) => shop.shopId == 'SHP-0001') ?? db.shops.first;
    travelTo(store.raw['Location ID'] as String);
    expect(canAccessShop(db, session.save, store).ok, isTrue);

    // Every write catches the meta up, so a boot never has to.
    expect(asQuestRows(db), isNotEmpty);
    expect(achievementRows(db), isNotEmpty);
    expect(session.save.statistics.values['total_level'], totalLevel(session.save));
    expect(session.save.statistics.values['total_experience'], totalSkillXp(session.save));
    expect(getQuestProgress(session.save, 'QST-0001').questId, 'QST-0001');
  });

  test('the save that was played is the save that comes back', () {
    session.boot();
    session.apply(
      assignRace(
        db,
        session.save,
        'RACE-0001',
      ).save!.copyWith(characterName: 'ReleaseCheck', gold: 25),
    );

    // A second launch over the same storage, a minute later.
    now += 60000;
    final returning = GameSession(
      db: db,
      repository: SaveRepository(storage: storage, clock: () => now),
      clock: () => now,
      random: () => 0,
    );
    final boot = returning.boot();
    expect(boot.created, isFalse);
    expect(boot.save.characterName, 'ReleaseCheck');
    expect(boot.save.gold, 25);
    expect(boot.save.saveVersion, saveVersion);
  });
}

/// Whether the current action has been resolved and the next one rolled.
bool _paidOut(GameSession session) => totalSkillXp(session.save) > 0;

bool _fightResolved(GameSession session) =>
    session.save.combatEnemyId == null || session.deathPauseRemaining > 0;
