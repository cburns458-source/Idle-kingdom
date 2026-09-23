import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('HUD mailbox opens the test letter and marks it read', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    expect(unreadMailCount(controller.save, testStartMs), 2);

    await pumpShell(tester, controller, size: const Size(900, 1600));
    expect(find.byKey(const Key('mailbox-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('mailbox-button')));
    await tester.pump();
    expect(find.text('Mailbox'), findsWidgets);
    expect(find.byKey(const Key('mailbox-row-mail-mailbox-test')), findsOneWidget);

    await tester.tap(find.byKey(const Key('mailbox-row-mail-mailbox-test')));
    await tester.pump();
    expect(
      find.text('This is a test of the kingdom post. Update lists will arrive here.'),
      findsOneWidget,
    );
    expect(
      controller.save.mailbox.where((message) => message.id == mailboxTestCatalogId).single.readAt,
      isNotNull,
    );
    expect(unreadMailCount(controller.save, testStartMs), 1);
  });

  test('claiming mailbox items puts them in the bag', () {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    final gift = MailMessage(
      id: 'mail-gift',
      catalogId: null,
      subject: 'A parcel',
      body: 'Try this.',
      sentAt: isoFromMs(testStartMs),
      readAt: null,
      attachments: const [MailAttachment(itemId: 'ITEM-0025', quantity: 3)],
      claimedAt: null,
    );
    controller.commit(controller.save.copyWith(mailbox: [...controller.save.mailbox, gift]));
    expect(controller.claimMailboxMessage('mail-gift'), 'Items claimed.');
    expect(
      controller.save.inventory.where((stack) => stack.itemId == 'ITEM-0025').first.quantity,
      3,
    );
  });
}
