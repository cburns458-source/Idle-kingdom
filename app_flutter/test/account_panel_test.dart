import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/multiplayer_controller.dart';
import 'package:idle_kingdoms/src/ui/account_panel.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  Future<void> pumpAccount(WidgetTester tester, MultiplayerController net) async {
    final game = buildController(database, seed: startedCharacter(database));
    addTearDown(game.dispose);
    addTearDown(net.dispose);
    await pumpPanel(
      tester,
      ListenableBuilder(
        listenable: net,
        builder: (context, _) => AccountPanel(controller: game, multiplayer: net),
      ),
    );
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

  testWidgets('a local build says so and offers no magic link', (tester) async {
    final net = buildMultiplayer(database, signedIn: false);
    await pumpAccount(tester, net);

    expect(find.text(multiplayerModeLine(MultiplayerMode.local)), findsOne);
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

    expect(find.text(multiplayerModeLine(MultiplayerMode.supabase)), findsOne);

    final link = find.widgetWithText(OutlinedButton, 'Email magic link');
    expect(tester.widget<OutlinedButton>(link).onPressed, isNull);

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
