import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';
import 'package:test/test.dart';

const num _nowMs = 1786568400000;

GameDatabase _database() => assertGameDatabaseShape(contentDatabaseJson());

PlayerSave _withTitle(PlayerSave save, String? cosmeticId, {bool hasEverDied = false}) {
  final unlocked = <String>{...save.cosmetics.unlocked, ?cosmeticId}.toList();
  return save.copyWith(
    hasEverDied: hasEverDied,
    cosmetics: save.cosmetics.copyWith(
      unlocked: unlocked,
      equipped: <String, String?>{...save.cosmetics.equipped, titleCosmeticSlotId: cosmeticId},
    ),
  );
}

ChatMessage _line({String? title}) => ChatMessage(
  id: 'msg_1',
  channelKey: 'global',
  userId: 'usr_1',
  username: 'Rowan',
  body: 'The watch is set.',
  createdAt: '2026-01-01T12:00:00.000Z',
  title: title,
);

void main() {
  test('local sendChat stamps the save title and ignores a spoofed title field on the save', () {
    final db = _database();
    final backend = LocalMultiplayerBackend(storage: MemorySaveStorage())..gameDatabase = db;
    final signed = backend.signUp('hero@example.com', 'Hero', 'secret');
    expect(signed.ok, isTrue);

    final untitled = backend.sendChat(signed.session!, const ChatChannel.global(), 'No save yet');
    expect(untitled.ok, isTrue);
    expect(untitled.message!.title, isNull);

    final living = createNewSave(db, _nowMs).copyWith(characterName: 'Hero');
    expect(backend.writeCloudSave(signed.session!.userId, living).ok, isTrue);
    final undying = backend.sendChat(signed.session!, const ChatChannel.local('LOC-0001'), 'Hi');
    expect(undying.ok, isTrue);
    expect(undying.message!.title, 'The Undying');
    expect(undying.message!.body, 'Hi');

    final dead = _withTitle(living, starterTitleCosmeticId, hasEverDied: true);
    expect(backend.writeCloudSave(signed.session!.userId, dead, force: true).ok, isTrue);
    final lost = backend.sendChat(
      signed.session!,
      const ChatChannel.local('LOC-0002'),
      'Still here',
    );
    expect(lost.ok, isTrue);
    expect(lost.message!.title, isNull);

    final faith = _withTitle(living, 'COS-0013', hasEverDied: true);
    expect(backend.writeCloudSave(signed.session!.userId, faith, force: true).ok, isTrue);
    final oruvani = backend.sendChat(signed.session!, const ChatChannel.local('LOC-0003'), 'Hold');
    expect(oruvani.ok, isTrue);
    expect(oruvani.message!.title, 'Oruvani');
  });

  test('send-chat function payload stamps the save title and ignores a client title', () async {
    final db = _database();
    final transport = FakeTransport(database: db);
    final service = RemoteMultiplayerService(
      transport: transport,
      storage: MemorySaveStorage(),
      ports: LocalBackendPorts(nowMs: () => _nowMs, newId: (prefix) => '${prefix}_0001'),
    );
    expect((await service.signUp('hero@example.com', 'Hero', 'secret')).ok, isTrue);

    final spoofedUntitled = await transport.invoke(remoteSendChatFunction, <String, Object?>{
      'channelKey': 'global',
      'body': 'No save yet',
      'title': 'Sir',
      'equippedTitle': 'Knight',
    });
    expect(spoofedUntitled.ok, isTrue);
    expect(chatMessageFromFunction(spoofedUntitled.data)!.title, isNull);
    expect(spoofedUntitled.data!['title'], isNull);
    expect(transport.tables[RemoteTables.chat]!.last['title'], isNull);

    final living = createNewSave(db, _nowMs).copyWith(characterName: 'Hero');
    expect((await seedHostedSave(service, transport, living)).ok, isTrue);

    final spoofed = await transport.invoke(remoteSendChatFunction, <String, Object?>{
      'channelKey': 'local:LOC-0001',
      'body': 'Hi',
      'title': 'Sir',
      'senderTitle': 'Knight',
    });
    expect(spoofed.ok, isTrue);
    final stamped = chatMessageFromFunction(spoofed.data)!;
    expect(stamped.title, 'The Undying');
    expect(stamped.body, 'Hi');
    expect(spoofed.data!['title'], 'The Undying');
    expect(transport.tables[RemoteTables.chat]!.last['title'], 'The Undying');

    final honest = await service.sendChat(const ChatChannel.local('LOC-0002'), 'Hold');
    expect(honest.ok, isTrue);
    expect(honest.message!.title, 'The Undying');
    expect(remoteChatColumns.contains('title'), isTrue);
  });

  test('chat puts the title before the name, and the name alone when none', () {
    expect(chatLineUsername(_line()), 'Rowan');
    expect(chatLineUsername(_line(title: 'The Undying')), 'The Undying Rowan');
    expect(chatLineUsername(_line(title: 'The Undying'), showTitles: false), 'Rowan');
  });

  test('hiding titles is local to this viewer; the message still carries title', () {
    const titled = ChatMessage(
      id: 'msg_1',
      channelKey: 'global',
      userId: 'usr_1',
      username: 'Rowan',
      body: 'The watch is set.',
      createdAt: '2026-01-01T12:00:00.000Z',
      title: 'The Undying',
    );
    final hidden = chatLines(<ChatMessage>[titled], 'usr_2', showTitles: false);
    final shown = chatLines(<ChatMessage>[titled], 'usr_2');
    expect(titled.title, 'The Undying');
    expect(hidden.single.username, 'Rowan');
    expect(shown.single.username, 'The Undying Rowan');
    expect(hidden.single.body, titled.body);
  });

  test('show-titles and timestamps keys default on, and every channel has a notify key', () {
    expect(chatShowTitlesStorageKey, 'idle-kingdoms.client.show-chat-titles');
    expect(chatShowTimestampsStorageKey, 'idle-kingdoms.client.show-chat-timestamps');
    expect(chatTabOrder.map((tab) => tab.wire).toList(), <String>[
      'global',
      'local',
      'guild',
      'guest',
      'dm',
    ]);
    expect(chatTabOrder.map(chatNotifyStorageKey).toList(), <String>[
      'idle-kingdoms.client.chat-notify:global',
      'idle-kingdoms.client.chat-notify:local',
      'idle-kingdoms.client.chat-notify:guild',
      'idle-kingdoms.client.chat-notify:guest',
      'idle-kingdoms.client.chat-notify:dm',
    ]);
    expect(
      chatTabs(
        selected: ChatTab.global,
        citadelHub: false,
        hasGuild: true,
        hasGuest: true,
        unreadDms: 0,
      ).map((tab) => tab.label).toList(),
      <String>['Global', 'Local', 'Guild', 'Guest', 'Private'],
    );
    expect(
      formatChatTimestamp('2026-01-01T12:00:00.000Z', now: DateTime.utc(2026, 1, 1, 18)),
      isNotEmpty,
    );
  });
}
