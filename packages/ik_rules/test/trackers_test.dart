import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;
  late PlayerSave fresh;

  setUpAll(() {
    db = filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));
  });

  setUp(() {
    fresh = createNewSave(db, 1_000);
  });

  ActionRow action(String id) => db.actions.firstWhere((row) => row.actionId == id);

  EnemyRow enemy(String id) => db.enemies.firstWhere((row) => row.enemyId == id);

  test('cow and bull open separate loot sections', () {
    final tracking = resumeAllTrackers(fresh, 1_000);
    final cow = applyCombatVictory(
      db,
      tracking,
      action('ACN-0001'),
      enemy('ENM-0001'),
      () => 0,
      2_000,
    );
    final both = applyCombatVictory(
      db,
      cow.save,
      action('ACN-0002'),
      enemy('ENM-0002'),
      () => 0,
      3_000,
    );
    expect(both.save.lootTrackers.keys, containsAll(['enemy:ENM-0001', 'enemy:ENM-0002']));
    expect(both.save.lootTrackers['enemy:ENM-0001']!.completions, 1);
    expect(both.save.lootTrackers['enemy:ENM-0002']!.completions, 1);
  });

  test('resetting cows leaves the bull section', () {
    final tracking = resumeAllTrackers(fresh, 1_000);
    final cow = applyCombatVictory(
      db,
      tracking,
      action('ACN-0001'),
      enemy('ENM-0001'),
      () => 0,
      2_000,
    );
    final both = applyCombatVictory(
      db,
      cow.save,
      action('ACN-0002'),
      enemy('ENM-0002'),
      () => 0,
      3_000,
    );
    final reset = resetLootTracker(both.save, 'enemy:ENM-0001');
    expect(reset.lootTrackers.containsKey('enemy:ENM-0001'), isFalse);
    expect(reset.lootTrackers.containsKey('enemy:ENM-0002'), isTrue);
  });

  test('gathering starts an action loot section and XP tracker', () {
    final mine = action('ACN-0018');
    final completed = completeGatheringAction(
      db,
      resumeAllTrackers(fresh, 1_000),
      mine,
      () => 0,
      4_000,
    );
    expect(completed.save.lootTrackers.containsKey('action:ACN-0018'), isTrue);
    expect(completed.save.xpTrackers.containsKey('SKL-0002'), isTrue);
    expect(completed.save.xpTrackers.containsKey(totalXpTrackerId), isTrue);
  });

  test('standard production awards XP but not loot items', () {
    var save = addItemsToInventory(fresh, 'ITEM-0025', 10).save;
    save = resumeAllTrackers(save, 1_000).copyWith(currentLocationId: 'LOC-0023');
    final queued = beginProductionQueue(db, save, 'ACT-0017', 'RCP-0001', 1, 1_000);
    expect(queued.ok, isTrue);
    final finished = completeProductionCraft(db, queued.save!, 5_000, () => 0);
    expect(finished, isNotNull);
    expect(finished!.save.lootTrackers, isEmpty);
    expect(finished.save.xpTrackers.containsKey(totalXpTrackerId), isTrue);
  });

  test('new saves start with loot and XP tracking off', () {
    expect(lootTrackersPaused(fresh), isTrue);
    expect(xpTrackersPaused(fresh), isTrue);
    final mined = completeGatheringAction(db, fresh, action('ACN-0018'), () => 0, 4_000);
    expect(mined.save.lootTrackers.containsKey('action:ACN-0018'), isFalse);
    expect(mined.save.xpTrackers.containsKey('SKL-0002'), isFalse);
  });

  test('loot and XP pause independently', () {
    var save = pauseLootTrackers(resumeAllTrackers(fresh, 1_000), 1_000);
    final mined = completeGatheringAction(db, save, action('ACN-0018'), () => 0, 4_000);
    expect(mined.save.lootTrackers.containsKey('action:ACN-0018'), isFalse);
    expect(mined.save.xpTrackers.containsKey('SKL-0002'), isTrue);

    save = resumeLootTrackers(pauseXpTrackers(mined.save, 4_000), 4_000);
    final again = completeGatheringAction(db, save, action('ACN-0018'), () => 0, 6_000);
    expect(again.save.lootTrackers.containsKey('action:ACN-0018'), isTrue);
    expect(
      again.save.xpTrackers['SKL-0002']!.xpGained,
      mined.save.xpTrackers['SKL-0002']!.xpGained,
    );
  });

  test('xp/hr uses elapsed time since the tracker started', () {
    final entry = XpTrackerEntry(skillId: 'SKL-0001', startedAtMs: 0, xpGained: 3_600);
    expect(xpPerHour(entry, 3_600_000), 3_600);
  });

  test('off freezes xp/hr and on excludes the paused window', () {
    final runningSave = resumeAllTrackers(fresh, 1_000);
    final mined = completeGatheringAction(db, runningSave, action('ACN-0018'), () => 0, 4_000);
    final running = xpPerHour(mined.save.xpTrackers['SKL-0002']!, 10_000, mined.save);
    final paused = pauseXpTrackers(mined.save, 10_000);
    expect(xpTrackersPaused(paused), isTrue);
    expect(xpPerHour(paused.xpTrackers['SKL-0002']!, 20_000, paused), running);
    final resumed = resumeXpTrackers(paused, 20_000);
    expect(xpTrackersPaused(resumed), isFalse);
    expect(xpPerHour(resumed.xpTrackers['SKL-0002']!, 20_000, resumed), running);
  });
}
