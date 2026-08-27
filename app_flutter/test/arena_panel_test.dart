import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/app_shell.dart';
import 'package:idle_kingdoms/src/ui/action_stage.dart';
import 'package:idle_kingdoms/src/ui/arena_panel.dart';
import 'package:idle_kingdoms/src/ui/location_view.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('offers the arena at the Citadel plaza and hides it in the Meadow', (tester) async {
    final plaza = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: citadelPlazaId),
    );
    addTearDown(plaza.dispose);
    await pumpPanel(
      tester,
      LocationView(controller: plaza, multiplayer: buildMultiplayer(database), onOpenMap: () {}),
      size: const Size(900, 2400),
    );
    await tester.tap(find.widgetWithText(GameButton, 'Arena'));
    await tester.pump();
    expect(find.text('Player fights'), findsOne);

    final meadow = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    addTearDown(meadow.dispose);
    await pumpPanel(
      tester,
      LocationView(controller: meadow, multiplayer: buildMultiplayer(database), onOpenMap: () {}),
    );
    expect(find.text('Player fights'), findsNothing);
  });

  testWidgets('keeps the training grounds peaceful and shops the Armory', (tester) async {
    final grounds = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0032'),
    );
    addTearDown(grounds.dispose);
    await pumpPanel(
      tester,
      LocationView(controller: grounds, multiplayer: buildMultiplayer(database), onOpenMap: () {}),
      size: const Size(900, 2400),
    );
    expect(find.text('Player fights'), findsNothing);
    expect(find.text('Challenge the guards'), findsOne);
    await tester.tap(find.widgetWithText(GameButton, 'Shops'));
    await tester.pump();
    expect(find.text('Armory'), findsOne);
  });

  testWidgets('search finds Mira by name and ranked picks Bram by combat level', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);

    await pumpPanel(tester, ArenaPanel(controller: controller, multiplayer: net));
    await tester.pump();
    await tester.pump();

    expect(find.text('Save equipment'), findsOne);
    await tester.tap(find.text('Ranked'));
    await tester.pump();
    await tester.tap(find.text('Find match'));
    await tester.pump();
    expect(find.text('Save equipment first.'), findsOne);

    await tester.tap(find.text('Search'));
    await tester.pump();
    await tester.tap(find.text('Save equipment'));
    await tester.pump();
    expect(
      find.text('Loadout saved. Others will fight this gear at your current combat level.'),
      findsOne,
    );

    await tester.enterText(find.byType(TextField), 'mi');
    await tester.pump();
    expect(find.text('Mira'), findsOne);

    await tester.tap(find.text('Ranked'));
    await tester.pump();
    final goldBefore = controller.save.gold;
    await tester.tap(find.text('Find match'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Bram'), findsWidgets);
    if (find.text('Skip').evaluate().isNotEmpty) {
      await tester.tap(find.text('Skip'));
      await tester.pump();
    }
    expect(
      find.text('Victory').evaluate().isNotEmpty || find.text('Defeat').evaluate().isNotEmpty,
      isTrue,
    );
    expect(controller.save.rankedPvpFightsToday, 1);
    expect(
      controller.save.gold,
      goldBefore + (controller.save.rankedPvpWins > 0 ? rankedPvpWinGold : 0),
    );
    expect(controller.save.rankedPvpWins + controller.save.rankedPvpLosses, 1);
  });

  testWidgets('arena search sits above the keyboard', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: citadelPlazaId),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(900, 2400));

    await tapVisible(tester, find.byTooltip('Expand list'));
    await tester.tap(find.widgetWithText(GameButton, 'Arena'));
    await tester.pump();
    await tapVisible(
      tester,
      find.descendant(
        of: find.ancestor(of: find.text('Player fights'), matching: find.byType(DockRow)),
        matching: find.widgetWithText(GameButton, 'Arena'),
      ),
    );
    await tester.pump();
    expect(find.byType(ArenaPanel), findsOne);

    final field = find.byKey(const Key('arena-search-field'));
    expect(field, findsOne);
    await tester.tap(field);
    await tester.pump();

    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();

    expect(field, findsOne);
    final fieldBox = tester.getRect(field);
    final frame = tester.getRect(find.byType(AppShell));
    expect(fieldBox.bottom, lessThanOrEqualTo(frame.bottom - 280 + 2));
    expect(fieldBox.top, greaterThan(frame.top));
  });

  testWidgets('arena opponent art is mirrored toward the player', (tester) async {
    final look = startedCharacter(database).appearance;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PvpActionStage(
            youName: 'You',
            themName: 'Them',
            youAppearance: look,
            themAppearance: look,
            youHp: 10,
            youMaxHp: 10,
            themHp: 10,
            themMaxHp: 10,
            roundProgress: 0,
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate((widget) {
        if (widget is! Transform) return false;
        return widget.transform.storage[0] < 0;
      }),
      findsOne,
    );
  });
}
