import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';
import 'package:test/test.dart';

const num _nowMs = 1786568400000;

const CreateGuildInput _ironLeague = CreateGuildInput(
  name: 'Iron League',
  tag: 'IRN',
  description: 'Hammer and anvil.',
  emblem: GuildEmblem(color: '#3d5a80', symbol: 'shield'),
);

GameDatabase _database() => assertGameDatabaseShape(contentDatabaseJson());

RemoteMultiplayerService _service(FakeTransport transport, {num startMs = _nowMs}) {
  var counter = 0;
  return RemoteMultiplayerService(
    transport: transport,
    storage: MemorySaveStorage(),
    ports: LocalBackendPorts(
      nowMs: () => startMs,
      newId: (prefix) => '${prefix}_${(counter += 1).toString().padLeft(4, '0')}',
    ),
  );
}

/// A signed-in player on their own device, sharing one backend with the others.
Future<RemoteMultiplayerService> _player(
  FakeTransport transport,
  String email,
  String username,
) async {
  final service = _service(transport);
  final created = await service.signUp(email, username, 'secret');
  expect(created.ok, isTrue, reason: created.reason);
  return service;
}

void main() {
  test('a guild founded on one device is on the roster of another', () async {
    final transport = FakeTransport();
    final leader = await _player(transport, 'leader@example.com', 'Leader');
    final joiner = await _player(transport, 'joiner@example.com', 'Joiner');

    final created = await leader.createGuild(_ironLeague, guildCreateGoldCost);
    expect(created.ok, isTrue, reason: created.reason);
    expect(created.goldCost, guildCreateGoldCost);

    // The other device knew nothing about it and can still see all of it.
    final listings = await joiner.listGuilds();
    expect(listings, hasLength(1));
    expect(listings.single.guild.name, 'Iron League');
    expect(listings.single.guild.tag, 'IRN');
    expect(listings.single.guild.emblem.symbol, 'shield');
    expect(listings.single.memberCount, 1);

    final joined = await joiner.applyToGuild(created.guild!.id, '');
    expect(joined.ok, isTrue, reason: joined.reason);
    expect(joined.joined, isTrue, reason: 'a new guild is open to join');

    final roster = await leader.guildMembers(created.guild!.id);
    expect(roster.map((member) => member.username), <String>['Leader', 'Joiner']);
    expect(roster.first.role, guildRoleLeader);
    expect(roster.last.role, guildRoleRecruit);
    expect(await joiner.currentGuildId(), created.guild!.id);
  });

  test('the database settles a race for a name, and says so plainly', () async {
    final transport = FakeTransport();
    final first = await _player(transport, 'first@example.com', 'First');
    final second = await _player(transport, 'second@example.com', 'Second');

    expect((await first.createGuild(_ironLeague, guildCreateGoldCost)).ok, isTrue);

    final sameName = await second.createGuild(_ironLeague, guildCreateGoldCost);
    expect(sameName.ok, isFalse);
    expect(sameName.reason, remoteGuildNameTaken);

    // A different name with the same tag loses the same way.
    final sameTag = await second.createGuild(
      const CreateGuildInput(name: 'Iron Brotherhood', tag: 'IRN', emblem: GuildEmblem(color: '#3d5a80', symbol: 'shield')),
      guildCreateGoldCost,
    );
    expect(sameTag.reason, remoteGuildNameTaken);
  });

  test('a guild refuses what it always refused, over the wire too', () async {
    final transport = FakeTransport();
    final leader = await _player(transport, 'leader@example.com', 'Leader');

    final poor = await leader.createGuild(_ironLeague, guildCreateGoldCost - 1);
    expect(poor.reason, contains('costs'));
    expect(
      (await leader.createGuild(
        const CreateGuildInput(name: 'Ok', tag: 'OKY', emblem: GuildEmblem(color: '#3d5a80', symbol: 'shield')),
        guildCreateGoldCost,
      )).reason,
      'Guild name needs at least 3 characters.',
    );
    expect(
      (await leader.createGuild(
        const CreateGuildInput(name: 'Long Enough', tag: 'X', emblem: GuildEmblem(color: '#3d5a80', symbol: 'shield')),
        guildCreateGoldCost,
      )).reason,
      'Guild tag must be 2–4 letters.',
    );

    expect((await leader.createGuild(_ironLeague, guildCreateGoldCost)).ok, isTrue);
    final twice = await leader.createGuild(
      const CreateGuildInput(name: 'Second Home', tag: 'SND', emblem: GuildEmblem(color: '#3d5a80', symbol: 'shield')),
      guildCreateGoldCost,
    );
    expect(twice.reason, 'Leave your current guild before creating another.');
  });

  test('a closed guild collects applications its leader decides', () async {
    final transport = FakeTransport();
    final leader = await _player(transport, 'leader@example.com', 'Leader');
    final hopeful = await _player(transport, 'hopeful@example.com', 'Hopeful');

    final created = await leader.createGuild(_ironLeague, guildCreateGoldCost);
    final guildId = created.guild!.id;
    expect((await leader.setGuildJoinPolicy(guildId, guildJoinClosed)).ok, isTrue);

    final asked = await hopeful.applyToGuild(guildId, 'Let me in, please.');
    expect(asked.ok, isTrue, reason: asked.reason);
    expect(asked.joined, isFalse);
    expect(await hopeful.currentGuildId(), isNull);

    final again = await hopeful.applyToGuild(guildId, 'Still here.');
    expect(again.reason, 'Application already pending.');

    final pending = await leader.guildApplications(guildId);
    expect(pending, hasLength(1));
    expect(pending.single.username, 'Hopeful');
    expect(pending.single.message, 'Let me in, please.');
    expect(pending.single.guest, isFalse);

    // Only the leader decides; the applicant cannot wave themselves through.
    expect(
      (await hopeful.decideGuildApplication(pending.single.id, true)).reason,
      'Only the guild leader can decide applications.',
    );

    expect((await leader.decideGuildApplication(pending.single.id, true)).ok, isTrue);
    expect(await hopeful.currentGuildId(), guildId);
    expect(await leader.guildApplications(guildId), isEmpty);
  });

  test('a leader promotes a member, and nobody else can', () async {
    final transport = FakeTransport();
    final leader = await _player(transport, 'leader@example.com', 'Leader');
    final member = await _player(transport, 'member@example.com', 'Member');

    final created = await leader.createGuild(_ironLeague, guildCreateGoldCost);
    final guildId = created.guild!.id;
    await member.applyToGuild(guildId, '');
    final memberId = member.session!.userId;

    expect(
      (await member.setGuildMemberRole(guildId, memberId, guildRoleOfficer)).reason,
      'Only the leader can change roles.',
    );
    expect((await leader.setGuildMemberRole(guildId, memberId, guildRoleOfficer)).ok, isTrue);

    final roster = await member.guildMembers(guildId);
    expect(roster.firstWhere((row) => row.userId == memberId).role, guildRoleOfficer);

    expect(
      (await leader.setGuildMemberRole(guildId, memberId, guildRoleLeader)).reason,
      'Transfer leadership is not available yet.',
    );
  });

  test('a guest sits in the chat without joining the roster', () async {
    final transport = FakeTransport();
    final leader = await _player(transport, 'leader@example.com', 'Leader');
    final visitor = await _player(transport, 'visitor@example.com', 'Visitor');

    final created = await leader.createGuild(_ironLeague, guildCreateGoldCost);
    final guildId = created.guild!.id;
    expect((await leader.setGuildGuestAutoAccept(guildId, true)).ok, isTrue);

    final visiting = await visitor.joinAsGuest(guildId, '');
    expect(visiting.ok, isTrue, reason: visiting.reason);
    expect(visiting.joined, isTrue);
    expect(await visitor.currentGuestGuildId(), guildId);
    expect(await visitor.currentGuildId(), isNull);
    expect(await leader.guildMembers(guildId), hasLength(1));

    expect((await visitor.joinAsGuest(guildId, '')).reason, 'Already a guest of that guild.');
    expect((await visitor.leaveGuest()).ok, isTrue);
    expect(await visitor.currentGuestGuildId(), isNull);
    expect((await visitor.leaveGuest()).reason, 'Not a guest of a guild.');
  });

  test('the last member out closes the guild, and a leader with company cannot', () async {
    final transport = FakeTransport();
    final leader = await _player(transport, 'leader@example.com', 'Leader');
    final member = await _player(transport, 'member@example.com', 'Member');

    final created = await leader.createGuild(_ironLeague, guildCreateGoldCost);
    final guildId = created.guild!.id;
    await member.applyToGuild(guildId, '');

    expect(
      (await leader.leaveGuild()).reason,
      'Transfer leadership or remove members before leaving.',
    );

    expect((await member.leaveGuild()).ok, isTrue);
    expect(await member.currentGuildId(), isNull);
    expect((await leader.leaveGuild()).ok, isTrue);
    expect(await leader.listGuilds(), isEmpty);
  });

  test('a hall is one hall: what one member donates, another sees', () async {
    final transport = FakeTransport();
    final leader = await _player(transport, 'leader@example.com', 'Leader');
    final member = await _player(transport, 'member@example.com', 'Member');
    final database = _database();

    final created = await leader.createGuild(_ironLeague, guildCreateGoldCost);
    final guildId = created.guild!.id;
    await member.applyToGuild(guildId, '');

    final fresh = await member.guildHall(guildId);
    expect(fresh!.debtRemaining, guildHallDebtGold);
    expect(fresh.storehouse, isEmpty);

    final donor = createNewSave(database, _nowMs).copyWith(
      inventory: const <InventoryStack>[InventoryStack(itemId: 'ITEM-0015', quantity: 60)],
    );
    final given = await leader.contributeHallItem(donor, 0, 60);
    expect(given.ok, isTrue, reason: given.reason);
    expect(given.save!.inventory, isEmpty);

    // The other member reads the same store house, not their own copy of one.
    final shared = await member.guildHall(guildId);
    expect(shared!.storehouse.single.itemId, 'ITEM-0015');
    expect(shared.storehouse.single.quantity, 60);

    // A recruit cannot pay the debt, so the leader promotes them first.
    expect(
      (await leader.setGuildMemberRole(
        guildId,
        member.session!.userId,
        guildRoleMember,
      )).ok,
      isTrue,
    );
    final payer = createNewSave(database, _nowMs).copyWith(gold: 400);
    final paid = await member.payGuildDebt(payer, 400);
    expect(paid.ok, isTrue, reason: paid.reason);
    expect(paid.save!.gold, 0);

    final afterPayment = await leader.guildHall(guildId);
    expect(afterPayment!.debtRemaining, guildHallDebtGold - 400);
    expect(afterPayment.debtPaidBy[member.session!.userId], 400);
  });

  test('a new guild starts with the same first project and challenge as offline', () async {
    final transport = FakeTransport();
    final leader = await _player(transport, 'leader@example.com', 'Leader');
    final created = await leader.createGuild(_ironLeague, guildCreateGoldCost);
    final guildId = created.guild!.id;

    final projects = await leader.guildProjects(guildId);
    expect(projects.single.name, guildStorehouseProjectName);
    expect(projects.single.goalAmount, guildStorehouseProjectGoal);

    final challenges = await leader.guildChallenges(guildId);
    expect(challenges.single.name, guildMonsterChallengeName);

    final gave = await leader.contributeGuildProject(projects.single.id, 250);
    expect(gave.ok, isTrue, reason: gave.reason);
    expect(gave.project!.contributed, 250);
    expect((await leader.guildProjects(guildId)).single.contributed, 250);
  });

  test('a leader edits the banner, the ranks, and the rank marks', () async {
    final transport = FakeTransport();
    final leader = await _player(transport, 'leader@example.com', 'Leader');
    final created = await leader.createGuild(_ironLeague, guildCreateGoldCost);
    final guildId = created.guild!.id;

    expect(
      (await leader.setGuildEmblem(
        guildId,
        const GuildEmblem(color: '#2f6b3a', symbol: 'tree'),
      )).ok,
      isTrue,
    );
    expect(
      (await leader.setGuildRankLabels(guildId, <GuildRankKey, String>{
        guildRoleOfficer: 'Forgemaster',
      })).ok,
      isTrue,
    );
    expect((await leader.setGuildRankIconTheme(guildId, guildRankIconThemeCrowns)).ok, isTrue);

    final read = await leader.guild(guildId);
    expect(read!.emblem.symbol, 'tree');
    expect(read.emblem.color, '#2f6b3a');
    expect(read.rankLabels[guildRoleOfficer], 'Forgemaster');
    // Renaming one rank leaves the rest as they were.
    expect(read.rankLabels[guildRoleRecruit], defaultGuildRankLabels[guildRoleRecruit]);
    expect(read.rankIconTheme, guildRankIconThemeCrowns);
    expect(read.description, 'Hammer and anvil.');
  });

  test('a ranking update carries the level the roster lists', () async {
    final transport = FakeTransport();
    final leader = await _player(transport, 'leader@example.com', 'Leader');
    final database = _database();

    final created = await leader.createGuild(_ironLeague, guildCreateGoldCost);
    final guildId = created.guild!.id;

    final save = createNewSave(database, _nowMs).copyWith(characterName: 'Rowan of Oak');
    expect((await leader.submitLeaderboard(database, save)).ok, isTrue);

    final roster = await leader.guildMembers(guildId);
    expect(roster.single.username, 'Rowan of Oak');
    expect(roster.single.totalLevel, totalLevel(save));
  });

  test('a refused write is reported rather than swallowed', () async {
    final transport = FakeTransport();
    final leader = await _player(transport, 'leader@example.com', 'Leader');

    transport.failOnce['insert:${RemoteTables.guilds}'] = 'permission denied for table guilds';
    final refused = await leader.createGuild(_ironLeague, guildCreateGoldCost);
    expect(refused.ok, isFalse);
    expect(refused.reason, 'permission denied for table guilds');
    expect(await leader.listGuilds(), isEmpty);
  });
}
