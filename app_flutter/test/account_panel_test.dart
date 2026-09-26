import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/game_controller.dart';
import 'package:idle_kingdoms/src/session/multiplayer_controller.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/account_panel.dart';
import 'package:idle_kingdoms/src/ui/format.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  Future<GameController> pumpAccount(
    WidgetTester tester,
    MultiplayerController net, {
    PlayerSave? seed,
  }) async {
    final game = buildController(database, seed: seed ?? startedCharacter(database));
    addTearDown(game.dispose);
    addTearDown(net.dispose);
    await pumpPanel(
      tester,
      ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[game, net]),
        builder: (context, _) => AccountPanel(controller: game, multiplayer: net),
      ),
    );
    return game;
  }

  /// Fills the form and presses [button], letting both the call and the repaint
  /// it causes settle.
  Future<void> submit(
    WidgetTester tester,
    String button, {
    String email = 'hero@example.com',
    String password = 'secret',
  }) async {
    await tester.enterText(find.widgetWithText(TextField, 'Email'), email);
    await tester.enterText(find.widgetWithText(TextField, 'Password'), password);
    await tester.pump();
    await tester.tap(find.text(button));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows play time and the day the save was made', (tester) async {
    final net = buildMultiplayer(database, signedIn: false);
    await pumpAccount(
      tester,
      net,
      seed: startedCharacter(database)
          .copyWith(playTimeMs: 3 * 3600000 + 12 * 60000, createdAt: '2026-09-22T10:30:00.000Z'),
    );

    expect(find.text('Play time: 3h 12m'), findsOne);
    expect(find.text('Created: ${formatSaveDate('2026-09-22T10:30:00.000Z')}'), findsOne);
  });

  testWidgets('a save with no written date shows no created line', (tester) async {
    final net = buildMultiplayer(database, signedIn: false);
    await pumpAccount(tester, net, seed: startedCharacter(database).copyWith(createdAt: ''));

    expect(find.textContaining('Created:'), findsNothing);
  });

  testWidgets('a local build says so and offers no magic link', (tester) async {
    final net = buildMultiplayer(database, signedIn: false);
    await pumpAccount(tester, net);

    expect(find.text(multiplayerModeLine(MultiplayerMode.local)), findsNothing);
    expect(find.text('Create account'), findsOne);
    expect(find.widgetWithText(TextField, 'Username'), findsNothing);
    expect(find.text('Email magic link'), findsNothing);
  });

  testWidgets('a hosted build says so and offers a magic link once an email is typed', (
    tester,
  ) async {
    final transport = FakeTransport();
    final net = buildRemoteMultiplayer(database, transport: transport);
    await pumpAccount(tester, net);

    expect(find.text(multiplayerModeLine(MultiplayerMode.supabase)), findsNothing);

    final link = find.widgetWithText(GameButton, 'Email magic link');
    expect(tester.widget<GameButton>(link).onPressed, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'hero@example.com');
    await tester.pump();
    await tester.tap(link);
    await tester.pump();
    await tester.pump();

    expect(transport.magicLinks.single, 'hero@example.com');
    // Notices surface as AppShell alerts; the panel itself only drives the wire.
    expect(net.notice, 'Magic link sent.');
  });

  testWidgets('creating an account against the backend uploads a named leftover', (tester) async {
    final transport = FakeTransport();
    final net = buildRemoteMultiplayer(database, transport: transport);
    await pumpAccount(tester, net);

    await submit(tester, 'Create account');

    expect(net.notice, contains('Account created for'));
    expect(find.text('Signed in as Tester'), findsOne);
    expect(transport.tables[RemoteTables.saves], hasLength(1));
    // First sign-in of the day posts the boards once. The save upload itself does not.
    expect(transport.tables[RemoteTables.leaderboard], isNotEmpty);
  });

  testWidgets('creating an account does one social sync and does not overlap fetches', (
    tester,
  ) async {
    final transport = FakeTransport();
    final net = buildRemoteMultiplayer(database, transport: transport);
    final game = await pumpAccount(tester, net);

    await submit(tester, 'Create account');

    expect(net.notice, contains('Account created'));
    expect(net.hasCompletedSocialRefresh, isTrue);
    expect(
      transport.maxInFlight,
      1,
      reason: 'Signup refresh, ranking, and market must be sequential.',
    );

    final profiles = transport.calls
        .where((call) => call == 'select:${RemoteTables.profiles}')
        .length;
    await net.publishPresence(game.save);
    expect(
      transport.calls.where((call) => call == 'select:${RemoteTables.profiles}').length,
      profiles,
      reason: 'Presence publish must not reload the own-profile row.',
    );
  });

  testWidgets('shows what the backend said when it refused a sign-in', (tester) async {
    final transport = FakeTransport();
    final net = buildRemoteMultiplayer(database, transport: transport);
    await pumpAccount(tester, net);

    await submit(tester, 'Sign in');

    expect(net.notice, 'Invalid login credentials.');
    expect(find.text('Sign in'), findsOne);
  });

  testWidgets('signing out returns to the sign-in form', (tester) async {
    final transport = FakeTransport();
    final net = buildRemoteMultiplayer(database, transport: transport);
    await pumpAccount(tester, net);
    await submit(tester, 'Create account');

    await tester.tap(find.text('Sign out'));
    await tester.pump();
    await tester.pump();

    expect(net.notice, 'Signed out.');
    expect(transport.signedOut, isTrue);
    expect(find.widgetWithText(TextField, 'Email'), findsOne);
  });
}
