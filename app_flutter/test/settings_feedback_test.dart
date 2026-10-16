import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/feedback_sheet.dart';
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
    expect(find.text('Report / Suggestion'), findsOne);
    expect(find.text('Report a bug'), findsNothing);
    expect(find.text('Share an idea'), findsNothing);
    expect(find.text('Open Discord'), findsNothing);
    expect(find.text('Join Discord'), findsOne);
    expect(find.text('UI look'), findsNothing);

    await tester.tap(find.text('UI'));
    await tester.pump();
    expect(find.text('UI look'), findsOne);
  });

  testWidgets('Report / Suggestion opens the ADM-04 form', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(900, 2400));

    await openChinScreen(tester, 'Settings');
    await tester.tap(find.text('Report / Suggestion'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FeedbackForm), findsOne);
    expect(find.text('Bug'), findsOne);
    expect(find.text('Suggestion'), findsOne);
    expect(find.text('Player'), findsOne);
    expect(find.text('Send'), findsOne);
  });

  testWidgets('UI look options are parchment on wood, green when selected', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(900, 2400));

    await openChinScreen(tester, 'Settings');
    expect(controller.uiChromePack, UiChromePack.wood);

    await tester.tap(find.text('UI'));
    await tester.pump();

    final selected = tester.widget<Text>(find.text('Wood'));
    expect(selected.style?.color, Palette.successInk);
    expect(contrastRatio(Palette.successInk, Palette.panelTan), greaterThanOrEqualTo(4.5));

    final unselected = tester.widget<Text>(find.text('Stone'));
    expect(unselected.style?.color, UiChrome.wood.panelInk);
  });
}
