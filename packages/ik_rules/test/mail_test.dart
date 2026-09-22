import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;
  final nowMs = DateTime.utc(2026, 9, 22, 12).millisecondsSinceEpoch;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  MailMessage giftMail({List<MailAttachment> attachments = const <MailAttachment>[]}) {
    return MailMessage(
      id: 'mail-gift',
      catalogId: null,
      subject: 'A parcel',
      body: 'Try this.',
      sentAt: isoFromMs(nowMs),
      readAt: null,
      attachments: attachments,
      claimedAt: null,
    );
  }

  test('delivers the test letter to a new save', () {
    final save = createNewSave(db, nowMs);
    expect(save.mailbox.map((message) => message.id), contains(mailboxTestCatalogId));
    expect(unreadMailCount(save, nowMs), 1);
    expect(visibleMailbox(save, nowMs).first.attachments, isEmpty);
  });

  test('stays after it is read and is not delivered twice', () {
    final save = createNewSave(db, nowMs);
    final read = markMailRead(save, mailboxTestCatalogId, nowMs);
    expect(
      read.mailbox.where((message) => message.id == mailboxTestCatalogId).first.readAt,
      isoFromMs(nowMs),
    );
    expect(unreadMailCount(read, nowMs), 0);
    expect(syncSystemMail(read, nowMs).mailbox.length, save.mailbox.length);
  });

  test('drops letters 90 days after they were sent', () {
    final save = createNewSave(db, nowMs);
    final later = nowMs + mailboxTtlMs;
    expect(pruneExpiredMail(save, later).mailbox, isEmpty);
    expect(syncSystemMail(save, later).mailbox, isEmpty);
  });

  test('claims attached items into the bag or refuses when the bag is full', () {
    final base = createNewSave(db, nowMs);
    final withGift = base.copyWith(
      mailbox: [
        giftMail(attachments: const [MailAttachment(itemId: 'ITEM-0025', quantity: 3)]),
      ],
    );
    final claimed = claimMailAttachments(withGift, 'mail-gift', nowMs, db);
    expect(claimed.ok, isTrue);
    expect(claimed.save!.inventory.where((stack) => stack.itemId == 'ITEM-0025').first.quantity, 3);
    expect(claimed.save!.mailbox.first.claimedAt, isoFromMs(nowMs));
    expect(claimMailAttachments(claimed.save!, 'mail-gift', nowMs, db).ok, isFalse);

    final full = withGift.copyWith(
      inventory: [
        for (var index = 0; index < 180; index += 1)
          InventoryStack(itemId: 'FILL-$index', quantity: 1),
      ],
    );
    final refused = claimMailAttachments(full, 'mail-gift', nowMs, db);
    expect(refused.ok, isFalse);
    expect(refused.reason, contains('full'));
  });

  test('adds an empty mailbox when migrating a v50 save', () {
    final created = createNewSave(db, nowMs);
    final legacy = created.toJson()
      ..['saveVersion'] = 50
      ..remove('mailbox');
    final migrated = migrateSaveJson(legacy, nowMs);
    expect(migrated['saveVersion'], 51);
    expect(migrated['mailbox'], isEmpty);
  });
}
