import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:ik_content/ik_content.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('Settings Feedback is a direct entry, not inside a dropdown', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(900, 2400));

    await openChinScreen(tester, 'Settings');

    expect(find.text('Feedback'), findsOne);
    expect(find.text('Report a bug'), findsOne);
    expect(find.text('Share an idea'), findsOne);
    expect(find.text('Open Discord'), findsOne);
    expect(find.text('UI look'), findsNothing);

    await tester.tap(find.text('UI'));
    await tester.pump();
    expect(find.text('UI look'), findsOne);
  });

  testWidgets('Feedback options are parchment on wood, green when selected', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(900, 2400));

    await openChinScreen(tester, 'Settings');
    expect(controller.uiChromePack, UiChromePack.wood);

    final unselected = tester.widget<Text>(find.text('Report a bug'));
    expect(unselected.style?.color, Palette.parchmentText);
    expect(unselected.style?.color, isNot(UiChrome.wood.panelInk));

    await tester.tap(find.widgetWithText(GameTextButton, 'Report a bug'));
    await tester.pump();
    expect(tester.widget<Text>(find.text('Report a bug')).style?.color, Palette.borderSelected);
    expect(tester.widget<Text>(find.text('Share an idea')).style?.color, Palette.parchmentText);
  });

  testWidgets('Feedback options stay parchment on stone, green when selected', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    controller.setUiChromePack(UiChromePack.stone);
    await pumpShell(tester, controller, size: const Size(900, 2400));

    await openChinScreen(tester, 'Settings');
    expect(controller.uiChromePack, UiChromePack.stone);

    expect(tester.widget<Text>(find.text('Share an idea')).style?.color, Palette.parchmentText);
    expect(
      tester.widget<Text>(find.text('Share an idea')).style?.color,
      isNot(UiChrome.stone.panelInk),
    );

    await tester.tap(find.widgetWithText(GameTextButton, 'Share an idea'));
    await tester.pump();
    expect(tester.widget<Text>(find.text('Share an idea')).style?.color, Palette.borderSelected);
    expect(tester.widget<Text>(find.text('Report a bug')).style?.color, Palette.parchmentText);
  });
}
