import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';

import 'package:idle_kingdoms/src/ui/age_gate_sheet.dart';
import 'package:idle_kingdoms/src/ui/app_shell.dart';

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

    expect(find.text(ageGateTitle), findsOneWidget);
    expect(find.text('Name your character'), findsNothing);
    expect(find.text('Chat'), findsNothing);
  });

  testWidgets('the age picker submits once and hides chat for under-13', (tester) async {
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
    expect(find.text(ageGateTitle), findsOneWidget);

    await tester.enterText(find.byKey(const Key('age-year')), '2015');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(net.accountStatus.ageAnswered, isTrue);
    expect(net.chatAllowed, isFalse);
  });
}
