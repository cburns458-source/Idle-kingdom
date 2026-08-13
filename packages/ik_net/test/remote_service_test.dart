import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';
import 'package:test/test.dart';

const num _nowMs = 1786568400000;

GameDatabase _database() => assertGameDatabaseShape(contentDatabaseJson());

/// A remote service on a pinned clock, so an assertion can name a timestamp.
RemoteMultiplayerService _service(
  FakeTransport transport,
  MemorySaveStorage storage, {
  num startMs = _nowMs,
}) {
  final num clock = startMs;
  var counter = 0;
  return RemoteMultiplayerService(
    transport: transport,
    storage: storage,
    ports: LocalBackendPorts(
      nowMs: () => clock,
      newId: (prefix) => '${prefix}_${(counter += 1).toString().padLeft(4, '0')}',
    ),
  );
}

Future<RemoteMultiplayerService> _signedIn(
  FakeTransport transport,
  MemorySaveStorage storage, {
  num startMs = _nowMs,
}) async {
  final service = _service(transport, storage, startMs: startMs);
  final created = await service.signUp('hero@example.com', 'Hero', 'secret');
  expect(created.ok, isTrue, reason: created.reason);
  return service;
}

void main() {
  test('signs an account up and starts its profile row', () async {
    final transport = FakeTransport();
    final storage = MemorySaveStorage();
    final service = await _signedIn(transport, storage);

    expect(service.session?.username, 'Hero');
    expect(service.session?.email, 'hero@example.com');
    expect(service.session?.accessToken, isNotEmpty);
    expect(transport.tables[RemoteTables.profiles]!.single['username'], 'Hero');

    // The session outlives the object holding it, as a relaunch would need.
    expect(_service(transport, storage).session?.userId, service.session!.userId);
  });

  test('trims and shortens a name before the account carries it', () async {
    final transport = FakeTransport();
    final service = _service(transport, MemorySaveStorage());
    await service.signUp('  HERO@Example.com ', '  ${'Rowan' * 8}  ', 'secret');

    expect(service.session!.username.length, remoteUsernameMaxLength);
    expect(service.session!.email, 'hero@example.com');
  });

  test('reports why the backend refused a sign-in', () async {
    final transport = FakeTransport();
    final service = _service(transport, MemorySaveStorage());

    final refused = await service.signIn('nobody@example.com', 'secret');
    expect(refused.ok, isFalse);
    expect(refused.reason, 'Invalid login credentials.');
    expect(service.isSignedIn, isFalse);
  });

  test('names an account made outside the game after its email', () async {
    final transport = FakeTransport();
    transport.seedAccount(email: 'outside@example.com');
    final service = _service(transport, MemorySaveStorage());

    final signed = await service.signIn('OUTSIDE@example.com ', 'secret');
    expect(signed.ok, isTrue);
    expect(service.session?.username, 'outside');
  });

  test('signs out of both the device and the backend', () async {
    final transport = FakeTransport();
    final storage = MemorySaveStorage();
    final service = await _signedIn(transport, storage);

    await service.signOut();
    expect(service.isSignedIn, isFalse);
    expect(transport.signedOut, isTrue);
  });

  test('sends a magic link, which the local backend cannot', () async {
    final transport = FakeTransport();
    final storage = MemorySaveStorage();
    final service = _service(transport, storage);

    expect((await service.sendMagicLink('hero@example.com')).ok, isTrue);
    expect(transport.magicLinks.single, 'hero@example.com');

    transport.failNextWith = 'Email rate limit exceeded.';
    expect((await service.sendMagicLink('hero@example.com')).reason, 'Email rate limit exceeded.');

    final local = LocalMultiplayerService(storage: MemorySaveStorage());
    expect((await local.sendMagicLink('hero@example.com')).reason, remoteMagicLinkUnavailable);
  });

  test('uploads a save and reads it back', () async {
    final transport = FakeTransport();
    final storage = MemorySaveStorage();
    final service = await _signedIn(transport, storage);
    final db = _database();
    final save = createNewSave(db, _nowMs).copyWith(characterName: 'Hero', gold: 250);

    final pushed = await service.pushSave(db, save);
    expect(pushed.ok, isTrue, reason: pushed.reason);
    expect(pushed.source, CloudSyncSource.uploaded);
    expect(pushed.save!.updatedAt, isoFromMs(_nowMs));

    final row = transport.tables[RemoteTables.saves]!.single;
    expect(row['user_id'], service.session!.userId);
    expect(row['updated_at'], isoFromMs(_nowMs));

    final pulled = await service.pullSave();
    expect(pulled.ok, isTrue, reason: pulled.reason);
    expect(pulled.save!.gold, 250);
    expect(pulled.source, CloudSyncSource.downloaded);
  });

  test('submits every board the save is worth alongside the upload', () async {
    final transport = FakeTransport();
    final storage = MemorySaveStorage();
    final service = await _signedIn(transport, storage);
    final db = _database();

    await service.pushSave(db, createNewSave(db, _nowMs).copyWith(characterName: 'Hero'));

    final rows = transport.tables[RemoteTables.leaderboard]!;
    expect(rows, isNotEmpty);
    expect(rows.every((row) => row['updated_at'] == isoFromMs(_nowMs)), isTrue);

    // A second submit updates the same rows rather than adding more.
    final before = rows.length;
    await service.submitLeaderboard(db, createNewSave(db, _nowMs).copyWith(gold: 999));
    expect(transport.tables[RemoteTables.leaderboard]!, hasLength(before));
  });

  test('reads a board back in descending order with its profile joined', () async {
    final transport = FakeTransport();
    final storage = MemorySaveStorage();
    final service = await _signedIn(transport, storage);
    final db = _database();
    await service.pushSave(db, createNewSave(db, _nowMs).copyWith(characterName: 'Hero'));

    // A rival's row, written straight to the table the way another client would.
    await transport.upsert(RemoteTables.profiles, <RemoteRow>[
      <String, Object?>{'user_id': 'usr_rival', 'username': 'Rival', 'guild_name': 'Iron League'},
    ]);
    await transport.upsert(
      RemoteTables.leaderboard,
      <RemoteRow>[
        <String, Object?>{'user_id': 'usr_rival', 'board_key': boardTotalLevel, 'value': 99},
      ],
      onConflict: remoteLeaderboardConflict,
    );

    final board = await service.leaderboard(boardTotalLevel);
    expect(board.map((entry) => entry.username), <String>['Rival', 'Hero']);
    expect(board.first.rank, 1);
    expect(board.first.value, 99);
    expect(board.first.guildName, 'Iron League');
    // A row whose profile never arrived still reads as somebody.
    expect(board.last.appearance, isNotNull);
  });

  test('reports an empty board rather than throwing when a read fails', () async {
    final transport = FakeTransport();
    final storage = MemorySaveStorage();
    final service = await _signedIn(transport, storage);

    transport.failNextWith = 'Connection closed.';
    expect(await service.leaderboard(boardTotalLevel), isEmpty);
  });

  test('refuses an upload the account has a newer save than', () async {
    final transport = FakeTransport();
    final storage = MemorySaveStorage();
    final service = await _signedIn(transport, storage);
    final db = _database();
    final base = createNewSave(db, _nowMs);

    // A row a later session wrote, which this one must not overwrite blindly.
    await transport.upsert(RemoteTables.saves, <RemoteRow>[
      saveRowFor(service.session!.userId, base.copyWith(updatedAt: '2099-01-01T00:00:00.000Z')),
    ]);

    final blocked = await service.pushSave(db, base);
    expect(blocked.ok, isFalse);
    expect(blocked.reason, remoteSaveConflict);
    expect(blocked.remote?.updatedAt, '2099-01-01T00:00:00.000Z');
  });

  test('stops a sync when the stored save is newer, and forces past it', () async {
    final transport = FakeTransport();
    final storage = MemorySaveStorage();
    final service = await _signedIn(transport, storage);
    final db = _database();
    final base = createNewSave(db, _nowMs);

    await transport.upsert(RemoteTables.saves, <RemoteRow>[
      saveRowFor(service.session!.userId, base.copyWith(updatedAt: '2099-01-01T00:00:00.000Z')),
    ]);

    final blocked = await service.syncSave(db, base);
    expect(blocked.ok, isFalse);
    expect(blocked.reason, 'Cloud save is newer than the local save.');
    expect(blocked.remote?.payload.updatedAt, '2099-01-01T00:00:00.000Z');

    final forced = await service.syncSave(db, base, forceUpload: true);
    expect(forced.ok, isTrue, reason: forced.reason);
    expect(transport.tables[RemoteTables.saves]!.single['updated_at'], isoFromMs(_nowMs));
  });

  test('uploads over a stored row this build cannot read', () async {
    final transport = FakeTransport();
    final storage = MemorySaveStorage();
    final service = await _signedIn(transport, storage);
    final db = _database();

    transport.tables[RemoteTables.saves]!.add(<String, Object?>{
      'user_id': service.session!.userId,
      'save_version': 999,
      'updated_at': '2099-01-01T00:00:00.000Z',
      'payload': <String, Object?>{'notASave': true},
    });

    final synced = await service.syncSave(db, createNewSave(db, _nowMs));
    expect(synced.ok, isTrue, reason: synced.reason);

    // The same unreadable row is refused on a pull, where there is nothing to
    // replace it with.
    transport.tables[RemoteTables.saves]!.first['payload'] = <String, Object?>{'notASave': true};
    expect((await service.pullSave()).reason, 'The cloud save could not be read.');
  });

  test('says which account has no cloud save yet', () async {
    final transport = FakeTransport();
    final service = await _signedIn(transport, MemorySaveStorage());
    expect((await service.pullSave()).reason, 'No cloud save for this account yet.');
  });

  test('needs an account before it will sync anything', () async {
    final transport = FakeTransport();
    final service = _service(transport, MemorySaveStorage());
    final db = _database();
    final save = createNewSave(db, _nowMs);

    expect((await service.pushSave(db, save)).reason, 'Sign in to sync cloud saves.');
    expect((await service.pullSave()).reason, 'Sign in to load cloud saves.');
    expect((await service.submitLeaderboard(db, save)).reason, isNotNull);
    expect((await service.syncSave(db, save)).source, CloudSyncSource.unchanged);
    expect((await service.sendChat(const ChatChannel.global(), 'Hi')).reason, 'Sign in to chat.');
    expect(await service.listChat(const ChatChannel.global()), isEmpty);
    expect(transport.calls.where((call) => call.startsWith('upsert')), isEmpty);
  });

  test('sends chat through the function and reads it from the table', () async {
    final transport = FakeTransport();
    final service = await _signedIn(transport, MemorySaveStorage());

    final sent = await service.sendChat(const ChatChannel.local('LOC-0028'), 'Anyone here?');
    expect(sent.ok, isTrue, reason: sent.reason);
    expect(sent.message!.channelKey, 'local:LOC-0028');
    expect(sent.message!.body, 'Anyone here?');
    expect(transport.calls, contains('invoke:$remoteSendChatFunction'));

    final read = await service.listChat(const ChatChannel.local('LOC-0028'));
    expect(read.single.body, 'Anyone here?');
    // Another room does not see it.
    expect(await service.listChat(const ChatChannel.global()), isEmpty);
  });

  test('accepts either spelling of the fields the function answers with', () async {
    final transport = FakeTransport();
    final service = await _signedIn(transport, MemorySaveStorage());

    transport.chatFunctionReply = <String, Object?>{
      'id': 'msg_1',
      'channelKey': 'global',
      'userId': 'usr_0001',
      'username': 'Hero',
      'body': 'Hi',
      'createdAt': '2026-08-13T00:00:00.000Z',
    };
    final camel = await service.sendChat(const ChatChannel.global(), 'Hi');
    expect(camel.message!.userId, 'usr_0001');
    expect(camel.message!.createdAt, '2026-08-13T00:00:00.000Z');

    transport.chatFunctionReply = <String, Object?>{'accepted': true};
    expect((await service.sendChat(const ChatChannel.global(), 'Hi')).reason, remoteChatSendFailed);

    transport.chatFunctionReply = null;
    transport.failNextWith = 'Chat cooldown active.';
    expect((await service.sendChat(const ChatChannel.global(), 'Hi')).reason, 'Chat cooldown active.');
  });

  test('answers the screens no server owns from this device', () async {
    final transport = FakeTransport();
    final storage = MemorySaveStorage();
    final service = await _signedIn(transport, storage);
    final save = createNewSave(_database(), _nowMs).copyWith(currentLocationId: 'LOC-0028');

    expect(await service.publishPresence(presenceFromSave(save)), isNotNull);
    expect(await service.peersAtLocation('LOC-0028', excludeSelf: false), hasLength(1));

    final guild = await service.createGuild(
      const CreateGuildInput(
        name: 'Iron League',
        tag: 'IRN',
        emblem: GuildEmblem(color: '#3d5a80', symbol: 'shield'),
      ),
      guildCreateGoldCost,
    );
    expect(guild.ok, isTrue, reason: guild.reason);
    expect(await service.currentGuildId(), guild.guild!.id);

    final posted = await service.postBazaar(bazaarPostTrade, 'Selling copper ore');
    expect(posted.ok, isTrue, reason: posted.reason);
    expect((await service.bazaarPosts()).single.body, 'Selling copper ore');

    // None of it went over the wire.
    expect(transport.calls.where((call) => call.startsWith('invoke')), isEmpty);
  });
}
