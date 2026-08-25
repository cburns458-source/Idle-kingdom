import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/multiplayer_controller.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/account_panel.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  Future<void> signIn(MultiplayerController net) async {
    final result = await net.service.signUp('hero@example.com', 'Hero', 'secret');
    expect(result.ok, isTrue);
  }

  testWidgets('nearby at the meadow lists Mira from The Watch', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: demoMiraLocationId),
    );
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await signIn(net);
    await net.refresh(controller.save);
    await pumpShell(tester, controller, multiplayer: net, size: const Size(900, 2400));
    await tester.pump();

    await tester.tap(find.byTooltip('Nearby adventurers'));
    await tester.pump();
    await tester.pump();

    expect(find.text('[WCH]Mira'), findsOne);
    expect(find.textContaining('The Watch'), findsNothing);

    await tester.tap(find.text('[WCH]Mira'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Friend request'), findsOne);
    expect(find.text('Ignore'), findsOne);

    await tester.tap(find.text('Ignore'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Ignored.'), findsOne);
    expect(find.text('OK'), findsOne);
    await tester.tap(find.text('OK'));
    await tester.pump();
    expect(find.text('Unignore'), findsOne);
  });

  testWidgets('guild search shows The Watch, and a recruit can join and leave', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await signIn(net);
    await pumpShell(tester, controller, multiplayer: net, size: const Size(900, 2400));

    await openChinScreen(tester, 'Guilds');
    await tester.pump();

    expect(find.text('[WCH] The Watch'), findsOne);
    await tester.tap(find.text('[WCH] The Watch'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Join'), findsOne);
    await tester.tap(find.text('Join'));
    await tester.pump();
    await tester.pump();
    // Action results are alerts now, not a sticky banner.
    expect(find.text('OK'), findsOne);
    await tester.tap(find.text('OK'));
    await tester.pump();
    await tester.pump();

    // Leave the roster detail; the guild home now owns the panel.
    await tester.tap(find.widgetWithText(GameButton, 'Close'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Mira'), findsWidgets);
    expect(find.textContaining('Bram'), findsWidgets);
    expect(find.textContaining('Kael'), findsWidgets);
    expect(find.text('Leave guild'), findsOne);

    await tester.tap(find.text('Leave guild'));
    await tester.pump();
    await tester.tap(find.text('Leave'));
    await tester.pump();
    await tester.pump();
    expect(find.text('OK'), findsOne);
    await tester.tap(find.text('OK'));
    await tester.pump();
    await tester.pump();

    expect(find.text('[WCH] The Watch'), findsOne);
    await tester.tap(find.text('[WCH] The Watch'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Join'), findsOne);
  });

  testWidgets('guest The Watch without joining the roster', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await signIn(net);
    await pumpShell(tester, controller, multiplayer: net, size: const Size(900, 2400));

    await openChinScreen(tester, 'Guilds');
    await tester.pump();

    expect(find.text('[WCH] The Watch'), findsOne);
    await tester.tap(find.text('[WCH] The Watch'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Guest'), findsOne);
    await tester.tap(find.text('Guest'));
    await tester.pump();
    await tester.pump();
    expect(find.text('OK'), findsOne);
    await tester.tap(find.text('OK'));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.widgetWithText(GameButton, 'Close'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Guest of [WCH] The Watch'), findsOne);
    expect(find.text('Leave guest'), findsOne);
    expect(find.text('Leave guild'), findsNothing);
  });

  testWidgets('Account lists friends and ignored players', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await signIn(net);
    await net.sendFriendRequest(demoMiraId);
    final local = net.service as LocalMultiplayerService;
    local.backend.sendFriendRequest(demoMiraId, net.session!.userId);
    await net.sendFriendRequest(demoMiraId);
    await net.ignorePlayer(demoBramId);
    await net.refresh(controller.save);
    await pumpPanel(
      tester,
      ListenableBuilder(
        listenable: net,
        builder: (context, _) => AccountPanel(controller: controller, multiplayer: net),
      ),
    );

    expect(find.text('Friends'), findsOne);
    expect(find.text('Mira'), findsOne);
    expect(find.textContaining('The Watch ·'), findsOne);
    expect(find.text('Sent requests'), findsNothing);
    expect(find.text('Ignored'), findsOne);
    expect(find.text('Bram'), findsOne);
  });

  testWidgets('Settings Account lists a player after they are ignored', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await signIn(net);
    await net.ignorePlayer(demoBramId);
    net.announce(null);
    await pumpShell(tester, controller, multiplayer: net, size: const Size(900, 2400));

    await openChinScreen(tester, 'Settings');
    await tester.pump(const Duration(milliseconds: 280));
    await tester.tap(find.widgetWithText(GameButton, 'Account'));
    await tester.pump();
    await tester.ensureVisible(find.text('Bram'));

    expect(find.text('Ignored'), findsOne);
    expect(find.text('Bram'), findsOne);
    expect(find.widgetWithText(GameButton, 'Unignore'), findsOne);
  });
}
