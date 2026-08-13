import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';
import 'package:test/test.dart';

const num _nowMs = 1786568400000;

/// A service whose clock and ids are pinned, so an assertion can name a row.
///
/// Two services sharing one storage stand for two devices, so their ids have to
/// come from different ranges the way real ones would.
LocalMultiplayerService _service(
  MemorySaveStorage storage, {
  num startMs = _nowMs,
  int idOffset = 0,
}) {
  final num clock = startMs;
  var counter = idOffset;
  return LocalMultiplayerService(
    storage: storage,
    ports: LocalBackendPorts(
      nowMs: () => clock,
      newId: (prefix) => '${prefix}_${(counter += 1).toString().padLeft(4, '0')}',
    ),
  );
}

GameDatabase _database() => assertGameDatabaseShape(contentDatabaseJson());

void main() {
  test('keeps the session across service instances', () async {
    final storage = MemorySaveStorage();
    final first = _service(storage);
    expect(first.isSignedIn, isFalse);

    final created = await first.signUp('hero@example.com', 'Hero', 'secret');
    expect(created.ok, isTrue);
    expect(first.session?.username, 'Hero');

    // A relaunch reads the stored session rather than asking again.
    expect(_service(storage).session?.userId, created.session!.userId);

    await first.signOut();
    expect(first.isSignedIn, isFalse);
    expect(_service(storage).isSignedIn, isFalse);
  });

  test('refuses everything that needs an account', () async {
    final service = _service(MemorySaveStorage());
    final db = _database();
    final save = createNewSave(db, _nowMs);

    expect((await service.pushSave(db, save)).reason, 'Sign in to sync cloud saves.');
    expect((await service.pullSave()).reason, 'Sign in to load cloud saves.');
    expect((await service.sendChat(const ChatChannel.global(), 'Hi')).reason, 'Sign in to chat.');
    expect(await service.listChat(const ChatChannel.global()), isEmpty);
    expect(await service.currentGuildId(), isNull);
    expect(await service.publishPresence(presenceFromSave(save)), isNull);
    expect(
      (await service.postBazaar(bazaarPostTrade, 'Selling')).reason,
      'Sign in to post in the Grand Bazaar.',
    );
  });

  test('pushes a save, then hands it back on pull', () async {
    final storage = MemorySaveStorage();
    final service = _service(storage);
    final db = _database();
    await service.signUp('hero@example.com', 'Hero', 'secret');
    final save = createNewSave(db, _nowMs).copyWith(characterName: 'Hero', gold: 250);

    final pushed = await service.pushSave(db, save);
    expect(pushed.ok, isTrue);
    expect(pushed.source, CloudSyncSource.uploaded);
    // The push stamps the save, so the record is the stamped one.
    expect(pushed.save!.updatedAt, isoFromMs(_nowMs));

    final pulled = await service.pullSave();
    expect(pulled.ok, isTrue);
    expect(pulled.save!.gold, 250);

    // Pushing also refreshes the profile and submits the boards.
    final profile = await service.profile(service.session!.userId);
    expect(profile?.username, 'Hero');
    final board = await service.leaderboard(boardTotalLevel);
    expect(board.single.username, 'Hero');
  });

  test('stops a sync when the stored save is newer', () async {
    final storage = MemorySaveStorage();
    final service = _service(storage);
    final db = _database();
    await service.signUp('hero@example.com', 'Hero', 'secret');
    final base = createNewSave(db, _nowMs);

    await service.pushSave(db, base.copyWith(updatedAt: '2026-08-13T00:00:00.000Z'));
    final stale = base.copyWith(updatedAt: '2026-08-01T00:00:00.000Z');

    final blocked = await service.syncSave(db, stale);
    expect(blocked.ok, isFalse);
    expect(blocked.reason, 'Cloud save is newer than the local save.');
    expect(blocked.remote?.payload.updatedAt, isoFromMs(_nowMs));

    final forced = await service.syncSave(db, stale, forceUpload: true);
    expect(forced.ok, isTrue);
  });

  test('leaves the player out of their own nearby list', () async {
    final storage = MemorySaveStorage();
    final hero = _service(storage);
    await hero.signUp('hero@example.com', 'Hero', 'secret');
    final save = createNewSave(_database(), _nowMs).copyWith(currentLocationId: 'LOC-0028');
    await hero.publishPresence(presenceFromSave(save));

    expect(await hero.peersAtLocation('LOC-0028'), isEmpty);
    expect(await hero.peersAtLocation('LOC-0028', excludeSelf: false), hasLength(1));

    // A second account on the same device sees the first one.
    final rival = _service(storage, startMs: _nowMs + 1000, idOffset: 100);
    await rival.signUp('rival@example.com', 'Rival', 'secret');
    final peers = await rival.peersAtLocation('LOC-0028');
    expect(peers.single.username, 'Hero');
  });

  test('reports the guild the player joined', () async {
    final storage = MemorySaveStorage();
    final service = _service(storage);
    await service.signUp('leader@example.com', 'Leader', 'secret');
    expect(await service.currentGuildId(), isNull);

    final created = await service.createGuild(
      const CreateGuildInput(
        name: 'Iron League',
        tag: 'IRN',
        emblem: GuildEmblem(color: '#3d5a80', symbol: 'shield'),
      ),
      guildCreateGoldCost,
    );
    expect(created.ok, isTrue);
    expect(await service.currentGuildId(), created.guild!.id);
    expect((await service.guildMembers(created.guild!.id)).single.role, guildRoleLeader);

    final challenges = await service.guildChallenges(created.guild!.id);
    expect(challenges.single.currentValue, 0);

    expect((await service.leaveGuild()).ok, isTrue);
    expect(await service.currentGuildId(), isNull);
  });
}
