import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';

import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/account_panel.dart';
import 'package:idle_kingdoms/src/ui/delete_account_page.dart';
import 'package:idle_kingdoms/src/ui/delete_account_sheet.dart';
import 'package:idle_kingdoms/src/ui/format.dart';
import 'package:idle_kingdoms/src/ui/restore_account_sheet.dart';

import 'support/harness.dart';

void main() {
  final database = loadDatabaseFromRepo();

  test('the Google Play web path is /delete-account', () {
    expect(isDeleteAccountPath(Uri.parse('https://restoriaidle.com/delete-account')), isTrue);
    expect(isDeleteAccountPath(Uri.parse('https://test.restoriaidle.com/play')), isFalse);
  });

  testWidgets('Settings shows a red delete control that asks for re-auth and the name', (
    tester,
  ) async {
    final controller = buildController(database, seed: startedCharacter(database));
    final transport = FakeTransport();
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    transport.seedAccount(email: 'hero@example.com', username: 'Tester');
    await net.signIn(
      'hero@example.com',
      'secret',
      controller.save,
      adopt: controller.adoptAccountSave,
    );

    await pumpPanel(tester, AccountPanel(controller: controller, multiplayer: net, embedded: true));
    expect(find.byKey(const Key('delete-account')), findsOneWidget);
    expect(
      tester.widget<GameButton>(find.byKey(const Key('delete-account'))).tone,
      GameButtonTone.danger,
    );

    await pumpPanel(
      tester,
      DeleteAccountSheet(controller: controller, multiplayer: net, embedded: true),
    );
    expect(find.text(deleteAccountGraceLine), findsOneWidget);
    expect(find.textContaining('Cancelled Bazaar'), findsNothing);
    await tester.enterText(find.byKey(const Key('delete-reauth-password')), 'secret');
    await tester.tap(find.text('Sign in again'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<GameButton>(find.byKey(const Key('delete-account-confirm'))).onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const Key('delete-character-name')), 'Tester');
    await tester.pump();
    expect(
      tester.widget<GameButton>(find.byKey(const Key('delete-account-confirm'))).onPressed,
      isNotNull,
    );
    expect(
      tester.widget<GameButton>(find.byKey(const Key('delete-account-confirm'))).tone,
      GameButtonTone.danger,
    );
    await tester.tap(find.byKey(const Key('delete-account-confirm')));
    await tester.pumpAndSettle();
    expect(transport.pendingDeletions, isNotEmpty);
  });

  testWidgets('a pending deletion shows Restore account', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    final transport = FakeTransport();
    final net = buildRemoteMultiplayer(database, transport: transport);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    transport.seedAccount(email: 'hero@example.com', username: 'Tester');
    await net.signIn(
      'hero@example.com',
      'secret',
      controller.save,
      adopt: controller.adoptAccountSave,
    );
    transport.pendingDeletions[net.session!.userId] = DateTime.utc(2026, 10, 31);
    await net.refreshAccountStatus();

    await pumpPanel(tester, RestoreAccountSheet(multiplayer: net));
    expect(find.text(restoreAccountTitle), findsWidgets);
    expect(find.text(formatLocalDay(DateTime.utc(2026, 10, 31))), findsOneWidget);
    expect(find.textContaining('Cancelled Bazaar'), findsNothing);
    await tester.tap(find.byKey(const Key('restore-account')));
    await tester.pumpAndSettle();
    expect(net.deletionPending, isFalse);
  });

  testWidgets('the standalone web page signs in then deletes', (tester) async {
    final controller = buildController(database);
    final net = buildMultiplayer(database, signedIn: false);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    await pumpPanel(tester, DeleteAccountPage(controller: controller, multiplayer: net));
    expect(find.text('Delete a Restoria account'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
  });
}
