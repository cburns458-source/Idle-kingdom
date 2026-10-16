import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/tutorial_spotlight.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('tutorial lock hides other places and shows the next-step line', (tester) async {
    final controller = buildController(database, seed: tutorialCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(400, 900));
    await tester.pump();

    expect(isTutorialLocked(controller.save), isTrue);
    expect(find.byType(TutorialHintBar), findsOneWidget);
    expect(find.textContaining('Gather potatoes'), findsOneWidget);
    expect(find.byTooltip('Skills'), findsNothing);
    expect(find.byTooltip('Open menu'), findsNothing);
    expect(find.text('Bank'), findsNothing);
  });

  testWidgets('a finished Getting Started character sees the open world', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0034'),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(400, 900));
    await tester.pump();

    expect(isTutorialLocked(controller.save), isFalse);
    expect(find.byType(TutorialHintBar), findsNothing);
    expect(find.byTooltip('Skills'), findsOneWidget);
    expect(find.byTooltip('Open menu'), findsOneWidget);
  });
}
