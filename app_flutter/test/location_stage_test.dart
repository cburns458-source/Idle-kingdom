import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/action_stage.dart';
import 'package:idle_kingdoms/src/ui/pixel_chrome.dart';
import 'package:idle_kingdoms/src/ui/production_panel.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  Finder dockRow(String title) {
    return find.ancestor(of: find.text(title), matching: find.byType(PixelFill));
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
    await tester.pump();

    expect(controller.lastRound, isNotNull);
    expect(controller.lastRound!.playerHit, greaterThan(0));
    expect(find.textContaining('${controller.lastRound!.playerHit.round()}'), findsWidgets);
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
    expect(find.byType(ProductionPicker), findsOne);

    await tester.tap(find.text('Max'));
    await tester.pump();
    await tester.tap(find.text('Start queue'));
    await tester.pump();

    expect(controller.save.currentActivityId, 'ACT-0017');
    expect(find.byType(ActionStage), findsOne);
    expect(find.bySemanticsLabel('Production'), findsOne);
    expect(find.byWidgetPredicate((widget) => assetNamed(widget, '/workstations/')), findsOne);

    final durationMs = controller.save.actionDurationMs ?? 20000;
    clock.advance(durationMs);
    await tester.pump();

    expect(controller.craftPopup, isNotNull);
    expect(controller.craftPopup!.displayName, 'Baked Potato');
    expect(find.byKey(ValueKey('craft-pop-${controller.craftPopup!.seq}')), findsOne);
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
}
