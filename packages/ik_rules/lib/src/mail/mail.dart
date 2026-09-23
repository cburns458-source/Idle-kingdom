import 'package:ik_content/ik_content.dart';

import '../inventory/add_items.dart';
import '../save/generated/save_models.dart';
import '../time.dart';

/// Mail is dropped this long after it was sent.
const num mailboxTtlMs = 90 * 24 * 60 * 60 * 1000;

const String mailboxTestCatalogId = 'mail-mailbox-test';

const String mailUpdate20260922CatalogId = 'mail-update-2026-09-22';

const String _mailUpdate20260922Body = '''Update (Sep 22–23)

Combat
- Added copper sword and dagger
- New Combat Level leaderboard!
- New characters default to Offensive stance
- View an opponent's gear before PvP

Gathering
- Rebalanced gather and craft success
- Pot fishing XP increased

Food and potions
- Eat now on your equipment screen
- Auto-eat tweaks
- Potion icon while adventuring; tap to pause

Botany
- Plants can fail when they grow; gather compost on Patches and use it when planting to improve your odds
- New botany seeds and mutations, including Moonblossom at Botany 70
- Botany menu: Crops, Herbs, Flowers, Trees
- Pruners give reduced Botany XP

Features
- New in-game mailbox! Open mail from the top bar, read messages, and claim attached items
- Bazaar expanded to six offer slots; recent trades open from a button on the page
- XP and Loot trackers under your location name on the map
- Lockpicks require Thievery 20
- Added soup stock, go to a kitchen and combine water and kitchen scraps, used to make stews and soups
- Signing in on another device ends your other active session while you are playing

Minor balance changes
Minor UI tweaks
Minor art updates

Vari - ❤️''';

class SystemMailCatalogEntry {
  const SystemMailCatalogEntry({
    required this.id,
    required this.subject,
    required this.body,
    required this.sentAt,
    this.attachments = const <MailAttachment>[],
  });

  final String id;
  final String subject;
  final String body;
  final String sentAt;
  final List<MailAttachment> attachments;
}

/// Broadcast mail every save should receive. New rows are appended; existing
/// players pick them up on the next parse. Do not invent update-list copy here —
/// approved text is added as its own catalog row.
const List<SystemMailCatalogEntry> systemMailCatalog = <SystemMailCatalogEntry>[
  SystemMailCatalogEntry(
    id: mailboxTestCatalogId,
    subject: 'Mailbox',
    body: 'This is a test of the kingdom post. Update lists will arrive here.',
    sentAt: '2026-09-22T00:00:00.000Z',
  ),
  SystemMailCatalogEntry(
    id: mailUpdate20260922CatalogId,
    subject: 'Update (Sep 22–23)',
    body: _mailUpdate20260922Body,
    sentAt: '2026-09-23T00:00:00.000Z',
  ),
];

num mailSentAtMs(String sentAt) => jsDateParse(sentAt);

bool isMailExpired(String sentAt, num nowMs) {
  final sentMs = mailSentAtMs(sentAt);
  if (!sentMs.isFinite) return true;
  return nowMs - sentMs >= mailboxTtlMs;
}

PlayerSave pruneExpiredMail(PlayerSave save, num nowMs) {
  final mailbox = save.mailbox.where((message) => !isMailExpired(message.sentAt, nowMs)).toList();
  if (mailbox.length == save.mailbox.length) return save;
  return save.copyWith(mailbox: mailbox);
}

PlayerSave syncSystemMail(PlayerSave save, num nowMs) {
  final pruned = pruneExpiredMail(save, nowMs);
  final have = <String>{
    for (final message in pruned.mailbox)
      if (message.catalogId != null) message.catalogId!,
  };
  final extras = <MailMessage>[];
  for (final entry in systemMailCatalog) {
    if (have.contains(entry.id)) continue;
    if (isMailExpired(entry.sentAt, nowMs)) continue;
    extras.add(
      MailMessage(
        id: entry.id,
        catalogId: entry.id,
        subject: entry.subject,
        body: entry.body,
        sentAt: entry.sentAt,
        readAt: null,
        attachments: [for (final attachment in entry.attachments) attachment],
        claimedAt: null,
      ),
    );
  }
  if (extras.isEmpty) return pruned;
  return pruned.copyWith(mailbox: [...pruned.mailbox, ...extras]);
}

int _compareVisibleMail(MailMessage a, MailMessage b) {
  final aUnread = a.readAt == null;
  final bUnread = b.readAt == null;
  if (aUnread != bUnread) return aUnread ? -1 : 1;
  final sent = mailSentAtMs(b.sentAt) - mailSentAtMs(a.sentAt);
  if (sent != 0 && sent.isFinite) return sent < 0 ? -1 : 1;
  return a.id.compareTo(b.id);
}

List<MailMessage> visibleMailbox(PlayerSave save, num nowMs) {
  final messages = save.mailbox.where((message) => !isMailExpired(message.sentAt, nowMs)).toList();
  messages.sort(_compareVisibleMail);
  return messages;
}

num unreadMailCount(PlayerSave save, num nowMs) {
  return visibleMailbox(save, nowMs).where((message) => message.readAt == null).length;
}

PlayerSave markMailRead(PlayerSave save, String messageId, num nowMs) {
  final mailbox = [
    for (final message in save.mailbox)
      if (message.id != messageId || message.readAt != null || isMailExpired(message.sentAt, nowMs))
        message
      else
        message.copyWith(readAt: isoFromMs(nowMs)),
  ];
  return save.copyWith(mailbox: mailbox);
}

class MailClaimResult {
  const MailClaimResult.ok(this.save) : reason = null;

  const MailClaimResult.failed(this.reason) : save = null;

  final PlayerSave? save;
  final String? reason;

  bool get ok => reason == null;
}

MailClaimResult claimMailAttachments(
  PlayerSave save,
  String messageId,
  num nowMs, [
  GameDatabase? db,
]) {
  MailMessage? message;
  for (final entry in save.mailbox) {
    if (entry.id == messageId) {
      message = entry;
      break;
    }
  }
  if (message == null || isMailExpired(message.sentAt, nowMs)) {
    return const MailClaimResult.failed('That letter is gone.');
  }
  if (message.attachments.isEmpty) {
    return const MailClaimResult.failed('Nothing to claim.');
  }
  if (message.claimedAt != null) {
    return const MailClaimResult.failed('Those items were already claimed.');
  }
  var next = save;
  for (final attachment in message.attachments) {
    final granted = addItemToInventoryExact(
      next,
      attachment.itemId,
      attachment.quantity,
      null,
      false,
      db,
    );
    if (!granted.ok) return MailClaimResult.failed(granted.reason!);
    next = granted.save!;
  }
  final claimedAt = isoFromMs(nowMs);
  return MailClaimResult.ok(
    next.copyWith(
      mailbox: [
        for (final entry in next.mailbox)
          if (entry.id == messageId)
            entry.copyWith(claimedAt: claimedAt, readAt: entry.readAt ?? claimedAt)
          else
            entry,
      ],
    ),
  );
}
