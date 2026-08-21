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

  test('assigns a pending name on sign-up, then claims the first character name', () async {
    final transport = FakeTransport();
    final first = _service(transport, MemorySaveStorage());
    final created = await first.signUp('hero@example.com', '', 'secret');
    expect(created.ok, isTrue);
    expect(isPendingAccountUsername(first.session!.username), isTrue);
    expect(transport.tables[RemoteTables.profiles]!.single['username'], first.session!.username);

    expect((await first.claimAccountUsername('Hero')).ok, isTrue);
    expect(first.session?.username, 'Hero');
    expect(transport.tables[RemoteTables.profiles]!.single['username'], 'Hero');
    expect(transport.calls, contains('updateAuthUsername:Hero'));

    expect((await first.claimAccountUsername('Later')).ok, isTrue);
    expect(first.session?.username, 'Hero');

    final rival = _service(transport, MemorySaveStorage());
    await rival.signUp('rival@example.com', '', 'secret');
    expect((await rival.claimAccountUsername('Hero')).reason, 'That name is taken.');
    expect(isPendingAccountUsername(rival.session!.username), isTrue);
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

  test('submits every board the save is worth only when asked', () async {
    final transport = FakeTransport();
    final storage = MemorySaveStorage();
    final service = await _signedIn(transport, storage);
    final db = _database();
    final save = createNewSave(db, _nowMs).copyWith(characterName: 'Hero');

    await service.pushSave(db, save);
    expect(transport.tables[RemoteTables.leaderboard], isEmpty);

    await service.submitLeaderboard(db, save);
    final rows = transport.tables[RemoteTables.leaderboard]!;
    expect(rows, isNotEmpty);
    expect(rows.every((row) => row['updated_at'] == isoFromMs(_nowMs)), isTrue);
    expect(
      transport.tables[RemoteTables.profiles]!.single['appearance_json'],
      save.appearance.toJson(),
    );

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
    final save = createNewSave(db, _nowMs).copyWith(characterName: 'Hero');
    await service.pushSave(db, save);
    await service.submitLeaderboard(db, save);

    // A rival's row, written straight to the table the way another client would.
    await transport.upsert(RemoteTables.profiles, <RemoteRow>[
      <String, Object?>{'user_id': 'usr_rival', 'username': 'Rival', 'guild_name': 'Iron League'},
    ]);
    await transport.upsert(RemoteTables.leaderboard, <RemoteRow>[
      <String, Object?>{'user_id': 'usr_rival', 'board_key': boardTotalLevel, 'value': 99},
    ], onConflict: remoteLeaderboardConflict);

    final board = await service.leaderboard(boardTotalLevel);
    expect(board.map((entry) => entry.username), <String>['Rival', 'Hero']);
    expect(board.first.rank, 1);
    expect(board.first.value, 99);
    expect(board.first.guildName, 'Iron League');
    // A row whose profile never arrived still reads as somebody.
    expect(board.last.appearance, isNotNull);
  });

  test('two accounts that submit both appear on the board', () async {
    final transport = FakeTransport();
    final db = _database();

    final hero = await _signedIn(transport, MemorySaveStorage());
    final heroSave = createNewSave(db, _nowMs).copyWith(characterName: 'Hero');
    await hero.pushSave(db, heroSave);
    expect((await hero.submitLeaderboard(db, heroSave)).ok, isTrue);

    final rival = _service(transport, MemorySaveStorage());
    expect((await rival.signUp('rival@example.com', 'Rival', 'secret')).ok, isTrue);
    final rivalSave = createNewSave(db, _nowMs).copyWith(characterName: 'Rival', gold: 999);
    await rival.pushSave(db, rivalSave);
    expect((await rival.submitLeaderboard(db, rivalSave)).ok, isTrue);

    final board = await hero.leaderboard(boardTotalLevel);
    expect(board.map((entry) => entry.username).toSet(), <String>{'Hero', 'Rival'});
    expect(board, hasLength(2));
  });

  test('a snapshot without a profile still lists that other player', () async {
    final transport = FakeTransport();
    final storage = MemorySaveStorage();
    final service = await _signedIn(transport, storage);
    final db = _database();
    final save = createNewSave(db, _nowMs).copyWith(characterName: 'Hero');
    await service.pushSave(db, save);
    await service.submitLeaderboard(db, save);

    await transport.upsert(RemoteTables.leaderboard, <RemoteRow>[
      <String, Object?>{'user_id': 'usr_ghost', 'board_key': boardTotalLevel, 'value': 50},
    ], onConflict: remoteLeaderboardConflict);

    final board = await service.leaderboard(boardTotalLevel);
    expect(board.map((entry) => entry.username), <String>['Adventurer', 'Hero']);
    expect(board.first.userId, 'usr_ghost');
    expect(board.last.username, 'Hero');
  });

  test('reports an empty board rather than throwing when a read fails', () async {
    final transport = FakeTransport();
    final storage = MemorySaveStorage();
    final service = await _signedIn(transport, storage);

    transport.failNextWith = 'Connection closed.';
    expect(await service.leaderboard(boardTotalLevel), isEmpty);
  });

  test('a read that was refused is remembered, so a bare screen can say why', () async {
    final transport = FakeTransport();
    final storage = MemorySaveStorage();
    final service = await _signedIn(transport, storage);

    expect(service.takeReadProblem(), isNull, reason: 'nothing has gone wrong yet');

    // A column this build reads and the project has not got is what a skipped
    // migration looks like from the client.
    transport.failNextWith = 'column leaderboard_snapshots.value_secondary does not exist';
    expect(await service.leaderboard(boardTotalLevel), isEmpty);

    expect(service.takeReadProblem(), contains('value_secondary'));
    expect(service.takeReadProblem(), isNull, reason: 'reported once, not on every pass after');
  });

  test('a missing leaderboard view is remembered rather than hidden', () async {
    final transport = FakeTransport();
    final storage = MemorySaveStorage();
    final service = await _signedIn(transport, storage);

    transport.failNextWith =
        'Could not find the table \'public.leaderboard_entries\' in the schema cache';
    expect(await service.leaderboard(boardTotalLevel), isEmpty);
    expect(service.takeReadProblem(), contains('leaderboard_entries'));
  });

  test('a refused cloud save read is not reported as an empty account', () async {
    final transport = FakeTransport();
    final storage = MemorySaveStorage();
    final service = await _signedIn(transport, storage);

    transport.failNextWith = 'Connection closed.';
    final pulled = await service.pullSave();
    expect(pulled.ok, isFalse);
    expect(pulled.reason, 'Connection closed.');
  });

  test('a refused read explains a wrong project URL the way sign-in does', () async {
    final transport = FakeTransport();
    final storage = MemorySaveStorage();
    final service = await _signedIn(transport, storage);

    transport.failNextWith = 'Invalid path specified in request URL';
    expect(await service.listGuilds(), isEmpty);

    expect(service.takeReadProblem(), remoteInvalidBackendUrl);
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

  test('a second sign-in takes the seat and the first cannot write', () async {
    final transport = FakeTransport();
    final first = await _signedIn(transport, MemorySaveStorage());
    expect((await first.claimPlaySession()).ok, isTrue);
    expect(first.session!.playSessionId, isNotNull);

    final db = _database();
    final save = createNewSave(db, _nowMs).copyWith(characterName: 'Hero', gold: 10);
    expect((await first.pushSave(db, save, force: true)).ok, isTrue);

    final second = _service(transport, MemorySaveStorage());
    final signed = await second.signIn('hero@example.com', 'secret');
    expect(signed.ok, isTrue, reason: signed.reason);
    expect((await second.claimPlaySession()).ok, isTrue);
    expect(second.session!.playSessionId, isNot(first.session!.playSessionId));
    expect(await first.activePlaySessionId(), second.session!.playSessionId);

    final refused = await first.pushSave(db, save.copyWith(gold: 99), force: true);
    expect(refused.ok, isFalse);
    expect(refused.reason, remoteSignedInElsewhere);

    final pulled = await second.pullSave();
    expect(pulled.ok, isTrue, reason: pulled.reason);
    expect(pulled.save!.gold, 10);
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

  test('sends a private message through the function and the other account reads it', () async {
    final transport = FakeTransport();
    final hero = await _signedIn(transport, MemorySaveStorage());
    final rival = _service(transport, MemorySaveStorage());
    expect((await rival.signUp('rival@example.com', 'Rival', 'secret')).ok, isTrue);

    final pair = ChatChannel.dm(dmPairKey(hero.session!.userId, rival.session!.userId));
    // The fake wire has one signed-in seat; take it back before the function writes.
    expect((await hero.signIn('hero@example.com', 'secret')).ok, isTrue);
    final sent = await hero.sendChat(pair, 'Meet at the docks?');
    expect(sent.ok, isTrue, reason: sent.reason);
    expect(sent.message!.userId, hero.session!.userId);
    expect(sent.message!.channelKey.startsWith('dm:'), isTrue);
    expect(sent.message!.body, 'Meet at the docks?');

    final heroInbox = await hero.listDirectMessages();
    expect(heroInbox.single.body, 'Meet at the docks?');
    expect(heroInbox.single.channelKey, sent.message!.channelKey);

    final rivalInbox = await rival.listDirectMessages();
    expect(rivalInbox.single.body, 'Meet at the docks?');
    expect(rivalInbox.single.userId, hero.session!.userId);
    expect(await rival.countUnreadDirectMessages(null), 1);
    expect(await hero.countUnreadDirectMessages(null), 0);

    final stranger = _service(transport, MemorySaveStorage());
    expect((await stranger.signUp('stranger@example.com', 'Stranger', 'secret')).ok, isTrue);
    expect(await stranger.listDirectMessages(), isEmpty);
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
    expect(
      (await service.sendChat(const ChatChannel.global(), 'Hi')).reason,
      'Chat cooldown active.',
    );
  });

  test('publishes presence so another account at the same place can see it', () async {
    final transport = FakeTransport();
    final hero = await _signedIn(transport, MemorySaveStorage());
    final save = createNewSave(_database(), _nowMs).copyWith(currentLocationId: 'LOC-0005');
    expect(await hero.publishPresence(presenceFromSave(save)), isNotNull);
    expect(transport.tables[RemoteTables.activityPresence], hasLength(1));
    final row = transport.tables[RemoteTables.activityPresence]!.single;
    expect(row['expires_at'], isoFromMs(_nowMs + presenceAwayTtlSeconds * 1000));

    final rival = _service(transport, MemorySaveStorage());
    await rival.signUp('rival@example.com', 'Rival', 'secret');
    final peers = await rival.peersAtLocation('LOC-0005');
    expect(peers.single.username, 'Hero');
    expect(peers.single.locationId, 'LOC-0005');
  });

  test('keeps Away peers visible until the away TTL, then drops them', () async {
    var clock = _nowMs;
    final transport = FakeTransport();
    final hero = RemoteMultiplayerService(
      transport: transport,
      storage: MemorySaveStorage(),
      ports: LocalBackendPorts(nowMs: () => clock, newId: (prefix) => '${prefix}_0001'),
    );
    await hero.signUp('hero@example.com', 'Hero', 'secret');
    final save = createNewSave(_database(), clock).copyWith(currentLocationId: 'LOC-0005');
    await hero.publishPresence(presenceFromSave(save));

    clock += presenceTtlSeconds * 1000 + 1000;
    final mid = await hero.peersAtLocation('LOC-0005', excludeSelf: false);
    expect(mid, hasLength(1));

    clock = _nowMs + presenceAwayTtlSeconds * 1000 + 1000;
    final gone = await hero.peersAtLocation('LOC-0005', excludeSelf: false);
    expect(gone, isEmpty);
  });

  test('authoritativeNowMs prefers the transport server clock', () async {
    final transport = FakeTransport(nowMs: () => _nowMs + 60_000);
    final service = _service(transport, MemorySaveStorage());
    expect(await service.authoritativeNowMs(), _nowMs + 60_000);
  });

  test('authoritativeNowMs falls back to the local ports clock', () async {
    final transport = FakeTransport();
    final service = _service(transport, MemorySaveStorage());
    expect(await service.authoritativeNowMs(), _nowMs);
  });

  test('loads another account public profile from the hosted profiles table', () async {
    final transport = FakeTransport();
    final hero = await _signedIn(transport, MemorySaveStorage());
    final db = _database();
    final save = createNewSave(db, _nowMs).copyWith(characterName: 'Hero', gold: 10);
    await hero.pushSave(db, save, force: true);
    await hero.submitLeaderboard(db, save);

    final rival = _service(transport, MemorySaveStorage());
    await rival.signUp('rival@example.com', 'Rival', 'secret');
    final profile = await rival.publicProfile(hero.session!.userId);
    expect(profile, isNotNull);
    expect(profile!.username, 'Hero');
    expect(profile.totalLevel, greaterThanOrEqualTo(1));
    expect(await rival.publicProfile('missing-user'), isNull);
  });

  test('records the first bounty turn-in of the hour and no other', () async {
    final transport = FakeTransport();
    final hero = await _signedIn(transport, MemorySaveStorage());

    final first = await hero.claimBounty('2026-08-13T00', 'BNT-0001');
    expect(first.ok, isTrue, reason: first.reason);
    expect(first.firstCompleter, isTrue);
    expect(first.claim!.username, 'Hero');
    expect(first.claim!.claimedAt, transport.startIso);

    // The same player asking again is told they already hold it.
    final again = await hero.claimBounty('2026-08-13T00', 'BNT-0001');
    expect(again.firstCompleter, isTrue);
    expect(transport.tables[RemoteTables.bountyClaims], hasLength(1));

    // A rival gets the claim back, naming who beat them, and still succeeds.
    final rival = _service(transport, MemorySaveStorage());
    await rival.signUp('rival@example.com', 'Rival', 'secret');
    final second = await rival.claimBounty('2026-08-13T00', 'BNT-0001');
    expect(second.ok, isTrue, reason: second.reason);
    expect(second.firstCompleter, isFalse);
    expect(second.claim!.username, 'Hero');

    // A different bounty is its own race.
    expect((await rival.claimBounty('2026-08-13T00', 'BNT-0002')).firstCompleter, isTrue);
    // And so is the next hour.
    expect((await rival.claimBounty('2026-08-13T01', 'BNT-0001')).firstCompleter, isTrue);
  });

  test('hands the winner back to whoever lost the race to the insert', () async {
    final transport = FakeTransport();
    final hero = await _signedIn(transport, MemorySaveStorage());

    // A claim that lands after the read said the slot was free, which is what a
    // second device doing the same thing at the same moment looks like.
    // The read that would have found it is made to fail, so the service goes on
    // to attempt the insert and has to cope with losing.
    transport.tables[RemoteTables.bountyClaims]!.add(<String, Object?>{
      'hour_key': '2026-08-13T00',
      'bounty_id': 'BNT-0001',
      'user_id': 'usr_rival',
      'username': 'Rival',
      'claimed_at': transport.startIso,
    });
    transport.failOnce['select:${RemoteTables.bountyClaims}'] = 'Connection reset.';

    final claimed = await hero.claimBounty('2026-08-13T00', 'BNT-0001');
    expect(claimed.ok, isTrue, reason: claimed.reason);
    expect(claimed.firstCompleter, isFalse);
    expect(claimed.claim!.username, 'Rival');
  });

  test('reports a claim that failed for a reason other than losing', () async {
    final transport = FakeTransport();
    final hero = await _signedIn(transport, MemorySaveStorage());

    // Nobody holds the bounty, so the refusal is the write itself, not a rival.
    transport.failOnce['insert:${RemoteTables.bountyClaims}'] = 'Connection closed.';
    final refused = await hero.claimBounty('2026-08-13T00', 'BNT-0001');

    expect(refused.ok, isFalse);
    expect(refused.reason, 'Connection closed.');
    expect(transport.tables[RemoteTables.bountyClaims], isEmpty);
  });

  test('lists the hour that was asked for, oldest first', () async {
    final transport = FakeTransport();
    final hero = await _signedIn(transport, MemorySaveStorage());

    await hero.claimBounty('2026-08-13T00', 'BNT-0001');
    await hero.claimBounty('2026-08-13T00', 'BNT-0002');
    await hero.claimBounty('2026-08-13T01', 'BNT-0001');

    final hour = await hero.bountyClaims('2026-08-13T00');
    expect(hour.map((claim) => claim.bountyId), <String>['BNT-0001', 'BNT-0002']);
    expect(await hero.bountyClaims('2026-08-12T23'), isEmpty);
  });

  test('posts a Bazaar notice and reads the board oldest first', () async {
    final transport = FakeTransport();
    final hero = await _signedIn(transport, MemorySaveStorage());

    final posted = await hero.postBazaar(bazaarPostTrade, '  Selling copper ore  ');
    expect(posted.ok, isTrue, reason: posted.reason);
    expect(posted.post!.body, 'Selling copper ore');
    expect(posted.post!.kind, bazaarPostTrade);
    expect(posted.post!.username, 'Hero');
    expect(posted.post!.id, isNotEmpty);

    await hero.postBazaar(bazaarPostMessage, 'Anyone hiring?');

    final board = await hero.bazaarPosts();
    expect(board.map((post) => post.body), <String>['Selling copper ore', 'Anyone hiring?']);
  });

  test('refuses a Bazaar notice the shared rules reject, before the wire', () async {
    final transport = FakeTransport();
    final hero = await _signedIn(transport, MemorySaveStorage());

    expect((await hero.postBazaar(bazaarPostMessage, '   ')).reason, bazaarEmptyPost);
    expect((await hero.postBazaar('shouting', 'Hello')).reason, bazaarUnknownKind);
    expect(transport.tables[RemoteTables.bazaarPosts], isEmpty);

    // What it does accept is masked and cut to length the same way either backend
    // would have done it.
    final long = await hero.postBazaar(bazaarPostMessage, 'fuck ${'a' * 400}');
    expect(long.post!.body.startsWith('****'), isTrue);
    expect(long.post!.body.length, bazaarPostMaxLength);
  });

  test('needs an account before it will touch either Citadel board', () async {
    final transport = FakeTransport();
    final service = _service(transport, MemorySaveStorage());

    expect(
      (await service.claimBounty('2026-08-13T00', 'BNT-0001')).reason,
      'Sign in to claim bounties.',
    );
    expect(
      (await service.postBazaar(bazaarPostMessage, 'Hello')).reason,
      'Sign in to post in the Grand Bazaar.',
    );
    expect(transport.calls.where((call) => call.startsWith('insert')), isEmpty);
  });
}
