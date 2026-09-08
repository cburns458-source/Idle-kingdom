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
    final cow = applyCombatVictory(
      db,
      fresh,
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
    final cow = applyCombatVictory(
      db,
      fresh,
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
    final completed = completeGatheringAction(db, fresh, mine, () => 0, 4_000);
    expect(completed.save.lootTrackers.containsKey('action:ACN-0018'), isTrue);
    expect(completed.save.xpTrackers.containsKey('SKL-0002'), isTrue);
    expect(completed.save.xpTrackers.containsKey(totalXpTrackerId), isTrue);
  });

  test('standard production awards XP but not loot items', () {
    var save = addItemsToInventory(fresh, 'ITEM-0025', 10).save;
    save = save.copyWith(currentLocationId: 'LOC-0023');
    final queued = beginProductionQueue(db, save, 'ACT-0017', 'RCP-0001', 1, 1_000);
    expect(queued.ok, isTrue);
    final finished = completeProductionCraft(db, queued.save!, 5_000, () => 0);
    expect(finished, isNotNull);
    expect(finished!.save.lootTrackers, isEmpty);
    expect(finished.save.xpTrackers.containsKey(totalXpTrackerId), isTrue);
  });

  test('xp/hr uses elapsed time since the tracker started', () {
    final entry = XpTrackerEntry(skillId: 'SKL-0001', startedAtMs: 0, xpGained: 3_600);
    expect(xpPerHour(entry, 3_600_000), 3_600);
  });
}
