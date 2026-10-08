import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';
import 'package:test/test.dart';

const num _nowMs = 1786568400000;

RemoteMultiplayerService _service(FakeTransport transport, {num startMs = _nowMs}) {
  return RemoteMultiplayerService(
    transport: transport,
    storage: MemorySaveStorage(),
    ports: LocalBackendPorts(nowMs: () => startMs, newId: (prefix) => '${prefix}_0001'),
  );
}

/// A hosted save that can pay for a guild, since founding is charged there.
Future<void> _purse(RemoteMultiplayerService service, FakeTransport transport) async {
  final database = assertGameDatabaseShape(contentDatabaseJson());
  final save = createNewSave(database, _nowMs).copyWith(gold: guildCreateGoldCost);
  expect((await seedHostedSave(service, transport, save)).ok, isTrue);
}

void main() {
  test('a first character name does not start the rename cooldown', () async {
    final transport = FakeTransport(nowMs: () => _nowMs);
    final service = _service(transport);
    expect((await service.signUp('hero@example.com', '', 'secret')).ok, isTrue);
    expect(isPendingAccountUsername(service.session!.username), isTrue);

    expect((await service.claimAccountUsername('Hero')).ok, isTrue);
    expect(transport.tables[RemoteTables.profiles]!.single[remoteUsernameRenamedAtColumn], isNull);

    expect((await service.renameAccountUsername('Vari')).ok, isTrue);
    expect(transport.tables[RemoteTables.profiles]!.single['username'], 'Vari');
    expect(
      transport.tables[RemoteTables.profiles]!.single[remoteUsernameRenamedAtColumn],
      isNotNull,
    );
  });

  test('a second rename is refused at the transport, not only the client', () async {
    var nowMs = _nowMs;
    final transport = FakeTransport(nowMs: () => nowMs);
    final service = RemoteMultiplayerService(
      transport: transport,
      storage: MemorySaveStorage(),
      ports: LocalBackendPorts(nowMs: () => nowMs, newId: (prefix) => '${prefix}_${nowMs.toInt()}'),
    );
    await service.signUp('hero@example.com', 'Hero', 'secret');
    expect((await service.renameAccountUsername('Vari')).ok, isTrue);

    final userId = service.session!.userId;
    expect(
      await transport.upsert(RemoteTables.profiles, <RemoteRow>[
        <String, Object?>{'user_id': userId, 'username': 'Later'},
      ], onConflict: 'user_id'),
      contains('rename again'),
    );
    expect(transport.tables[RemoteTables.profiles]!.single['username'], 'Vari');

    nowMs += usernameRenameCooldownMs;
    expect(
      await transport.upsert(RemoteTables.profiles, <RemoteRow>[
        <String, Object?>{'user_id': userId, 'username': 'Later'},
      ], onConflict: 'user_id'),
      isNull,
    );
    expect(transport.tables[RemoteTables.profiles]!.single['username'], 'Later');
  });

  test('a stamped upsert on an existing profile still renames', () async {
    final transport = FakeTransport(nowMs: () => _nowMs);
    final service = _service(transport);
    await service.signUp('hero@example.com', 'Hero', 'secret');
    final userId = service.session!.userId;

    expect(
      await transport.upsert(RemoteTables.profiles, <RemoteRow>[
        <String, Object?>{
          'user_id': userId,
          'username': 'Vari',
          remoteUsernameRenamedAtColumn: '2020-01-01T00:00:00.000Z',
        },
      ], onConflict: 'user_id'),
      isNull,
    );
    expect(transport.tables[RemoteTables.profiles]!.single['username'], 'Vari');
    expect(
      transport.tables[RemoteTables.profiles]!.single[remoteUsernameRenamedAtColumn],
      isNotNull,
    );
    expect(
      transport.tables[RemoteTables.profiles]!.single[remoteUsernameRenamedAtColumn],
      isNot('2020-01-01T00:00:00.000Z'),
    );
  });

  test('a client cannot write username_renamed_at by itself', () async {
    final transport = FakeTransport(nowMs: () => _nowMs);
    final service = _service(transport);
    await service.signUp('hero@example.com', 'Hero', 'secret');
    final userId = service.session!.userId;

    expect(
      await transport.update(
        RemoteTables.profiles,
        <String, Object?>{remoteUsernameRenamedAtColumn: '2020-01-01T00:00:00.000Z'},
        equals: <String, Object?>{'user_id': userId},
      ),
      remoteUsernameRenamedAtLocked,
    );
  });

  test('a profile cannot wear a guild tag without membership', () async {
    final transport = FakeTransport(nowMs: () => _nowMs);
    final service = _service(transport);
    await service.signUp('hero@example.com', 'Hero', 'secret');
    await _purse(service, transport);
    final userId = service.session!.userId;

    expect(
      await transport.update(
        RemoteTables.profiles,
        <String, Object?>{'guild_id': 'gld_spoof'},
        equals: <String, Object?>{'user_id': userId},
      ),
      remoteProfileGuildTagMismatch,
    );

    final created = await service.createGuild(
      const CreateGuildInput(
        name: 'Iron League',
        tag: 'IRN',
        emblem: GuildEmblem(color: '#3d5a80', symbol: 'shield'),
      ),
      guildCreateGoldCost,
    );
    expect(created.ok, isTrue, reason: created.reason);
    expect(transport.tables[RemoteTables.profiles]!.single['guild_id'], created.guild!.id);

    expect((await service.leaveGuild()).ok, isTrue);
    expect(transport.tables[RemoteTables.profiles]!.single['guild_id'], isNull);
  });

  test('only the current leader can write guilds.leader_id', () async {
    final transport = FakeTransport(nowMs: () => _nowMs);
    final leader = _service(transport);
    await leader.signUp('leader@example.com', 'Leader', 'secret');
    await _purse(leader, transport);
    final created = await leader.createGuild(
      const CreateGuildInput(
        name: 'Iron League',
        tag: 'IRN',
        emblem: GuildEmblem(color: '#3d5a80', symbol: 'shield'),
      ),
      guildCreateGoldCost,
    );
    expect(created.ok, isTrue, reason: created.reason);

    final officer = RemoteMultiplayerService(
      transport: FakeTransport.joining(transport),
      storage: MemorySaveStorage(),
      ports: LocalBackendPorts(nowMs: () => _nowMs, newId: (prefix) => '${prefix}_off'),
    );
    await officer.signUp('officer@example.com', 'Officer', 'secret');

    expect(
      await officer.transport.update(
        RemoteTables.guilds,
        <String, Object?>{'leader_id': officer.session!.userId},
        equals: <String, Object?>{'id': created.guild!.id},
      ),
      remoteGuildLeaderIdLocked,
    );
    expect(transport.tables[RemoteTables.guilds]!.single['leader_id'], leader.session!.userId);
  });
}
