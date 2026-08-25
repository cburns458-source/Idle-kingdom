import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/game_controller.dart';
import 'package:idle_kingdoms/src/session/multiplayer_controller.dart';
import 'package:idle_kingdoms/src/session/tester_access.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/app_shell.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';
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

/// Email, username, and password for a local test account.
class TestAccount {
  const TestAccount({required this.email, required this.username, required this.password});

  final String email;
  final String username;
  final String password;
}

/// The account every signed-in shell test uses unless it asks for another.
const TestAccount testAccount = TestAccount(
  email: 'test@example.com',
  username: 'Tester',
  password: 'secret',
);

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

/// Registers [account] on the local backend. Does not sign them in.
void registerTestAccount(LocalMultiplayerService service, {TestAccount account = testAccount}) {
  final result = service.backend.signUp(account.email, account.username, account.password);
  if (!result.ok) {
    throw StateError(result.reason ?? 'Could not register ${account.email}.');
  }
}

/// Writes [account]'s session into [storage] after the account already exists.
void restoreTestSession(
  LocalMultiplayerService service,
  SaveStorage storage, {
  TestAccount account = testAccount,
}) {
  final result = service.backend.signIn(account.email, account.password);
  if (!result.ok) {
    throw StateError(result.reason ?? 'Could not sign in ${account.email}.');
  }
  SessionStore(storage).write(result.session);
}

/// A multiplayer controller over the local backend and an in-memory store.
///
/// [testAccount] is always registered first. [signedIn] then restores that
/// session so shell tests play as an existing player, not a guest.
MultiplayerController buildMultiplayer(
  LoadedDatabase database, {
  TestClock? clock,
  bool signedIn = true,
  bool testerAccess = true,
  bool cloudUnavailable = false,
  TestAccount account = testAccount,
}) {
  final testClock = clock ?? TestClock();
  final storage = MemorySaveStorage();
  var ids = 0;
  final service = LocalMultiplayerService(
    storage: storage,
    ports: LocalBackendPorts(
      nowMs: testClock.read,
      newId: (prefix) => '${prefix}_${(ids += 1).toString().padLeft(4, '0')}',
    ),
  );
  service.ensureDemoWorld(database.launch);
  registerTestAccount(service, account: account);
  if (signedIn) {
    restoreTestSession(service, storage, account: account);
  }
  final net = MultiplayerController(
    database: database,
    service: service,
    storage: storage,
    clock: testClock.read,
    cloudUnavailable: cloudUnavailable,
  );
  if (testerAccess) net.unlockTesterAccess(testerPasskey);
  return net;
}

/// Signs the already-registered [account] in through the controller, not the form.
Future<void> signInRegisteredAccount(
  MultiplayerController multiplayer,
  PlayerSave save, {
  TestAccount account = testAccount,
}) async {
  await multiplayer.signIn(account.email, account.password, save, adopt: (save, {nowMs}) {});
  if (!multiplayer.isSignedIn) {
    throw StateError(multiplayer.notice ?? 'Sign-in of ${account.email} failed.');
  }
}

/// Clears a one-shot social OK alert so the shell underneath can be tapped.
Future<void> dismissSocialAlertIfPresent(WidgetTester tester) async {
  await tester.pump();
  final ok = find.text('OK');
  if (ok.evaluate().isEmpty) return;
  await tester.tap(ok);
  await tester.pump();
}

/// The same, over a hosted backend held in memory.
///
/// This is the arrangement a released build runs in when it was given a Supabase
/// project, with the wire replaced rather than the service.
MultiplayerController buildRemoteMultiplayer(
  LoadedDatabase database, {
  required FakeTransport transport,
  TestClock? clock,
  bool testerAccess = true,
}) {
  final testClock = clock ?? TestClock();
  final storage = MemorySaveStorage();
  final service = RemoteMultiplayerService(transport: transport, storage: storage);
  service.local.ensureDemoWorld(database.launch);
  final net = MultiplayerController(
    database: database,
    service: service,
    storage: storage,
    clock: testClock.read,
  );
  if (testerAccess) net.unlockTesterAccess(testerPasskey);
  return net;
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
  final net = multiplayer ?? buildMultiplayer(controller.database);
  if (multiplayer == null) addTearDown(net.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: AppShell(controller: controller, multiplayer: net),
    ),
  );
}

/// Opens a screen that lives in the chin's hamburger nest.
Future<void> openChinScreen(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Open menu'));
  await tester.pump();
  await tester.tap(find.text(label));
  await tester.pump();
}

/// Scrolls [button] into the location dock and taps it.
///
/// Dock rows that sit on the clipped edge of the bottom band have a center
/// that would otherwise land on the nav.
Future<void> tapVisible(WidgetTester tester, Finder button) async {
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pump();
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
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: panel),
    ),
  );
}
