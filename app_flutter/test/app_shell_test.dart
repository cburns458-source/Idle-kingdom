import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/game_controller.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/reward_strip.dart';
import 'package:idle_kingdoms/src/ui/app_shell.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

/// The shared content, read from the repo rather than the bundle so the test
/// does not depend on asset loading.
LoadedDatabase loadDatabaseFromRepo() {
  final file = File('../content/data/game-database.json');
  return prepareDatabase(jsonDecode(file.readAsStringSync()));
}

/// A clock the test moves by hand, standing in for the host's wall clock.
class _TestClock {
  num _nowMs = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;

  num read() => _nowMs;

  void advance(num ms) => _nowMs += ms;
}

/// A named human with the starter kit, which is what the activity requirements
/// expect: gathering needs the tools the race grants.
PlayerSave startedCharacter(LoadedDatabase database) {
  final base = createNewSave(database.launch, DateTime.utc(2026, 1, 1).millisecondsSinceEpoch);
  final assigned = assignRace(database.launch, base.copyWith(characterName: 'Tester'), 'RACE-0001');
  return assigned.save!;
}

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  /// A controller over an empty save slot, reading [clock] instead of the host's.
  GameController buildController({PlayerSave? seed, _TestClock? clock}) {
    final testClock = clock ?? _TestClock();
    final repository = SaveRepository(storage: MemorySaveStorage(), clock: testClock.read);
    if (seed != null) repository.write(seed);
    final session = GameSession(
      db: database.launch,
      repository: repository,
      clock: testClock.read,
      random: () => 0,
    );
    final boot = session.boot();
    return GameController(database: database, session: session)..adoptBoot(boot);
  }

  testWidgets('a new save is met with the character sheet', (tester) async {
    final controller = buildController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: AppShell(controller: controller)));

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
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: AppShell(controller: controller)));

    expect(find.text('Meadow'), findsWidgets);
    // The other meadow activity needs a hunting tool, so pick this one by name.
    final gatherCard = find.ancestor(
      of: find.text('Gather meadow supplies'),
      matching: find.byType(GamePanel),
    );
    await tester.tap(find.descendant(of: gatherCard, matching: find.text('Start')));
    await tester.pump();

    expect(controller.save.currentActivityId, 'ACT-0012');
    expect(find.text('Stop'), findsWidgets);

    await tester.tap(find.text('Stop').first);
    await tester.pump();
    expect(controller.save.currentActivityId, isNull);
  });

  testWidgets('the map travels to a chosen location', (tester) async {
    // From the meadow, because the town is a gateway and opens its district map.
    final controller = buildController(
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: AppShell(controller: controller)));

    await tester.tap(find.byTooltip('Map'));
    await tester.pump();
    await tester.tap(find.text('The Farm'));
    await tester.pump();
    await tester.tap(find.text('Travel'));
    await tester.pump();

    expect(controller.save.currentLocationId, 'LOC-0001');
  });

  testWidgets('the loop runs while the shell is on screen', (tester) async {
    final clock = _TestClock();
    final controller = buildController(
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
      clock: clock,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: AppShell(controller: controller)));

    final gatherCard = find.ancestor(
      of: find.text('Gather meadow supplies'),
      matching: find.byType(GamePanel),
    );
    await tester.tap(find.descendant(of: gatherCard, matching: find.text('Start')));
    await tester.pump();

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
    final controller = buildController(seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: AppShell(controller: controller)));

    await tester.tap(find.text('Skills'));
    await tester.pump();
    expect(find.text('Combat'), findsWidgets);

    await tester.tap(find.text('Inventory'));
    await tester.pump();
    expect(find.textContaining('slots'), findsOne);
  });
}
