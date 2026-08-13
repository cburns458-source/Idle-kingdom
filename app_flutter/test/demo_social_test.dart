import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/multiplayer_controller.dart';
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
    await signIn(net);
    await pumpShell(tester, controller, multiplayer: net);
    await tester.pump();

    await tester.tap(find.byTooltip('Nearby adventurers'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Mira'), findsOne);
    expect(find.textContaining('The Watch'), findsWidgets);

    await tester.tap(find.text('Mira'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Friend request'), findsOne);
    expect(find.text('Ignore'), findsOne);
  });

  testWidgets('guild search shows The Watch, and a recruit can join and leave', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    await signIn(net);
    await pumpShell(tester, controller, multiplayer: net, size: const Size(900, 2400));

    await openChinScreen(tester, 'Guilds');
    await tester.pump();

    expect(find.text('[WCH] The Watch'), findsOne);
    await tester.tap(find.text('Join'));
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

    expect(find.text('[WCH] The Watch'), findsOne);
    expect(find.text('Join'), findsOne);
  });

  testWidgets('Account lists friends and ignored players', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    await signIn(net);
    await net.sendFriendRequest(demoMiraId);
    await net.ignorePlayer(demoBramId);
    await pumpShell(tester, controller, multiplayer: net, size: const Size(900, 2400));

    await openChinScreen(tester, 'Account');
    await tester.pump();
    await tester.pump();

    expect(find.text('Friends'), findsOne);
    expect(find.text('Sent requests'), findsOne);
    expect(find.text('Mira'), findsOne);
    expect(find.text('Ignored'), findsOne);
    expect(find.text('Bram'), findsOne);
  });
}
