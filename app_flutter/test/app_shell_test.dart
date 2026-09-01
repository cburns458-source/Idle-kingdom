import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/battery_saver_pref.dart';
import 'package:idle_kingdoms/src/session/game_controller.dart';
import 'package:idle_kingdoms/src/session/multiplayer_controller.dart';
import 'package:idle_kingdoms/src/session/tester_access.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/app_shell.dart';
import 'package:idle_kingdoms/src/ui/menu_view.dart';
import 'package:idle_kingdoms/src/ui/reward_strip.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';
import 'package:ik_rules/ik_rules.dart';
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

  testWidgets('a local build does not claim the cloud is unavailable', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    await pumpShell(tester, controller, multiplayer: net);

    expect(find.text('Cloud unavailable — progress is not syncing.'), findsNothing);
  });

  testWidgets('a hosted backend that cannot be reached shows a banner', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    final net = buildMultiplayer(database, cloudUnavailable: true);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    await pumpShell(tester, controller, multiplayer: net);

    expect(find.text('Cloud unavailable — progress is not syncing.'), findsOne);
  });

  testWidgets('a full bag while crafting shows a pause toast', (tester) async {
    var seed = startedCharacter(database).copyWith(currentLocationId: 'LOC-0023');
    seed = addItemToInventory(seed, 'ITEM-0025', 5);
    final queued = beginProductionQueue(
      database.launch,
      seed,
      'ACT-0017',
      'RCP-0001',
      2,
      testStartMs,
    );
    expect(queued.ok, isTrue);
    final filled = queued.save!.copyWith(
      inventory: [for (var i = 0; i < 180; i++) InventoryStack(itemId: 'FILL-$i', quantity: 1)],
    );
    final controller = buildController(database, seed: filled);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text('Inventory full — free a slot to keep crafting.'), findsOne);
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
    await tester.tap(find.widgetWithText(GameButton, 'Account'));
    await tester.pump();
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

  testWidgets('a short lock stays live and a two-minute hide is covered', (tester) async {
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
    controller.tick();
    await tester.pump();

    clock.advance(2000);
    controller.tick();
    await tester.pump();
    expect(find.text('Returning to your adventure…'), findsNothing);
    expect(controller.returningFromAway, isFalse);

    clock.advance(2 * 60 * 1000);
    controller.tick();
    await tester.pump();
    expect(find.text('Returning to your adventure…'), findsOne);
    expect(controller.returningFromAway, isTrue);
    expect(controller.recentRewards, isEmpty);
    expect(find.textContaining('hit'), findsNothing);

    await tester.pump(const Duration(milliseconds: GameController.returningHoldMs));
    expect(find.text('Returning to your adventure…'), findsNothing);
    expect(find.text('While you were away'), findsOne);
  });

  testWidgets('the map travels to a chosen location', (tester) async {
    // From the meadow, so the destination is a world-map node rather than a landing.
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

    await tester.tap(find.text('Character'));
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

    await tester.tap(find.text('Character'));
    await tester.pump();
    expect(find.textContaining('slots'), findsOne);

    await tester.tap(find.widgetWithText(GameButton, 'Skills'));
    await tester.pump();
    expect(find.text('Combat'), findsWidgets);

    await tester.tap(find.widgetWithText(GameButton, 'Inventory'));
    await tester.pump();
    expect(find.textContaining('slots'), findsOne);

    await tester.tap(find.widgetWithText(GameButton, 'Equipment'));
    await tester.pump();
    expect(find.textContaining('slots'), findsNothing);
    expect(find.text('Sell items'), findsNothing);
    expect(find.text('Damage'), findsOne);
    expect(find.text('Health'), findsOne);
    expect(find.text('DR'), findsOne);
    expect(find.text('Helmet'), findsOne);
    expect(find.text('Show bonuses'), findsOne);
  });

  testWidgets('the chin nest opens Settings, Log, Leaderboards, and Guilds', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text('Character'), findsOne);
    expect(find.text('Skills'), findsNothing);
    expect(find.text('Inventory'), findsNothing);
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
    expect(find.text('Deeds unlocked on this save.'), findsOne);
  });

  testWidgets('the map travel walk is off until Settings turns it on', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(controller.mapTravelAnimation, isFalse);
    await openChinScreen(tester, 'Settings');
    await tester.tap(find.text('UI'));
    await tester.pump();
    expect(find.text('Map travel animation'), findsOne);
    expect(find.text('Account'), findsOne);
    expect(
      find.descendant(of: find.byType(MenuView), matching: find.text('Character')),
      findsNothing,
    );
    await tester.tap(_settingsSwitch('Map travel animation'));
    await tester.pump();
    expect(controller.mapTravelAnimation, isTrue);
  });

  test('battery saver stays on this device', () {
    final storage = MemorySaveStorage();
    final pref = BatterySaverPref.load(storage);
    expect(pref.enabled, isFalse);

    pref.setEnabled(true);
    expect(pref.enabled, isTrue);
    expect(storage.getItem(BatterySaverPref.storageKey), '1');
    expect(BatterySaverPref.load(storage).enabled, isTrue);

    pref.setEnabled(false);
    expect(pref.enabled, isFalse);
    expect(storage.getItem(BatterySaverPref.storageKey), '0');
  });

  testWidgets('Settings turns battery saver on and the plaque opens Settings', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(controller.batterySaver, isFalse);
    expect(find.byKey(const Key('battery-saver-plaque')), findsNothing);

    await openChinScreen(tester, 'Settings');
    await tester.tap(find.text('UI'));
    await tester.pump();
    expect(find.text('Battery saver'), findsOne);
    expect(find.text('Skip animations and refresh the screen less often.'), findsOne);
    await tester.tap(_settingsSwitch('Battery saver'));
    await tester.pump();
    expect(controller.batterySaver, isTrue);
    expect(controller.reduceMotion, isTrue);

    await tester.tap(find.widgetWithText(GameButton, 'Close'));
    await tester.pump();
    expect(find.byKey(const Key('battery-saver-plaque')), findsOne);

    await tester.tap(find.byKey(const Key('battery-saver-plaque')));
    await tester.pump();
    await tester.tap(find.text('UI'));
    await tester.pump();
    expect(find.text('Skip animations and refresh the screen less often.'), findsOne);
    expect(find.byKey(const Key('battery-saver-plaque')), findsNothing);

    await tester.tap(_settingsSwitch('Map travel animation'));
    await tester.pump();
    expect(controller.mapTravelAnimation, isFalse);

    await tester.tap(_settingsSwitch('Battery saver'));
    await tester.pump();
    expect(controller.batterySaver, isFalse);

    await tester.tap(find.widgetWithText(GameButton, 'Close'));
    await tester.pump();
    expect(find.byKey(const Key('battery-saver-plaque')), findsNothing);
  });

  testWidgets('battery saver arrives from the map immediately', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    addTearDown(controller.dispose);
    controller.setMapTravelAnimation(true);
    controller.setBatterySaver(true);
    await pumpShell(tester, controller);

    expect(find.byKey(const Key('battery-saver-plaque')), findsOne);

    await tester.tap(find.byTooltip('Open world map'));
    await tester.pump();
    await tester.tap(find.text('The Farm'));
    await tester.pump();
    await tester.tap(find.text('Travel'));
    await tester.pump();

    expect(controller.save.currentLocationId, 'LOC-0001');
    expect(find.bySemanticsLabel('Travelling'), findsNothing);
    expect(find.text('The Farm'), findsWidgets);
  });

  testWidgets('the loop still runs under battery saver', (tester) async {
    final clock = TestClock();
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
      clock: clock,
    );
    addTearDown(controller.dispose);
    controller.setBatterySaver(true);
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

    for (var elapsed = 0; elapsed <= durationMs; elapsed += 500) {
      clock.advance(500);
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(controller.recentRewards, isNotEmpty);
    expect(controller.save.skills.fold<num>(0, (sum, skill) => sum + skill.xp), greaterThan(0));
    expect(controller.save.currentActivityId, 'ACT-0012');
    expect(find.byType(RewardStrip), findsOne);
  });

  testWidgets('a wide window docks chat beside a full-height 9:16 column', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(1920, 1080));
    await tester.pump();

    expect(find.byTooltip('Open chat'), findsNothing);
    expect(find.byKey(const Key('chat-panel')), findsOne);
    expect(find.byTooltip('Close chat'), findsNothing);
    final frame = tester.getSize(find.byType(AppShell));
    expect(frame.height, 1080);
    expect(tester.getSize(find.byKey(const Key('chat-panel'))).width, greaterThan(300));
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
    final travel = tester.getRect(find.widgetWithText(GameButton, 'Travel'));
    expect(chat.bottom, lessThanOrEqualTo(travel.top));
  });

  testWidgets('Close pops one page, and a second chin tab replaces the first', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.text('Character'));
    await tester.pump();
    expect(find.textContaining('slots'), findsOne);
    expect(find.text('Total level'), findsNothing);

    await tester.tap(find.widgetWithText(GameButton, 'Skills'));
    await tester.pump();
    expect(find.text('Total level'), findsOne);

    await tester.tap(find.widgetWithText(GameButton, 'Inventory'));
    await tester.pump();
    expect(find.textContaining('slots'), findsOne);
    expect(find.text('Total level'), findsNothing);

    await tester.tap(find.widgetWithText(GameButton, 'Close'));
    await tester.pump();
    expect(find.textContaining('slots'), findsNothing);
    expect(find.byTooltip('Open world map'), findsOne);

    await openChinScreen(tester, 'Log');
    expect(find.text('Deeds unlocked on this save.'), findsOne);
    await tester.tap(find.widgetWithText(GameButton, 'Close'));
    await tester.pump();
    expect(find.text('Deeds unlocked on this save.'), findsNothing);
  });

  testWidgets('Fennel dimmed welcome does not start Getting Started', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(hasSeenFennelIntro: false),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text('Fennel'), findsOne);
    expect(find.textContaining('Welcome to the lands'), findsOne);
    expect(getQuestProgress(controller.save, 'QST-0006').status, 'inactive');

    await tester.tap(find.text('OK'));
    await tester.pump();

    expect(controller.save.hasSeenFennelIntro, isTrue);
    expect(find.textContaining('Welcome to the lands'), findsNothing);
    expect(getQuestProgress(controller.save, 'QST-0006').status, 'inactive');
    await tester.tap(find.widgetWithText(GameButton, 'People'));
    await tester.pump();
    expect(find.text('Fennel'), findsOne);
  });
}

Finder _settingsSwitch(String title) {
  return find.descendant(
    of: find.ancestor(of: find.text(title), matching: find.byType(GamePanel)),
    matching: find.byType(GameSwitch),
  );
}
