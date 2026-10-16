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

void main() {
  test('local sendChat stamps the equipped title from the sender save', () {
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

  test('send-chat stores the save title on the row and listing reads it', () async {
    final db = _database();
    final transport = FakeTransport(database: db);
    final service = RemoteMultiplayerService(
      transport: transport,
      storage: MemorySaveStorage(),
      ports: LocalBackendPorts(nowMs: () => _nowMs, newId: (prefix) => '${prefix}_0001'),
    );
    expect((await service.signUp('hero@example.com', 'Hero', 'secret')).ok, isTrue);

    final noSave = await service.sendChat(const ChatChannel.global(), 'No save yet');
    expect(noSave.ok, isTrue);
    expect(noSave.message!.title, isNull);
    expect(transport.tables[RemoteTables.chat]!.last['title'], isNull);

    final living = createNewSave(db, _nowMs).copyWith(characterName: 'Hero');
    expect((await seedHostedSave(service, transport, living)).ok, isTrue);
    final undying = await service.sendChat(const ChatChannel.local('LOC-0001'), 'Hi');
    expect(undying.ok, isTrue);
    expect(undying.message!.title, 'The Undying');
    expect(undying.message!.body, 'Hi');

    final listed = await service.listChat(const ChatChannel.local('LOC-0001'));
    expect(listed.single.body, 'Hi');
    expect(listed.single.title, 'The Undying');
    expect(transport.tables[RemoteTables.chat]!.last['title'], 'The Undying');

    final faith = _withTitle(living, 'COS-0013');
    expect((await seedHostedSave(service, transport, faith)).ok, isTrue);
    final oruvani = await service.sendChat(const ChatChannel.local('LOC-0002'), 'Hold');
    expect(oruvani.message!.title, 'Oruvani');
    expect(transport.tables[RemoteTables.chat]!.last['title'], 'Oruvani');
    final listedFaith = await service.listChat(const ChatChannel.local('LOC-0002'));
    expect(listedFaith.single.title, 'Oruvani');
  });
}
