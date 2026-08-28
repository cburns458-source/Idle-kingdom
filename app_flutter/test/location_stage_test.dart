import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/game_controller.dart';
import 'package:idle_kingdoms/src/ui/action_stage.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/production_panel.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  Finder dockRow(String title) {
    return find.ancestor(of: find.text(title), matching: find.byType(DockRow));
  }

  bool assetNamed(Widget widget, String needle) {
    if (widget is! Image) return false;
    final image = widget.image;
    return image is AssetImage && image.assetName.contains(needle);
  }

  testWidgets('gathering shows the two-column stage and action art', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tapVisible(
      tester,
      find.descendant(
        of: dockRow('Gather meadow supplies'),
        matching: find.bySemanticsLabel('Start'),
      ),
    );

    expect(controller.save.currentActivityId, 'ACT-0012');
    expect(find.byType(ActionStage), findsOne);
    expect(find.bySemanticsLabel('Gathering'), findsOne);
    expect(find.bySemanticsLabel('Adventurer'), findsWidgets);
    expect(find.byWidgetPredicate((widget) => assetNamed(widget, '/actions/')), findsOne);
    expect(find.bySemanticsLabel('Action progress'), findsOne);

    final stage = tester.getRect(find.byType(ActionStage));
    final player = tester.getRect(find.bySemanticsLabel('Adventurer').first);
    final action = tester.getRect(
      find.byWidgetPredicate((widget) => assetNamed(widget, '/actions/')),
    );
    expect(player.height, 152);
    expect(player.top - stage.top, closeTo(4, 1));
    expect(action.height, 152);
    final playerArt = tester.getRect(
      find.descendant(of: find.bySemanticsLabel('Adventurer').first, matching: find.byType(Image)),
    );
    expect(playerArt.height, 137);
  });

  testWidgets('combat keeps the player at 152 and does not shrink the enemy', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0001'),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tapVisible(
      tester,
      find.descendant(of: dockRow('Tend the pasture'), matching: find.bySemanticsLabel('Start')),
    );

    final stage = tester.getRect(find.byType(ActionStage));
    final player = tester.getRect(find.bySemanticsLabel('Adventurer').first);
    final enemy = tester.getRect(
      find.byWidgetPredicate((widget) => assetNamed(widget, '/enemies/')),
    );
    expect(player.height, 152);
    expect(player.top - stage.top, closeTo(4, 1));
    expect(enemy.height, 152);
    final playerArt = tester.getRect(
      find.descendant(of: find.bySemanticsLabel('Adventurer').first, matching: find.byType(Image)),
    );
    expect(playerArt.height, 137);
  });

  testWidgets('the farm plate runs behind the activities band', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0001'),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(420, 420 * 16 / 9));

    final plate = tester.getRect(
      find.byWidgetPredicate((widget) => assetNamed(widget, 'loc_farm.webp')),
    );
    final activities = tester.getRect(find.text('Activities'));
    expect(plate.bottom, greaterThan(activities.bottom));
  });

  testWidgets('combat shows the enemy on the right with both HP bars', (tester) async {
    final clock = TestClock();
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0001'),
      clock: clock,
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tapVisible(
      tester,
      find.descendant(of: dockRow('Tend the pasture'), matching: find.bySemanticsLabel('Start')),
    );

    expect(controller.save.currentActivityId, 'ACT-0001');
    expect(controller.save.combatEnemyId, isNotNull);
    final enemy = getEnemy(database.launch, controller.save.combatEnemyId!);
    expect(enemy, isNotNull);
    expect(find.byType(ActionStage), findsOne);
    expect(find.bySemanticsLabel('Combat'), findsOne);
    expect(find.text(enemy!.displayName), findsWidgets);
    expect(find.byWidgetPredicate((widget) => assetNamed(widget, '/enemies/')), findsOne);
    expect(find.bySemanticsLabel('Player health'), findsOne);
    expect(find.bySemanticsLabel('${enemy.displayName} health'), findsOne);
    expect(find.bySemanticsLabel('Round progress'), findsOne);

    clock.advance(configNumber(database.launch, 'combat_round_duration', 4) * 1000);
    controller.tick();
    await tester.pump();

    expect(controller.lastRound, isNotNull);
    expect(controller.lastRound!.playerHit, greaterThan(0));
    expect(controller.showLastRoundFloaters, isTrue);
    expect(find.textContaining('${controller.lastRound!.playerHit.round()}'), findsWidgets);

    clock.advance(GameController.combatFloaterHoldMs);
    controller.tick();
    await tester.pump();
    expect(controller.showLastRoundFloaters, isFalse);
  });

  testWidgets('a finished craft pops the item over the workstation', (tester) async {
    final clock = TestClock();
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(
        currentLocationId: 'LOC-0023',
        inventory: const [InventoryStack(itemId: 'ITEM-0025', quantity: 3)],
      ),
      clock: clock,
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(900, 2400));

    await tapVisible(
      tester,
      find.descendant(
        of: dockRow('Cook at the kitchen'),
        matching: find.bySemanticsLabel('Recipes'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(ProductionPicker), findsOne);
    expect(find.byKey(const Key('game-popup')), findsOne);

    await tester.tap(find.text('Max'));
    await tester.pump();
    await tester.tap(find.text('Start queue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(controller.save.currentActivityId, 'ACT-0017');
    expect(find.byType(ActionStage), findsOne);
    expect(find.bySemanticsLabel('Production'), findsOne);
    expect(find.byWidgetPredicate((widget) => assetNamed(widget, '/workstations/')), findsOne);

    final durationMs = controller.save.actionDurationMs ?? 20000;
    final step = foregroundCatchUpFloorMs(database.launch);
    var left = durationMs;
    while (left > 0 && controller.craftPopup == null) {
      final chunk = left > step ? step : left;
      clock.advance(chunk);
      controller.tick();
      await tester.pump();
      left -= chunk;
    }

    expect(controller.craftPopup, isNotNull);
    expect(controller.craftPopup!.displayName, 'Baked Potato');
    expect(find.byKey(ValueKey('craft-pop-${controller.craftPopup!.seq}')), findsOne);

    clock.advance(GameController.craftPopupHoldMs);
    controller.tick();
    await tester.pump();
    expect(controller.craftPopup, isNull);
    expect(find.byKey(const ValueKey('craft-pop-1')), findsNothing);
  });

  testWidgets('a victory eat floats the heal over the player', (tester) async {
    final clock = TestClock();
    final base = startedCharacter(database);
    final controller = buildController(
      database,
      seed: base.copyWith(
        currentLocationId: 'LOC-0001',
        currentHp: 20,
        equipment: EquipmentLoadout(
          slots: {
            ...base.equipment.slots,
            foodSlotId: const EquippedStack(itemId: 'ITEM-0058', quantity: 3),
          },
        ),
      ),
      clock: clock,
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tapVisible(
      tester,
      find.descendant(of: dockRow('Tend the pasture'), matching: find.bySemanticsLabel('Start')),
    );

    final roundMs = configNumber(database.launch, 'combat_round_duration', 4) * 1000;
    for (var i = 0; i < 40 && controller.healPopup == null; i++) {
      clock.advance(roundMs);
      controller.tick();
      await tester.pump();
    }

    expect(controller.healPopup, isNotNull);
    expect(find.byKey(ValueKey('heal-${controller.healPopup!.seq}')), findsOne);
    expect(find.text('+${controller.healPopup!.amount.round()}'), findsNWidgets(2));

    clock.advance(GameController.healPopupHoldMs);
    controller.tick();
    await tester.pump();
    expect(controller.healPopup, isNull);
  });

  testWidgets('a second activity offers Replace while one is running', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.byTooltip('Open world map'), findsOne);

    await tapVisible(
      tester,
      find.descendant(
        of: dockRow('Gather meadow supplies'),
        matching: find.bySemanticsLabel('Start'),
      ),
    );

    expect(
      find.descendant(
        of: dockRow('Search for small game'),
        matching: find.bySemanticsLabel('Replace'),
      ),
      findsOne,
    );
  });

  testWidgets('death pause says Recovering and greys travel and new actions', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(
        currentLocationId: 'LOC-0009',
        currentActivityId: 'ACT-0012',
        deathPauseUntil: isoFromMs(testStartMs + 30000),
      ),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text('Recovering…'), findsWidgets);
    expect(find.bySemanticsLabel('Resume progress'), findsWidgets);
    expect(find.textContaining('Resuming in'), findsNothing);
    expect(find.text('resting'), findsNothing);
    expect(find.text('Dead'), findsNothing);

    expect(
      tester.getSemantics(
        find.descendant(
          of: dockRow('Gather meadow supplies'),
          matching: find.bySemanticsLabel('Stop'),
        ),
      ),
      isSemantics(label: 'Stop', isButton: true, isEnabled: false),
    );
    expect(
      tester.getSemantics(
        find.descendant(
          of: dockRow('Search for small game'),
          matching: find.bySemanticsLabel('Replace'),
        ),
      ),
      isSemantics(label: 'Replace', isButton: true, isEnabled: false),
    );

    await tester.tap(find.byTooltip('Open world map'));
    await tester.pump();
    await tester.tap(find.text('The Farm'));
    await tester.pump();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Travel')),
      isSemantics(label: 'Travel', isButton: true, isEnabled: false),
    );
    expect(controller.save.currentLocationId, 'LOC-0009');

    await tester.tap(find.text('Character'));
    await tester.pump();
    await tester.tap(find.widgetWithText(GameButton, 'Inventory'));
    await tester.pump();
    expect(find.textContaining('slots'), findsOne);
  });

  testWidgets('a killing blow keeps sprites and damage up, then shows defeated', (tester) async {
    final clock = TestClock();
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0001'),
      clock: clock,
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tapVisible(
      tester,
      find.descendant(of: dockRow('Tend the pasture'), matching: find.bySemanticsLabel('Start')),
    );
    expect(controller.save.combatEnemyId, isNotNull);

    controller.commit(controller.save.copyWith(combatEnemyHp: 1));
    clock.advance(configNumber(database.launch, 'combat_round_duration', 4) * 1000);
    await tester.pump();

    expect(controller.lastRound?.outcome, 'victory');
    expect(controller.combatBlowHold, isTrue);
    expect(find.text('defeated'), findsNothing);
    expect(find.textContaining('${controller.lastRound!.playerHit.round()}'), findsWidgets);
    expect(find.byWidgetPredicate((widget) => assetNamed(widget, '/enemies/')), findsOne);

    clock.advance(GameController.combatBlowHoldMs);
    await tester.pump();
    expect(controller.defeatedFlash, isTrue);
    expect(find.text('defeated'), findsOne);

    clock.advance(GameController.combatDefeatedBannerMs);
    await tester.pump();
    expect(controller.defeatedFlash, isFalse);
    expect(find.text('defeated'), findsNothing);
  });

  testWidgets('a death blow keeps sprites up, then says Recovering', (tester) async {
    final clock = TestClock();
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0001', currentHp: 1),
      clock: clock,
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tapVisible(
      tester,
      find.descendant(of: dockRow('Tend the pasture'), matching: find.bySemanticsLabel('Start')),
    );
    expect(controller.save.combatEnemyId, isNotNull);

    controller.commit(controller.save.copyWith(currentHp: 1, combatEnemyHp: 50000));
    clock.advance(configNumber(database.launch, 'combat_round_duration', 4) * 1000);
    await tester.pump();

    expect(controller.lastRound?.outcome, 'defeat');
    expect(controller.showingDeathHold, isTrue);
    expect(find.bySemanticsLabel('Combat'), findsOne);
    expect(find.bySemanticsLabel('Recovering'), findsNothing);
    expect(find.textContaining('${controller.lastRound!.playerHit.round()}'), findsWidgets);

    clock.advance(GameController.combatBlowHoldMs);
    await tester.pump();
    expect(controller.showingDeathHold, isFalse);
    expect(find.bySemanticsLabel('Recovering'), findsOne);
    expect(find.bySemanticsLabel('Resume progress'), findsWidgets);
  });
}
