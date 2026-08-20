import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/multiplayer_controller.dart';
import 'package:idle_kingdoms/src/session/tester_access.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/app_shell.dart';
import 'package:idle_kingdoms/src/ui/reward_strip.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  test('the tester passkey is case-insensitive and remembered as the current key', () {
    expect(testerPasskeyRequired(null), isTrue);
    expect(testerPasskeyRequired(testerPasskey), isFalse);
    expect(matchesTesterPasskey('  RESTORIA-TESTERS  '), isTrue);
    expect(matchesTesterPasskey('nope'), isFalse);
  });

  test('resume adopts a named cloud save that still needs a race', () async {
    final transport = FakeTransport();
    final storage = MemorySaveStorage();
    final service = RemoteMultiplayerService(transport: transport, storage: storage);
    final signed = await service.signUp('vari@example.com', 'Vari', 'secret');
    expect(signed.ok, isTrue, reason: signed.reason);

    final cloud = startedCharacter(database)
        .copyWith(characterName: 'Vari', gold: 777, raceId: null);
    await transport.upsert(RemoteTables.saves, <RemoteRow>[
      saveRowFor(service.session!.userId, cloud),
    ]);

    final controller = buildController(database);
    addTearDown(controller.dispose);
    final net = MultiplayerController(
      database: database,
      service: service,
      storage: storage,
      clock: () => testStartMs,
    );
    addTearDown(net.dispose);
    await net.resumeAccount(controller.save, adopt: controller.adoptAccountSave);

    expect(controller.save.characterName, 'Vari');
    expect(controller.save.gold, 777);
    expect(controller.save.raceId, isNull);
    expect(net.mustRestoreCloudSaveBeforeCreate, isFalse);
  });

  testWidgets('a new save asks for an account, then character creation', (tester) async {
    final controller = buildController(database);
    final net = buildMultiplayer(database, signedIn: false);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    await pumpShell(tester, controller, multiplayer: net);

    expect(find.text('Sign in to play'), findsOne);
    expect(find.text('Test launch'), findsNothing);
    expect(find.text('Name your character'), findsNothing);
    expect(find.text('Meadow'), findsNothing);

    await signInRegisteredAccount(net, controller.save);
    await tester.pump();
    await dismissSocialAlertIfPresent(tester);

    expect(find.text('Sign in to play'), findsNothing);
    expect(find.text('Name your character'), findsOne);
    // Nothing to report on a first run.
    expect(find.text('While you were away'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Character name'), 'Tester');
    await tester.tap(find.text('Human'));
    await tester.pump();
    await tester.tap(find.text('Begin'));
    await tester.pump();

    expect(find.text('Name your character'), findsNothing);
    expect(controller.save.characterName, 'Tester');
    expect(controller.save.raceId, isNotNull);
    expect(net.session?.username, 'Tester');
  });

  testWidgets('creating an account names the username at character creation', (tester) async {
    final controller = buildController(database);
    final net = buildMultiplayer(database, signedIn: false);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    await pumpShell(tester, controller, multiplayer: net);

    await tester.enterText(find.byKey(const Key('auth-email')), 'hero@example.com');
    await tester.enterText(find.byKey(const Key('auth-password')), 'secret');
    await tester.tap(find.text('Create account'));
    await tester.pump();
    await tester.pump();
    await dismissSocialAlertIfPresent(tester);

    expect(find.text('Name your character'), findsOne);
    expect(find.widgetWithText(TextField, 'Username'), findsNothing);
    expect(isPendingAccountUsername(net.session!.username), isTrue);

    await tester.enterText(find.widgetWithText(TextField, 'Character name'), 'Rowan');
    await tester.tap(find.text('Human'));
    await tester.pump();
    await tester.tap(find.text('Begin'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Name your character'), findsNothing);
    expect(controller.save.characterName, 'Rowan');
    expect(net.session?.username, 'Rowan');
  });

  testWidgets('a taken character name stays on the create sheet', (tester) async {
    final controller = buildController(database);
    final net = buildMultiplayer(database, signedIn: false);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    await pumpShell(tester, controller, multiplayer: net);

    await tester.enterText(find.byKey(const Key('auth-email')), 'hero@example.com');
    await tester.enterText(find.byKey(const Key('auth-password')), 'secret');
    await tester.tap(find.text('Create account'));
    await tester.pump();
    await tester.pump();
    await dismissSocialAlertIfPresent(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Character name'), 'Tester');
    await tester.tap(find.text('Begin'));
    await tester.pump();
    await tester.pump();
    await dismissSocialAlertIfPresent(tester);

    expect(find.text('That name is taken.'), findsOne);
    expect(find.text('Name your character'), findsOne);
    expect(controller.save.characterName, isNull);
    expect(isPendingAccountUsername(net.session!.username), isTrue);
  });

  testWidgets('a typed URL on a fresh device asks for the tester passkey', (tester) async {
    final controller = buildController(database);
    final net = buildMultiplayer(database, signedIn: false, testerAccess: false);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    await pumpShell(tester, controller, multiplayer: net);

    expect(find.text('Test launch'), findsOne);
    expect(find.text('Enter the tester passkey to create an account or sign in.'), findsOne);
    expect(find.byKey(const Key('tester-passkey')), findsOne);
    expect(find.text('Sign in to play'), findsNothing);
    expect(find.byKey(const Key('auth-email')), findsNothing);
  });

  testWidgets('the tester passkey opens sign-in and stays on this device', (tester) async {
    final controller = buildController(database);
    final net = buildMultiplayer(database, signedIn: false, testerAccess: false);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    await pumpShell(tester, controller, multiplayer: net);

    expect(find.text('Test launch'), findsOne);
    expect(find.text('Sign in to play'), findsNothing);
    expect(find.byKey(const Key('auth-email')), findsNothing);

    await tester.enterText(find.byKey(const Key('tester-passkey')), 'wrong-key');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('That passkey is not right.'), findsOne);
    expect(find.text('Sign in to play'), findsNothing);

    await tester.enterText(find.byKey(const Key('tester-passkey')), testerPasskey);
    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(find.text('Test launch'), findsNothing);
    expect(find.text('Sign in to play'), findsOne);
    expect(find.byKey(const Key('auth-email')), findsOne);
    expect(net.hasTesterAccess, isTrue);
  });

  testWidgets('an unsigned player cannot reach the location screen', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    final net = buildMultiplayer(database, signedIn: false);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    await pumpShell(tester, controller, multiplayer: net);

    expect(find.text('Sign in to play'), findsOne);
    expect(find.text('Gather meadow supplies'), findsNothing);
    expect(find.byTooltip('Open world map'), findsNothing);
    expect(controller.save.currentActivityId, isNull);
  });

  testWidgets('signing in loads the account save and skips character creation', (tester) async {
    final transport = FakeTransport();
    final writer = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(writer.dispose);
    final stored = startedCharacter(database).copyWith(characterName: 'Vari', gold: 777);
    await writer.signUp('vari@example.com', 'Vari', 'secret', stored, adopt: (save, {nowMs}) {});

    final controller = buildController(database);
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    await pumpShell(tester, controller, multiplayer: net);

    await tester.enterText(find.byKey(const Key('auth-email')), 'vari@example.com');
    await tester.enterText(find.byKey(const Key('auth-password')), 'secret');
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Sign in to play'), findsNothing);
    expect(find.text('Name your character'), findsNothing);
    expect(controller.save.characterName, 'Vari');
    expect(controller.save.gold, 777);
  });

  testWidgets('signing out returns to the auth gate', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    await pumpShell(tester, controller, multiplayer: net);

    expect(find.text('Sign in to play'), findsNothing);
    await openChinScreen(tester, 'Settings');
    await tester.ensureVisible(find.text('Sign out'));
    await tester.tap(find.text('Sign out'));
    await tester.pump();
    await tester.pump();

    expect(net.isSignedIn, isFalse);
    expect(find.text('Sign in to play'), findsOne);
    expect(find.text('Gather meadow supplies'), findsNothing);
    expect(controller.save.characterName, isNull);
  });

  testWidgets('signing in on a second device kicks the first', (tester) async {
    final transport = FakeTransport();
    final stored = startedCharacter(database).copyWith(characterName: 'Vari', gold: 50);

    final firstGame = buildController(database, seed: stored);
    final firstNet = buildRemoteMultiplayer(database, transport: transport);
    firstNet.onAccountCleared = firstGame.resetUnsigned;
    addTearDown(firstGame.dispose);
    addTearDown(firstNet.dispose);
    await firstNet.signUp(
      'vari@example.com',
      'Vari',
      'secret',
      stored,
      adopt: firstGame.adoptAccountSave,
    );
    firstNet.startPolling(() => firstGame.save);

    final secondGame = buildController(database);
    final secondNet = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(secondGame.dispose);
    addTearDown(secondNet.dispose);
    await secondNet.signIn(
      'vari@example.com',
      'secret',
      secondGame.save,
      adopt: secondGame.adoptAccountSave,
    );

    await tester.pump(MultiplayerController.pollInterval);
    await tester.pump();

    expect(firstNet.isSignedIn, isFalse);
    expect(firstNet.notice, remoteSignedInElsewhere);
    expect(firstGame.save.characterName, isNull);
    expect(secondNet.isSignedIn, isTrue);
    expect(secondGame.save.characterName, 'Vari');
    firstNet.stopPolling();
    secondNet.stopPolling();
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
    controller.setMapTravelAnimation(false);
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

  testWidgets('map travel walks a sprite, then arrives', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    addTearDown(controller.dispose);
    controller.setMapTravelAnimation(true);
    await pumpShell(tester, controller);

    await tester.tap(find.byTooltip('Open world map'));
    await tester.pump();
    await tester.tap(find.text('The Farm'));
    await tester.pump();
    await tester.tap(find.text('Travel'));
    await tester.pump();

    expect(controller.save.currentLocationId, 'LOC-0009');
    expect(find.bySemanticsLabel('Travelling'), findsOne);

    await tester.pump(const Duration(seconds: 4));
    expect(controller.save.currentLocationId, 'LOC-0001');
    expect(find.text('The Farm'), findsWidgets);
  });

  testWidgets('leaving the map mid-walk cancels travel', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    addTearDown(controller.dispose);
    controller.setMapTravelAnimation(true);
    await pumpShell(tester, controller);

    await tester.tap(find.byTooltip('Open world map'));
    await tester.pump();
    await tester.tap(find.text('The Farm'));
    await tester.pump();
    await tester.tap(find.text('Travel'));
    await tester.pump();
    expect(find.bySemanticsLabel('Travelling'), findsOne);

    await tester.tap(find.text('Inventory'));
    await tester.pump();
    expect(controller.save.currentLocationId, 'LOC-0009');
    expect(find.bySemanticsLabel('Travelling'), findsNothing);
  });

  testWidgets('the map icon always opens the world map', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0023'),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text('Kitchen'), findsWidgets);
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

  testWidgets('the chin nest opens Settings, Log, Leaderboards, and Guilds', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text('Inventory'), findsOne);
    expect(find.text('Skills'), findsOne);
    expect(find.byTooltip('Open menu'), findsOne);
    expect(find.text('Log'), findsNothing);
    expect(find.text('Social'), findsNothing);

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pump();

    expect(find.text('Settings'), findsOne);
    expect(find.text('Log'), findsOne);
    expect(find.text('Leaderboards'), findsOne);
    expect(find.text('Guilds'), findsOne);
    expect(find.text('Account'), findsNothing);

    await tester.tap(find.text('Log'));
    await tester.pump();
    expect(find.text('Skill milestones unlocked on this save.'), findsOne);
  });

  testWidgets('the map travel walk is off until Settings turns it on', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(controller.mapTravelAnimation, isFalse);
    await openChinScreen(tester, 'Settings');
    expect(find.text('Map travel animation'), findsOne);
    expect(find.text('Account'), findsOne);
    expect(find.text('Character'), findsNothing);
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(controller.mapTravelAnimation, isTrue);
  });

  testWidgets('chat opens above the chin with a close control', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byTooltip('Open chat'), findsOne);

    await tester.tap(find.byTooltip('Open chat'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Global'), findsWidgets);
    expect(find.byTooltip('Close chat'), findsWidgets);
    expect(find.byKey(const Key('chat-panel')), findsOne);
    final chatBottom = tester.getBottomLeft(find.byKey(const Key('chat-panel'))).dy;
    final frameHeight = tester.getSize(find.byType(AppShell)).height;
    expect(chatBottom, greaterThan(frameHeight * 0.4));

    await tester.tap(find.widgetWithText(GameButton, 'Close').last);
    await tester.pump();
    expect(find.byKey(const Key('chat-panel')), findsNothing);
  });

  testWidgets('the chat button sits above the map Travel button', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(420, 420 * 16 / 9));

    await tester.tap(find.byTooltip('Open world map'));
    await tester.pump();
    await tester.tap(find.text('The Farm'));
    await tester.pump();

    final chat = tester.getRect(find.byTooltip('Open chat'));
    final travel = tester.getRect(find.bySemanticsLabel('Travel'));
    expect(chat.bottom, lessThanOrEqualTo(travel.top));
  });

  testWidgets('Close pops one page, and a second chin tab replaces the first', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.text('Skills'));
    await tester.pump();
    expect(find.text('Total level'), findsOne);

    await tester.tap(find.text('Inventory'));
    await tester.pump();
    expect(find.textContaining('slots'), findsOne);
    expect(find.text('Total level'), findsNothing);

    await tester.tap(find.widgetWithText(GameButton, 'Close'));
    await tester.pump();
    expect(find.textContaining('slots'), findsNothing);
    expect(find.byTooltip('Open world map'), findsOne);

    await openChinScreen(tester, 'Log');
    expect(find.text('Skill milestones unlocked on this save.'), findsOne);
    await tester.tap(find.widgetWithText(GameButton, 'Close'));
    await tester.pump();
    expect(find.text('Skill milestones unlocked on this save.'), findsNothing);
  });
}
