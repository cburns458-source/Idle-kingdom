import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_runtime/ik_runtime.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase database;

  setUpAll(() {
    database = assertGameDatabaseShape(contentDatabaseJson());
  });

  LocalMultiplayerBackend backend() {
    return LocalMultiplayerBackend(storage: MemorySaveStorage());
  }

  test('the demo guild is open, led by Mira, and has three members', () {
    final store = backend();
    store.ensureDemoWorld(database);

    final listings = store.listGuilds();
    expect(listings, hasLength(1));
    expect(listings.single.guild.id, demoGuildId);
    expect(listings.single.guild.name, demoGuildName);
    expect(listings.single.guild.leaderId, demoMiraId);
    expect(listings.single.guild.joinPolicy, guildJoinOpen);
    expect(listings.single.memberCount, 3);

    final members = store.guildMembers(demoGuildId);
    expect(
      members.map((row) => row.username),
      containsAll(<String>[demoMiraName, demoBramName, demoKaelName]),
    );
    expect(members.firstWhere((row) => row.userId == demoMiraId).role, guildRoleLeader);
  });

  test('demo presence is location-wide and a second seed does not duplicate', () {
    final store = backend();
    store.ensureDemoWorld(database);

    expect(store.listPresence(locationId: demoMiraLocationId).single.username, demoMiraName);
    expect(store.listPresence(locationId: demoBramLocationId).single.username, demoBramName);
    expect(store.listPresence(locationId: demoKaelLocationId).single.username, demoKaelName);
    expect(
      store.listPresence(locationId: demoMiraLocationId).single.currentActivityId,
      demoMiraActivityId,
    );

    store.ensureDemoWorld(database);
    expect(store.listGuilds(), hasLength(1));
    expect(store.listPresence(locationId: demoMiraLocationId), hasLength(1));
  });

  test('clearing the demo world leaves a real player untouched', () {
    final store = backend();
    store.ensureDemoWorld(database);
    final hero = store.signUp('hero@example.com', 'Hero', 'secret').session!;
    expect(store.applyToGuild(hero, demoGuildId, '').joined, isTrue);

    store.clearDemoWorld();

    expect(store.listGuilds(), isEmpty);
    expect(store.guildMembers(demoGuildId), isEmpty);
    expect(store.listPresence(includeExpired: true), isEmpty);
    expect(store.listChat(const ChatChannel.global(), hero.userId), isEmpty);
    expect(store.getProfile(demoMiraId), isNull);
    expect(store.getProfile(hero.userId)?.username, 'Hero');

    store.clearDemoWorld();
    expect(store.getProfile(hero.userId)?.username, 'Hero');
  });

  test('a player can join The Watch and leave it', () {
    final store = backend();
    store.ensureDemoWorld(database);
    final hero = store.signUp('hero@example.com', 'Hero', 'secret').session!;

    final joined = store.applyToGuild(hero, demoGuildId, '');
    expect(joined.ok, isTrue);
    expect(joined.joined, isTrue);
    expect(store.guildMembers(demoGuildId), hasLength(4));

    expect(store.leaveGuild(hero.userId).ok, isTrue);
    expect(store.guildMembers(demoGuildId), hasLength(3));
    expect(store.getGuild(demoGuildId)?.leaderId, demoMiraId);
  });

  test('demo characters publish race-specific portraits', () {
    final store = backend();
    store.ensureDemoWorld(database);
    expect(store.publicProfile(demoMiraId)!.raceId, 'RACE-0002');
    expect(store.publicProfile(demoBramId)!.raceId, 'RACE-0006');
    expect(store.publicProfile(demoKaelId)!.raceId, 'RACE-0004');
    expect(store.listPresence(locationId: demoMiraLocationId).single.raceId, 'RACE-0002');
  });

  test('demo characters wear a starter sword and shield on their public profile', () {
    final store = backend();
    store.ensureDemoWorld(database);
    final profile = store.publicProfile(demoMiraId);
    expect(profile, isNotNull);
    expect(profile!.publicEquipment, isNotNull);
    expect(
      profile.publicEquipment!.map((row) => row.itemId),
      containsAll(<String>['ITEM-0124', 'ITEM-0145']),
    );
  });

  test('friends and ignore lists, and ignored players drop out of nearby', () async {
    final storage = MemorySaveStorage();
    final service = LocalMultiplayerService(storage: storage);
    service.ensureDemoWorld(database);
    expect((await service.signUp('hero@example.com', 'Hero', 'secret')).ok, isTrue);

    expect((await service.sendFriendRequest(demoMiraId)).ok, isTrue);
    expect((await service.outgoingFriendRequests()).single.username, demoMiraName);

    expect((await service.peersAtLocation(demoMiraLocationId)).single.username, demoMiraName);
    await service.ignorePlayer(demoMiraId);
    expect(await service.peersAtLocation(demoMiraLocationId), isEmpty);
    expect((await service.ignoredPlayers()).single.username, demoMiraName);
    expect(await service.outgoingFriendRequests(), isEmpty);

    await service.unignorePlayer(demoMiraId);
    expect((await service.peersAtLocation(demoMiraLocationId)).single.username, demoMiraName);
  });

  test('a player can guest The Watch without joining the roster', () {
    final store = backend();
    store.ensureDemoWorld(database);
    expect(store.listGuilds().single.guild.guestAutoAccept, isTrue);

    final hero = store.signUp('hero@example.com', 'Hero', 'secret').session!;
    final guested = store.joinAsGuest(hero, demoGuildId, '');
    expect(guested.ok, isTrue);
    expect(guested.joined, isTrue);
    expect(store.guildMembers(demoGuildId), hasLength(3));
    expect(store.currentGuestGuildId(hero.userId), demoGuildId);

    final sent = store.sendChat(hero, ChatChannel.guild(demoGuildId), 'Hello from the road');
    expect(sent.ok, isTrue);
    expect(sent.message!.guest, isTrue);
    expect(sent.message!.guildTag, isNull);
  });

  test('global chat shows The Watch tag, stores raw text, and slurs disable chat', () {
    final store = backend();
    store.ensureDemoWorld(database);
    final hero = store.signUp('hero@example.com', 'Hero', 'secret').session!;

    final lines = chatLines(store.listChat(const ChatChannel.global(), hero.userId), hero.userId);
    expect(lines, hasLength(1));
    expect(lines.single.username, '[WCH] Mira');

    final stored = store.sendChat(hero, const ChatChannel.global(), 'what the fuck');
    expect(stored.ok, isTrue);
    expect(stored.message!.body, 'what the fuck');
    expect(
      chatLines(
        <ChatMessage>[stored.message!],
        hero.userId,
        filterProfanityEnabled: true,
      ).single.body,
      contains('*'),
    );

    final slur = store.sendChat(hero, const ChatChannel.local('LOC-0002'), 'nigger');
    expect(slur.ok, isFalse);
    expect(slur.reason, chatDisabledNotice);
    final later = store.sendChat(hero, const ChatChannel.global(), 'Hi again');
    expect(later.ok, isFalse);
    expect(later.reason, chatDisabledNotice);
  });
}
