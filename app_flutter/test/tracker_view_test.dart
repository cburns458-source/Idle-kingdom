import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/content/asset_paths.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/game_image.dart';
import 'package:idle_kingdoms/src/ui/tracker_view.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  ActionRow action(String id) => database.launch.actions.firstWhere((row) => row.actionId == id);

  EnemyRow enemy(String id) => database.launch.enemies.firstWhere((row) => row.enemyId == id);

  testWidgets('empty tracker tabs explain how to start one', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, TrackerView(controller: controller, kind: TrackerKind.xp));
    expect(find.text('XP'), findsOne);
    expect(find.text('Gain XP to start an XP tracker.'), findsOne);
    expect(find.byKey(const Key('tracker-on-xp')), findsOne);
    expect(find.byKey(const Key('tracker-off-xp')), findsOne);
    expect(find.byKey(const Key('tracker-reset-all-xp')), findsOne);

    await pumpPanel(tester, TrackerView(controller: controller, kind: TrackerKind.loot));
    expect(find.text('Loot'), findsOne);
    expect(find.text('Finish an action to start a loot tracker.'), findsOne);
    expect(find.byKey(const Key('tracker-on-loot')), findsOne);
    expect(find.byKey(const Key('tracker-off-loot')), findsOne);
    expect(find.byKey(const Key('tracker-reset-all-loot')), findsOne);
  });

  testWidgets('combat victory opens a cow loot section that reset can clear', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    final victory = applyCombatVictory(
      database.launch,
      resumeAllTrackers(controller.save, testStartMs),
      action('ACN-0001'),
      enemy('ENM-0001'),
      () => 0,
      testStartMs + 2_000,
    );
    controller.commit(victory.save);

    await pumpPanel(tester, TrackerView(controller: controller, kind: TrackerKind.loot));
    expect(find.text('Cow'), findsOne);
    expect(find.textContaining('kill'), findsOne);
    expect(find.byKey(const Key('tracker-reset-loot-enemy:ENM-0001')), findsOne);
    expect(find.byKey(const Key('tracker-reset-all-loot')), findsOne);

    await tester.tap(find.byKey(const Key('tracker-reset-loot-enemy:ENM-0001')));
    await tester.pump();
    expect(find.text('Cow'), findsNothing);
    expect(find.text('Finish an action to start a loot tracker.'), findsOne);
  });

  testWidgets('XP tab shows total and skill rows after a kill', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    final victory = applyCombatVictory(
      database.launch,
      resumeAllTrackers(controller.save, testStartMs),
      action('ACN-0001'),
      enemy('ENM-0001'),
      () => 0,
      testStartMs + 2_000,
    );
    controller.commit(victory.save);

    await pumpPanel(tester, TrackerView(controller: controller, kind: TrackerKind.xp));
    expect(find.text('Total XP'), findsOne);
    expect(find.text('Might'), findsOne);
    expect(find.textContaining('XP/hr'), findsWidgets);

    final combatRow = find.ancestor(of: find.text('Might'), matching: find.byType(GamePanel)).first;
    final title = tester.getRect(find.descendant(of: combatRow, matching: find.text('Might')));
    final reset = tester.getRect(
      find.descendant(of: combatRow, matching: find.byKey(Key('tracker-reset-xp-$combatSkillId'))),
    );
    final xpText = find.descendant(of: combatRow, matching: find.textContaining('XP/hr'));
    final xpLine = tester.getRect(find.ancestor(of: xpText, matching: find.byType(FittedBox)));
    expect(find.text('🔄'), findsWidgets);
    expect(reset.center.dy, closeTo(title.center.dy, 8));
    expect(xpLine.top, greaterThan(title.bottom - 2));
    expect(xpLine.left, closeTo(title.left, 2));
    expect(xpLine.right, closeTo(reset.right, 8));
    expect(tester.getSize(xpText).height, lessThan(22));

    await tester.tap(find.byKey(const Key('tracker-reset-all-xp')));
    await tester.pump();
    expect(find.text('Gain XP to start an XP tracker.'), findsOne);
  });

  testWidgets('standard production does not open a loot section', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    var save = addItemsToInventory(controller.save, 'ITEM-0025', 10).save;
    save = resumeAllTrackers(save, testStartMs).copyWith(currentLocationId: 'LOC-0023');
    final queued = beginProductionQueue(
      database.launch,
      save,
      'ACT-0017',
      'RCP-0001',
      1,
      testStartMs,
    );
    expect(queued.ok, isTrue);
    final finished = completeProductionCraft(
      database.launch,
      queued.save!,
      testStartMs + 5_000,
      () => 0,
    );
    expect(finished, isNotNull);
    controller.commit(finished!.save);

    await pumpPanel(tester, TrackerView(controller: controller, kind: TrackerKind.xp));
    expect(find.text('Total XP'), findsOne);

    await pumpPanel(tester, TrackerView(controller: controller, kind: TrackerKind.loot));
    expect(find.text('Finish an action to start a loot tracker.'), findsOne);
  });

  testWidgets('gold shows as a drop chip instead of a subtitle count', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    controller.commit(
      creditLootTracker(
        resumeLootTrackers(controller.save, testStartMs),
        'enemy',
        'ENM-0001',
        const <LootGrant>[],
        12,
        testStartMs,
      ),
    );

    await pumpPanel(tester, TrackerView(controller: controller, kind: TrackerKind.loot));
    expect(find.text('Cow'), findsOne);
    expect(find.text('1 kill'), findsOne);
    expect(find.textContaining('kill ·'), findsNothing);
    expect(find.textContaining('Gold ×12'), findsOne);
    expect(find.text('No item drops yet.'), findsNothing);
  });

  testWidgets('loot and XP rows use the requested art', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    final harvest = action('ACN-0035');
    var save = resumeAllTrackers(controller.save, testStartMs);
    save = creditLootTracker(save, 'action', harvest.actionId, const <LootGrant>[], 0, testStartMs);
    save = creditLootTracker(save, 'timer', 'botany:LOC-0001', const <LootGrant>[], 0, testStartMs);
    save = creditXpTracker(save, combatSkillId, 50, testStartMs);
    save = creditXpTracker(save, totalXpTrackerId, 50, testStartMs);
    controller.commit(save);

    await pumpPanel(tester, TrackerView(controller: controller, kind: TrackerKind.loot));
    expect(
      find.byWidgetPredicate(
        (widget) => widget is GameImage && widget.path == actionAssetPath(harvest.actionId),
      ),
      findsOne,
    );
    expect(
      find.byWidgetPredicate((widget) => widget is GameImage && widget.path.contains('skl_botany')),
      findsOne,
    );

    await pumpPanel(tester, TrackerView(controller: controller, kind: TrackerKind.xp));
    final totalRow = find.ancestor(of: find.text('Total XP'), matching: find.byType(GamePanel));
    expect(find.descendant(of: totalRow, matching: find.byType(GameImage)), findsNothing);
    final combatRow = find.ancestor(of: find.text('Might'), matching: find.byType(GamePanel)).first;
    expect(find.descendant(of: combatRow, matching: find.byType(GameImage)), findsOne);
    expect(
      find.byWidgetPredicate((widget) => widget is GameImage && widget.path.contains('skl_might')),
      findsOne,
    );
  });

  testWidgets('On and Off sit next to Reset all on both tracker tabs', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);

    await pumpPanel(tester, TrackerView(controller: controller, kind: TrackerKind.xp));
    expect(find.byKey(const Key('tracker-on-xp')), findsOne);
    expect(find.byKey(const Key('tracker-off-xp')), findsOne);
    expect(find.byKey(const Key('tracker-reset-all-xp')), findsOne);
    expect(xpTrackersPaused(controller.save), isTrue);
    expect(lootTrackersPaused(controller.save), isTrue);

    await tester.tap(find.byKey(const Key('tracker-on-xp')));
    await tester.pump();
    expect(xpTrackersPaused(controller.save), isFalse);
    expect(lootTrackersPaused(controller.save), isTrue);

    await tester.tap(find.byKey(const Key('tracker-off-xp')));
    await tester.pump();
    expect(xpTrackersPaused(controller.save), isTrue);

    await pumpPanel(tester, TrackerView(controller: controller, kind: TrackerKind.loot));
    expect(find.byKey(const Key('tracker-on-loot')), findsOne);
    expect(find.byKey(const Key('tracker-off-loot')), findsOne);
    expect(find.byKey(const Key('tracker-reset-all-loot')), findsOne);

    await tester.tap(find.byKey(const Key('tracker-on-loot')));
    await tester.pump();
    expect(lootTrackersPaused(controller.save), isFalse);
    expect(xpTrackersPaused(controller.save), isTrue);
  });
}
