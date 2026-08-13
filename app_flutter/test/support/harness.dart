import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/game_controller.dart';
import 'package:idle_kingdoms/src/session/multiplayer_controller.dart';
import 'package:idle_kingdoms/src/ui/app_shell.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

/// The start of 2026, the instant every test's clock begins at.
final num testStartMs = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;

/// The shared content, read from the repo rather than the bundle so the tests do
/// not depend on asset loading.
LoadedDatabase loadDatabaseFromRepo() {
  final file = File('../content/data/game-database.json');
  return prepareDatabase(jsonDecode(file.readAsStringSync()));
}

/// A clock the test moves by hand, standing in for the host's wall clock.
class TestClock {
  TestClock({num? startMs}) : _nowMs = startMs ?? testStartMs;

  num _nowMs;

  num read() => _nowMs;

  void advance(num ms) => _nowMs += ms;
}

/// A named human with the starter kit, which is what activity requirements
/// expect: gathering needs the tools the race grants.
PlayerSave startedCharacter(LoadedDatabase database) {
  final base = createNewSave(database.launch, testStartMs);
  final assigned = assignRace(database.launch, base.copyWith(characterName: 'Tester'), 'RACE-0001');
  return assigned.save!;
}

/// A booted controller over an in-memory save slot and a clock the test drives.
GameController buildController(LoadedDatabase database, {PlayerSave? seed, TestClock? clock}) {
  final testClock = clock ?? TestClock();
  final repository = SaveRepository(storage: MemorySaveStorage(), clock: testClock.read);
  if (seed != null) repository.write(seed);
  final session = GameSession(
    db: database.launch,
    repository: repository,
    clock: testClock.read,
    // Always takes the first pool entry, so runs are reproducible.
    random: () => 0,
  );
  final boot = session.boot();
  return GameController(database: database, session: session)..adoptBoot(boot);
}

/// A multiplayer controller over the local backend and an in-memory store, so a
/// shell test gets the social screens without a network or a signed-in account.
MultiplayerController buildMultiplayer(LoadedDatabase database, {TestClock? clock}) {
  final testClock = clock ?? TestClock();
  final storage = MemorySaveStorage();
  return MultiplayerController(
    database: database,
    service: LocalMultiplayerService(storage: storage),
    storage: storage,
    clock: testClock.read,
  );
}

/// Pumps the whole shell, which is how a panel is reached the way a player does.
Future<void> pumpShell(
  WidgetTester tester,
  GameController controller, {
  MultiplayerController? multiplayer,
  Size? size,
}) async {
  // The location screen is a lazy list, so a test that reaches for something far
  // down it needs a window tall enough to have built that far.
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    MaterialApp(
      home: AppShell(
        controller: controller,
        multiplayer: multiplayer ?? buildMultiplayer(controller.database),
      ),
    ),
  );
}

/// Pumps one panel on its own, for panels a player opens from a location.
///
/// The surface is made tall because these panels are built to scroll inside the
/// location screen, and the default 800×600 test window would leave their
/// buttons off-screen and unhittable.
Future<void> pumpPanel(
  WidgetTester tester,
  Widget panel, {
  Size size = const Size(900, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: panel)));
}
