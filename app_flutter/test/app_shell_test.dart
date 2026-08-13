import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/reward_strip.dart';
import 'package:ik_content/ik_content.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('a new save is met with the character sheet', (tester) async {
    final controller = buildController(database);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text('Name your character'), findsOne);
    // Nothing to report on a first run.
    expect(find.text('While you were away'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Tester');
    await tester.tap(find.text('Human'));
    await tester.pump();
    await tester.tap(find.text('Begin'));
    await tester.pump();

    expect(find.text('Name your character'), findsNothing);
    expect(controller.save.characterName, 'Tester');
    expect(controller.save.raceId, isNotNull);
  });

  testWidgets('the location screen starts and stops an activity', (tester) async {
    // Standing in the meadow, which has a plain gathering activity.
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text('Meadow'), findsWidgets);
    // The other meadow activity needs a hunting tool, so pick this one by name.
    final gatherCard = find.ancestor(
      of: find.text('Gather meadow supplies'),
      matching: find.byType(DockRow),
    );
    await tapVisible(
      tester,
      find.descendant(of: gatherCard, matching: find.bySemanticsLabel('Start')),
    );

    expect(controller.save.currentActivityId, 'ACT-0012');
    expect(find.text('Stop'), findsWidgets);

    await tapVisible(tester, find.bySemanticsLabel('Stop').first);
    expect(controller.save.currentActivityId, isNull);
  });

  testWidgets('the map travels to a chosen location', (tester) async {
    // From the meadow, because the town is a gateway and opens its district map.
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.byTooltip('Open world map'));
    await tester.pump();
    await tester.tap(find.text('The Farm'));
    await tester.pump();
    await tester.tap(find.text('Travel'));
    await tester.pump();

    expect(controller.save.currentLocationId, 'LOC-0001');
  });

  testWidgets('the map icon opens the district, then the world map', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0023'),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text('Kitchen'), findsWidgets);
    await tester.tap(find.byTooltip('Open world map'));
    await tester.pump();

    expect(find.text('Back to the world map'), findsNothing);
    expect(find.text('The Farm'), findsNothing);
    expect(find.text('Kitchen'), findsWidgets);
    expect(find.byTooltip('Open world map'), findsOne);

    await tester.tap(find.byTooltip('Open world map'));
    await tester.pump();

    expect(find.text('The Farm'), findsOne);
    expect(find.text('Back to the world map'), findsNothing);
  });

  testWidgets('the loop runs while the shell is on screen', (tester) async {
    final clock = TestClock();
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
      clock: clock,
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    final gatherCard = find.ancestor(
      of: find.text('Gather meadow supplies'),
      matching: find.byType(DockRow),
    );
    await tapVisible(
      tester,
      find.descendant(of: gatherCard, matching: find.bySemanticsLabel('Start')),
    );

    final durationMs = controller.save.actionDurationMs!;
    expect(durationMs, greaterThan(0));

    // Move the clock the way the host would, a frame at a time.
    for (var elapsed = 0; elapsed <= durationMs; elapsed += 500) {
      clock.advance(500);
      await tester.pump(const Duration(milliseconds: 500));
    }

    // The action paid out, the next one started, and the strip shows the line.
    expect(controller.recentRewards, isNotEmpty);
    expect(controller.save.skills.fold<num>(0, (sum, skill) => sum + skill.xp), greaterThan(0));
    expect(controller.save.currentActivityId, 'ACT-0012');
    expect(find.byType(RewardStrip), findsOne);
  });

  testWidgets('skills and inventory render', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.text('Inventory'));
    await tester.pump();
    expect(find.textContaining('slots'), findsOne);

    await tester.tap(find.text('Skills'));
    await tester.pump();
    expect(find.text('Combat'), findsWidgets);
  });

  testWidgets('the chin nest opens Menu, Log, Leaderboards, Guilds, and Account', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text('Inventory'), findsOne);
    expect(find.text('Skills'), findsOne);
    expect(find.byTooltip('Open menu nest'), findsOne);
    expect(find.text('Log'), findsNothing);
    expect(find.text('Social'), findsNothing);

    await tester.tap(find.byTooltip('Open menu nest'));
    await tester.pump();

    expect(find.text('Menu'), findsOne);
    expect(find.text('Log'), findsOne);
    expect(find.text('Leaderboards'), findsOne);
    expect(find.text('Guilds'), findsOne);
    expect(find.text('Account'), findsOne);

    await tester.tap(find.text('Log'));
    await tester.pump();
    expect(find.text('Skill milestones unlocked on this save.'), findsOne);
  });

  testWidgets('chat opens from the HUD as a dropdown', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byTooltip('Open chat'), findsOne);

    await tester.tap(find.byTooltip('Open chat'));
    await tester.pump();

    expect(find.text('Chat'), findsOne);
    expect(find.text('Sign in from Menu → Account to use multiplayer features.'), findsOne);
    expect(find.byTooltip('Close chat'), findsOne);
  });
}
