import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
