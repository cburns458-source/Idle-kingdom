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

  test('signs up without a username, then names the account from the first character', () async {
    final storage = MemorySaveStorage();
    final service = _service(storage);
    final created = await service.signUp('hero@example.com', '', 'secret');
    expect(created.ok, isTrue);
    expect(isPendingAccountUsername(service.session!.username), isTrue);

    expect((await service.signUp('alt@example.com', 'H', 'secret')).reason, contains('username'));
    expect((await service.claimAccountUsername('A')).reason, 'Enter a name to continue.');
    expect((await service.claimAccountUsername('Hero')).ok, isTrue);
    expect(service.session?.username, 'Hero');
    expect((await service.profile(service.session!.userId))?.username, 'Hero');

    expect((await service.claimAccountUsername('Later')).ok, isTrue);
    expect(service.session?.username, 'Hero');

    final rival = _service(storage, idOffset: 100);
    await rival.signUp('rival@example.com', '', 'secret');
    expect((await rival.claimAccountUsername('Hero')).reason, 'That name is taken.');
    expect(isPendingAccountUsername(rival.session!.username), isTrue);
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

    // Pushing refreshes the profile. Boards stay untouched until a ranking update.
    final profile = await service.profile(service.session!.userId);
    expect(profile?.username, 'Hero');
    expect(await service.leaderboard(boardTotalLevel), isEmpty);

    await service.submitLeaderboard(db, pushed.save!);
    expect((await service.leaderboard(boardTotalLevel)).single.username, 'Hero');
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

  test('hides pending stand-in names from Nearby until a character is named', () async {
    final storage = MemorySaveStorage();
    final pending = _service(storage);
    await pending.signUp('new@example.com', '', 'secret');
    expect(isPendingAccountUsername(pending.session!.username), isTrue);
    final save = createNewSave(_database(), _nowMs).copyWith(currentLocationId: 'LOC-0028');
    expect(await pending.publishPresence(presenceFromSave(save)), isNull);

    // A leftover row from before this rule still must not appear.
    pending.backend.upsertPresence(pending.session!, presenceFromSave(save));

    final watcher = _service(storage, startMs: _nowMs + 1000, idOffset: 100);
    await watcher.signUp('watcher@example.com', 'Watcher', 'secret');
    expect(await watcher.peersAtLocation('LOC-0028'), isEmpty);
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

  test('folds the account score into a board that has no row for it yet', () {
    final db = _database();
    final save = createNewSave(db, _nowMs).copyWith(characterName: 'Vari');
    final board = skillBoardKey('SKL-0004');

    final filled = mergeLiveLeaderboardScore(
      stored: const <LeaderboardEntry>[],
      boardKey: board,
      db: db,
      save: save,
      userId: 'usr_1',
      username: 'Vari',
      appearance: save.appearance,
    );
    expect(filled.single.username, 'Vari');
    expect(filled.single.rank, 1);
    expect(filled.single.boardKey, board);
  });

  test('the live score replaces a stale stored row and takes its place in order', () {
    final db = _database();
    final save = createNewSave(db, _nowMs).copyWith(characterName: 'Vari');
    final board = skillBoardKey('SKL-0004');
    final stale = LeaderboardEntry(
      userId: 'usr_1',
      username: 'Vari',
      appearance: save.appearance,
      guildName: null,
      boardKey: board,
      value: 0,
      rank: 2,
    );
    final rival = LeaderboardEntry(
      userId: 'usr_2',
      username: 'Rival',
      appearance: save.appearance,
      guildName: null,
      boardKey: board,
      value: 1,
      rank: 1,
    );

    final merged = mergeLiveLeaderboardScore(
      stored: <LeaderboardEntry>[rival, stale],
      boardKey: board,
      db: db,
      save: save.copyWith(
        skills: <SkillProgress>[
          for (final skill in save.skills)
            skill.skillId == 'SKL-0004' ? skill.copyWith(level: 40) : skill,
        ],
      ),
      userId: 'usr_1',
      username: 'Vari',
      appearance: save.appearance,
    );

    expect(merged.map((entry) => entry.username), <String>['Vari', 'Rival']);
    expect(merged.first.value, 40);
    expect(merged.first.rank, 1);
    expect(merged.where((entry) => entry.userId == 'usr_1'), hasLength(1));
  });

  test('leaves a guild board to the backend, whose value is the whole roster', () {
    final db = _database();
    final save = createNewSave(db, _nowMs).copyWith(characterName: 'Vari');
    expect(
      mergeLiveLeaderboardScore(
        stored: const <LeaderboardEntry>[],
        boardKey: boardGuildTotalLevel,
        db: db,
        save: save,
        userId: 'usr_1',
        username: 'Vari',
        appearance: save.appearance,
      ),
      isEmpty,
    );
  });

  test('the total level board carries experience under the level', () {
    final db = _database();
    final save = createNewSave(db, _nowMs).copyWith(characterName: 'Vari');
    final earned = save.copyWith(
      skills: <SkillProgress>[
        for (final skill in save.skills)
          skill.skillId == 'SKL-0004' ? skill.copyWith(level: 40, xp: 120000) : skill,
      ],
    );

    final merged = mergeLiveLeaderboardScore(
      stored: const <LeaderboardEntry>[],
      boardKey: boardTotalLevel,
      db: db,
      save: earned,
      userId: 'usr_1',
      username: 'Vari',
      appearance: save.appearance,
    );

    expect(merged.single.value, totalLevel(earned));
    expect(merged.single.secondaryValue, totalSkillXp(earned));
  });

  test('a fighter is taken off the pacifist board, and a peaceful player stays on', () {
    final db = _database();
    final save = createNewSave(db, _nowMs).copyWith(characterName: 'Vari');

    final peaceful = mergeLiveLeaderboardScore(
      stored: const <LeaderboardEntry>[],
      boardKey: boardPacifistTotalLevel,
      db: db,
      save: save,
      userId: 'usr_1',
      username: 'Vari',
      appearance: save.appearance,
    );
    expect(peaceful.single.value, totalLevel(save));

    final fighter = save.copyWith(
      skills: <SkillProgress>[
        for (final skill in save.skills)
          skill.skillId == combatSkillId ? skill.copyWith(level: 2) : skill,
      ],
    );
    final stale = LeaderboardEntry(
      userId: 'usr_1',
      username: 'Vari',
      appearance: save.appearance,
      guildName: null,
      boardKey: boardPacifistTotalLevel,
      value: 13,
      rank: 1,
    );

    // The row it wrote while still peaceful goes with it.
    expect(
      mergeLiveLeaderboardScore(
        stored: <LeaderboardEntry>[stale],
        boardKey: boardPacifistTotalLevel,
        db: db,
        save: fighter,
        userId: 'usr_1',
        username: 'Vari',
        appearance: save.appearance,
      ),
      isEmpty,
    );
  });

  test('submitting a ranking puts a peaceful player on both total boards', () async {
    final storage = MemorySaveStorage();
    final service = _service(storage);
    await service.signUp('vari@example.com', 'Vari', 'secret');
    final db = _database();
    final save = createNewSave(db, _nowMs).copyWith(characterName: 'Vari');

    await service.submitLeaderboard(db, save);

    final total = await service.leaderboard(boardTotalLevel);
    expect(total.single.value, totalLevel(save));
    expect(total.single.secondaryValue, totalSkillXp(save));

    final pacifist = await service.leaderboard(boardPacifistTotalLevel);
    expect(pacifist.single.value, totalLevel(save));

    final fighter = save.copyWith(
      skills: <SkillProgress>[
        for (final skill in save.skills)
          skill.skillId == combatSkillId ? skill.copyWith(level: 2) : skill,
      ],
    );
    await service.submitLeaderboard(db, fighter);

    expect(await service.leaderboard(boardPacifistTotalLevel), isEmpty);
    expect((await service.leaderboard(boardTotalLevel)).single.value, totalLevel(fighter));
  });

  test('a ranking submit publishes equipped gear onto the public profile', () async {
    final storage = MemorySaveStorage();
    final service = _service(storage);
    await service.signUp('hero@example.com', 'Hero', 'secret');
    final db = _database();
    final save = equipStackToSlot(
      createNewSave(db, _nowMs).copyWith(characterName: 'Hero'),
      weaponToolSlotId,
      'ITEM-0110',
      1,
    );

    await service.submitLeaderboard(db, save);
    final profile = await service.publicProfile(service.session!.userId);
    expect(profile, isNotNull);
    expect(profile!.publicEquipment, isNotNull);
    expect(profile.publicEquipment!.single.itemId, 'ITEM-0110');
    expect(profile.publicEquipment!.single.slotId, weaponToolSlotId);
  });

  test('a ranking submit publishes a name color only when asked', () async {
    final storage = MemorySaveStorage();
    final service = _service(storage);
    await service.signUp('hero@example.com', 'Hero', 'secret');
    final db = _database();
    final save = createNewSave(db, _nowMs).copyWith(characterName: 'Hero');
    final userId = service.session!.userId;

    await service.submitLeaderboard(db, save, nameColor: '#fa3');
    expect((await service.profile(userId))?.nameColor, isNull);
    expect(await service.publishedNameColors(<String>[userId]), isEmpty);

    await service.submitLeaderboard(db, save, nameColor: '#fa3', publishNameColor: true);
    expect((await service.profile(userId))?.nameColor, '#FFAA33');
    expect(await service.publishedNameColors(<String>[userId]), <String, String>{
      userId: '#FFAA33',
    });

    await service.submitLeaderboard(db, save, nameColor: 'nope', publishNameColor: true);
    expect((await service.profile(userId))?.nameColor, isNull);
    expect(await service.publishedNameColors(<String>[userId]), isEmpty);
  });

  test('counts unread public chat from other players after a cursor', () async {
    final storage = MemorySaveStorage();
    final hero = _service(storage);
    await hero.signUp('hero@example.com', 'Hero', 'secret');
    final rival = _service(storage, startMs: _nowMs + 2000, idOffset: 100);
    await rival.signUp('rival@example.com', 'Rival', 'secret');

    const room = ChatChannel.global();
    expect((await rival.sendChat(room, 'Hello global')).ok, isTrue);

    expect((await hero.signIn('hero@example.com', 'secret')).ok, isTrue);
    expect(await hero.countUnreadChat(room, null), 1);
    expect(await hero.countUnreadChat(room, isoFromMs(_nowMs + 1000)), 1);
    expect(await hero.countUnreadChat(room, isoFromMs(_nowMs + 3000)), 0);

    expect((await rival.signIn('rival@example.com', 'secret')).ok, isTrue);
    expect(await rival.countUnreadChat(room, null), 0);
  });
}
