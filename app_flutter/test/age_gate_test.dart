import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';

import 'package:idle_kingdoms/src/ui/age_gate_sheet.dart';
import 'package:idle_kingdoms/src/ui/app_shell.dart';
import 'package:idle_kingdoms/src/ui/chat_sheet.dart';
import 'package:idle_kingdoms/src/ui/player_profile_sheet.dart';

import 'support/harness.dart';

void main() {
  final database = loadDatabaseFromRepo();

  testWidgets('new and existing accounts are asked for age before the name step', (tester) async {
    final controller = buildController(database);
    final transport = FakeTransport();
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);

    await pumpPanel(tester, AppShell(controller: controller, multiplayer: net));

    expect(find.text('Sign in to play'), findsOneWidget);
    transport.seedAccount(email: 'hero@example.com', username: 'Hero');
    await net.signIn(
      'hero@example.com',
      'secret',
      controller.save,
      adopt: controller.adoptAccountSave,
    );
    transport.setAccountStatus(net.session!.userId, const AccountSocialStatus.unanswered());
    await net.refreshAccountStatus();
    await tester.pump();

    expect(find.byType(AgeGateSheet), findsOneWidget);
    expect(find.byKey(const Key('age-year')), findsOneWidget);
    expect(find.text(ageGateTitle), findsNothing);
    expect(find.text('Name your character'), findsNothing);
    expect(find.text('Chat'), findsNothing);
  });

  testWidgets('the year dropdown submits once and hides chat for under-13', (tester) async {
    final controller = buildController(database);
    final transport = FakeTransport();
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    transport.seedAccount(email: 'kid@example.com', username: 'Kid');
    await net.signIn(
      'kid@example.com',
      'secret',
      controller.save,
      adopt: controller.adoptAccountSave,
    );
    transport.setAccountStatus(net.session!.userId, const AccountSocialStatus.unanswered());
    await net.refreshAccountStatus();

    await pumpPanel(tester, AgeGateSheet(multiplayer: net));
    expect(find.byKey(const Key('age-year')), findsOneWidget);
    expect(find.byKey(const Key('age-month')), findsNothing);
    expect(find.text(ageGateTitle), findsNothing);
    expect(find.text(ageGateBody), findsNothing);

    await tester.tap(find.byKey(const Key('age-year')));
    await tester.pumpAndSettle();
    final year = DateTime.now().toUtc().year;
    await tester.tap(find.text('$year').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(net.accountStatus.ageAnswered, isTrue);
    expect(net.chatAllowed, isFalse);
  });

  testWidgets('under-13 accounts hide chat, DMs, and friend requests', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    final transport = FakeTransport();
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    transport.seedAccount(email: 'kid@example.com', username: 'Kid');
    await net.signIn(
      'kid@example.com',
      'secret',
      controller.save,
      adopt: controller.adoptAccountSave,
    );
    transport.setAccountStatus(
      net.session!.userId,
      const AccountSocialStatus(ageAnswered: true, chatAllowed: false),
    );
    await net.refreshAccountStatus();

    await pumpPanel(
      tester,
      ChatSheet(
        controller: controller,
        multiplayer: net,
        locationId: controller.save.currentLocationId,
        citadelHub: false,
        onClose: () {},
      ),
    );
    expect(find.text(ageGateChatHidden), findsNothing);
    expect(find.text('Chat is off for this account.'), findsNothing);
    expect(find.text('Global'), findsNothing);

    transport.seedAccount(email: 'mira@example.com', username: 'Mira', userId: 'usr_mira');
    await pumpPanel(
      tester,
      PlayerProfileSheet(controller: controller, multiplayer: net, userId: 'usr_mira'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Friend request'), findsNothing);
    expect(find.text('Private message'), findsNothing);
    expect(find.text('Ignore'), findsOneWidget);
  });

  testWidgets('the month dropdown appears only for the year that cannot settle 13', (tester) async {
    final controller = buildController(database);
    final transport = FakeTransport();
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    transport.seedAccount(email: 'teen@example.com', username: 'Teen');
    await net.signIn(
      'teen@example.com',
      'secret',
      controller.save,
      adopt: controller.adoptAccountSave,
    );
    transport.setAccountStatus(net.session!.userId, const AccountSocialStatus.unanswered());
    await net.refreshAccountStatus();

    final nowYear = DateTime.now().toUtc().year;
    await pumpPanel(
      tester,
      AgeGateSheet(key: const Key('age-settled'), multiplayer: net, initialYear: nowYear - 14),
    );
    expect(find.byKey(const Key('age-month')), findsNothing);

    await pumpPanel(
      tester,
      AgeGateSheet(key: const Key('age-borderline'), multiplayer: net, initialYear: nowYear - 13),
    );
    expect(find.byKey(const Key('age-month')), findsOneWidget);
    expect(find.text('Birth month'), findsOneWidget);
    expect(find.textContaining('optional'), findsNothing);
    expect(find.textContaining('skip'), findsNothing);
    expect(find.textContaining('December'), findsNothing);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(net.accountStatus.ageAnswered, isTrue);
    expect(net.chatAllowed, isFalse);
  });

  testWidgets('picking a month on the borderline year uses that month', (tester) async {
    final controller = buildController(database);
    final transport = FakeTransport();
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    transport.seedAccount(email: 'born@example.com', username: 'Born');
    await net.signIn(
      'born@example.com',
      'secret',
      controller.save,
      adopt: controller.adoptAccountSave,
    );
    transport.setAccountStatus(net.session!.userId, const AccountSocialStatus.unanswered());
    await net.refreshAccountStatus();

    await pumpPanel(
      tester,
      AgeGateSheet(multiplayer: net, initialYear: DateTime.now().toUtc().year - 13),
    );
    await tester.tap(find.byKey(const Key('age-month')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('January').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(net.accountStatus.ageAnswered, isTrue);
    expect(net.chatAllowed, isTrue);
  });
}
