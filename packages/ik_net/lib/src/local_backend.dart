import 'dart:convert';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'bazaar.dart';
import 'config.dart';
import 'demo_world.dart';
import 'local_db.dart';
import 'moderation.dart';
import 'results.dart';
import 'snapshots.dart';
import 'types.dart';

/// The host facilities the backend would otherwise reach for directly. Supplied
/// so a test — and the TypeScript parity fixtures — can pin both.
class LocalBackendPorts {
  const LocalBackendPorts({required this.nowMs, required this.newId});

  /// Wall clock in milliseconds.
  final num Function() nowMs;

  /// A fresh id for a row of the given kind, e.g. `usr` or `msg`.
  final String Function(String prefix) newId;

  /// The defaults a real client runs with: the system clock and random ids.
  factory LocalBackendPorts.system([math.Random? random]) {
    final rng = random ?? math.Random();
    return LocalBackendPorts(
      nowMs: () => DateTime.now().millisecondsSinceEpoch,
      newId: (prefix) {
        final noise = rng.nextInt(1 << 32).toRadixString(36);
        final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
        return '${prefix}_${noise}_$stamp';
      },
    );
  }
}

/// The display fields a roster or application row borrows from a player's
/// newest data, rather than from whatever was true when they joined.
class _MemberSnapshot {
  const _MemberSnapshot({
    required this.username,
    required this.appearance,
    required this.totalLevel,
  });

  final String username;
  final PlayerAppearance appearance;
  final num totalLevel;
}

/// A single-device backend: accounts, saves, boards, chat, guilds, presence,
/// bounty claims, and bazaar posts, all in one JSON document.
///
/// This is the reference implementation of the multiplayer semantics. It exists
/// so the game is playable and testable with no server at all, and so a remote
/// backend has something to agree with.
class LocalMultiplayerBackend {
  LocalMultiplayerBackend({required this.storage, LocalBackendPorts? ports})
    : ports = ports ?? LocalBackendPorts.system();

  final SaveStorage storage;
  final LocalBackendPorts ports;

  LocalDb _db() {
    final raw = storage.getItem(multiplayerLocalDbKey);
    if (raw == null || raw.isEmpty) return LocalDb.empty();
    try {
      return LocalDb.fromJson(jsonDecode(raw));
    } on Object {
      return LocalDb.empty();
    }
  }

  void _write(LocalDb db) {
    storage.setItem(multiplayerLocalDbKey, jsonEncode(db.toJson()));
  }

  num _now() => ports.nowMs();

  String _nowIso() => isoFromMs(ports.nowMs());

  String _newId(String prefix) => ports.newId(prefix);

  // --- Accounts -------------------------------------------------------------

  SessionResult signUp(String email, String username, String password) {
    final db = _db();
    final cleanEmail = email.trim().toLowerCase();
    final trimmedUser = username.trim();
    final cleanUser = trimmedUser.length > 24 ? trimmedUser.substring(0, 24) : trimmedUser;
    if (!cleanEmail.contains('@') || cleanUser.length < 2 || password.length < 4) {
      return const SessionResult.failed('Enter a valid email, username (2+), and password (4+).');
    }
    if (db.users.any((user) => user.email == cleanEmail)) {
      return const SessionResult.failed('An account with that email already exists.');
    }
    if (db.users.any((user) => user.username.toLowerCase() == cleanUser.toLowerCase())) {
      return const SessionResult.failed('That username is taken.');
    }
    final userId = _newId('usr');
    db.users.add(
      LocalAccount(userId: userId, email: cleanEmail, username: cleanUser, password: password),
    );
    db.profiles.add(
      MultiplayerProfile(
        userId: userId,
        username: cleanUser,
        appearance: defaultPlayerAppearance,
        guildId: null,
        guildName: null,
        privacyPublicSkills: true,
        updatedAt: _nowIso(),
      ),
    );
    _write(db);
    return SessionResult.ok(
      MultiplayerSession(
        userId: userId,
        email: cleanEmail,
        username: cleanUser,
        accessToken: 'local:$userId',
      ),
    );
  }

  SessionResult signIn(String email, String password) {
    final db = _db();
    final cleanEmail = email.trim().toLowerCase();
    final user = db.users.firstWhereOrNull(
      (row) => row.email == cleanEmail && row.password == password,
    );
    if (user == null) return const SessionResult.failed('Invalid email or password.');
    return SessionResult.ok(
      MultiplayerSession(
        userId: user.userId,
        email: user.email,
        username: user.username,
        accessToken: 'local:${user.userId}',
      ),
    );
  }

  MultiplayerProfile? getProfile(String userId) =>
      _db().profiles.firstWhereOrNull((row) => row.userId == userId);

  /// Gives an account authenticated elsewhere a profile row here.
  ///
  /// The screens this backend still owns — guilds, presence, public profiles —
  /// all hang off a profile, so an account that signed in against a remote
  /// backend needs one before it can join anything. Returns the row already
  /// present, so signing in twice does not reset a name or a guild.
  MultiplayerProfile registerProfile(String userId, String username) {
    final existing = getProfile(userId);
    if (existing != null) return existing;
    final db = _db();
    final profile = MultiplayerProfile(
      userId: userId,
      username: username,
      appearance: defaultPlayerAppearance,
      guildId: null,
      guildName: null,
      privacyPublicSkills: true,
      updatedAt: _nowIso(),
    );
    db.profiles.add(profile);
    _write(db);
    return profile;
  }

  MultiplayerProfile? upsertProfile(
    String userId, {
    PlayerAppearance? appearance,
    bool? privacyPublicSkills,
    String? username,
  }) {
    final db = _db();
    final index = db.profiles.indexWhere((row) => row.userId == userId);
    if (index < 0) return null;
    db.profiles[index] = db.profiles[index].copyWith(
      appearance: appearance,
      privacyPublicSkills: privacyPublicSkills,
      username: username,
      updatedAt: _nowIso(),
    );
    _write(db);
    return db.profiles[index];
  }

  // --- Cloud saves ----------------------------------------------------------

  CloudSaveRecord? readCloudSave(String userId) =>
      _db().saves.firstWhereOrNull((row) => row.userId == userId);

  /// Stores [save] as the account's cloud copy.
  ///
  /// A newer stored copy stops the write, so a stale device cannot quietly erase
  /// progress made elsewhere. [force] is the player answering that prompt: they
  /// have been shown the other save and chosen this one.
  CloudSaveWriteResult writeCloudSave(String userId, PlayerSave save, {bool force = false}) {
    final db = _db();
    final existing = db.saves.firstWhereOrNull((row) => row.userId == userId);
    if (!force &&
        existing != null &&
        jsDateParse(existing.updatedAt) > jsDateParse(save.updatedAt) &&
        existing.saveVersion >= save.saveVersion) {
      return CloudSaveWriteResult.failed(
        'A newer cloud save exists. Load it or overwrite carefully.',
        remote: existing,
      );
    }
    final record = CloudSaveRecord(
      userId: userId,
      saveVersion: save.saveVersion,
      updatedAt: isNotBlank(save.updatedAt) ? save.updatedAt : _nowIso(),
      payload: save,
    );
    db.saves = db.saves.where((row) => row.userId != userId).toList();
    db.saves.add(record);
    _write(db);
    return CloudSaveWriteResult.ok(record);
  }

  /// Every stored character except [excludeUserId], which is the signed-in player.
  List<ArenaOpponent> listArenaOpponents({String? excludeUserId}) {
    final db = _db();
    final rows = <ArenaOpponent>[];
    for (final save in db.saves) {
      if (excludeUserId != null && save.userId == excludeUserId) continue;
      final profile = db.profiles.firstWhereOrNull((row) => row.userId == save.userId);
      final username = isNotBlank(profile?.username)
          ? profile!.username
          : (isNotBlank(save.payload.characterName) ? save.payload.characterName! : save.userId);
      rows.add(
        ArenaOpponent(
          userId: save.userId,
          username: username,
          combatLevel: combatLevelOf(save.payload),
          totalLevel: totalLevel(save.payload),
          appearance: profile?.appearance ?? save.payload.appearance,
        ),
      );
    }
    rows.sort((a, b) {
      final byName = a.username.compareTo(b.username);
      return byName != 0 ? byName : a.userId.compareTo(b.userId);
    });
    return rows;
  }

  PlayerSave? opponentSave(String userId) {
    final record = readCloudSave(userId);
    if (record == null) return null;
    return parseSave(record.payload.toJson(), _now());
  }

  // --- Leaderboards ---------------------------------------------------------

  void submitLeaderboardSnapshot(GameDatabase gameDb, String userId, PlayerSave save) {
    if (getProfile(userId) == null) return;
    final snapshot = buildLeaderboardSnapshot(gameDb, save);
    final db = _db();
    final updatedAt = _nowIso();
    for (final board in snapshot.boards) {
      db.leaderboards = db.leaderboards
          .where((row) => !(row.userId == userId && row.boardKey == board.boardKey))
          .toList();
      db.leaderboards.add(
        LeaderboardRow(
          userId: userId,
          boardKey: board.boardKey,
          value: board.value,
          updatedAt: updatedAt,
        ),
      );
    }
    // Refresh the profile's cosmetics snapshot from the save.
    db.profiles = db.profiles
        .map(
          (row) => row.userId == userId
              ? row.copyWith(
                  appearance: save.appearance,
                  username: isNotBlank(save.characterName) ? save.characterName : row.username,
                  updatedAt: updatedAt,
                )
              : row,
        )
        .toList();
    _write(db);
  }

  List<LeaderboardEntry> listLeaderboard(MultiplayerBoardKey boardKey, [int limit = 25]) {
    final db = _db();
    if (boardKey == boardGuildTotalLevel) {
      final scored = db.guilds.map((guild) {
        final members = guildMembers(guild.id);
        num value = 0;
        for (final member in members) {
          value += member.totalLevel;
        }
        final leader =
            members.firstWhereOrNull((member) => member.userId == guild.leaderId) ??
            members.firstOrNull;
        return LeaderboardEntry(
          userId: guild.id,
          username: '[${guild.tag}] ${guild.name}',
          appearance: leader?.appearance ?? defaultPlayerAppearance,
          guildName: '${members.length}/$guildMaxMembers members',
          boardKey: boardKey,
          value: value,
          rank: 0,
          entryKind: LeaderboardEntryKind.guild,
          emblem: guild.emblem,
        );
      }).toList();
      mergeSort(
        scored,
        compare: (a, b) =>
            jsCompareThen(b.value - a.value, () => jsLocaleCompare(a.username, b.username)),
      );
      return scored
          .take(limit)
          .toList()
          .indexed
          .map((entry) => entry.$2.withRank(entry.$1 + 1))
          .toList();
    }
    final rows = db.leaderboards.where((row) => row.boardKey == boardKey).toList();
    mergeSort(
      rows,
      compare: (a, b) =>
          jsCompareThen(b.value - a.value, () => jsLocaleCompare(a.userId, b.userId)),
    );
    return rows.take(limit).toList().indexed.map((entry) {
      final row = entry.$2;
      final profile = db.profiles.firstWhereOrNull((candidate) => candidate.userId == row.userId);
      return LeaderboardEntry(
        userId: row.userId,
        username: profile?.username ?? 'Adventurer',
        appearance: profile?.appearance ?? defaultPlayerAppearance,
        guildName: profile?.guildName,
        boardKey: boardKey,
        value: row.value,
        rank: entry.$1 + 1,
        entryKind: LeaderboardEntryKind.player,
        emblem: null,
      );
    }).toList();
  }

  int _guildMemberCount(LocalDb db, String guildId) =>
      db.members.where((row) => row.guildId == guildId).length;

  bool _canSpeakInGuild(LocalDb db, String guildId, String userId) =>
      db.members.any((row) => row.guildId == guildId && row.userId == userId) ||
      db.guests.any((row) => row.guildId == guildId && row.userId == userId);

  GuildRecord? _guildForMember(LocalDb db, String userId) {
    final membership = db.members.firstWhereOrNull((row) => row.userId == userId);
    if (membership == null) return null;
    return db.guilds.firstWhereOrNull((row) => row.id == membership.guildId);
  }

  GuildGuest? _guestOf(LocalDb db, String userId) =>
      db.guests.firstWhereOrNull((row) => row.userId == userId);

  // --- Chat -----------------------------------------------------------------

  ChatSendResult sendChat(MultiplayerSession session, ChatChannel channel, String body) {
    final trimmedBody = body.trim();
    final trimmed = trimmedBody.length > 240 ? trimmedBody.substring(0, 240) : trimmedBody;
    if (trimmed.isEmpty) return const ChatSendResult.failed('Message is empty.');
    final key = chatChannelKey(channel);
    final cooldown = switch (channel) {
      GlobalChatChannel() => ChatCooldownSeconds.global,
      LocalChatChannel() => ChatCooldownSeconds.local,
      GuildChatChannel() => ChatCooldownSeconds.guild,
      DirectChatChannel() => ChatCooldownSeconds.dm,
    };
    final db = _db();
    final accountIndex = db.users.indexWhere((row) => row.userId == session.userId);
    if (accountIndex >= 0 && db.users[accountIndex].chatBanned) {
      return const ChatSendResult.failed(chatDisabledNotice);
    }
    if (containsSlur(trimmed)) {
      if (accountIndex >= 0) {
        db.users[accountIndex] = db.users[accountIndex].copyWith(chatBanned: true);
        _write(db);
      }
      return const ChatSendResult.failed(chatDisabledNotice);
    }
    final stampKey = '${session.userId}:$key';
    final last = db.lastChatAt[stampKey];
    if (isNotBlank(last) && _now() - jsDateParse(last) < cooldown * 1000) {
      final wait = ((cooldown * 1000 - (_now() - jsDateParse(last))) / 1000).ceil();
      return ChatSendResult.failed('Wait ${wait}s before chatting again.');
    }
    if (channel is GuildChatChannel && !_canSpeakInGuild(db, channel.guildId, session.userId)) {
      return const ChatSendResult.failed('Join the guild to use guild chat.');
    }
    final memberGuild = _guildForMember(db, session.userId);
    String? rankLabel;
    String? rankIcon;
    var guest = false;
    if (channel is GuildChatChannel) {
      final member = db.members.firstWhereOrNull(
        (row) => row.guildId == channel.guildId && row.userId == session.userId,
      );
      if (member != null) {
        final guild = db.guilds.firstWhereOrNull((row) => row.id == channel.guildId);
        rankLabel = guild?.rankLabels[member.role] ?? defaultGuildRankLabels[member.role];
        rankIcon = guildRankIcon(guild?.rankIconTheme ?? guildRankIconThemeStripes, member.role);
      } else {
        guest = true;
      }
    }
    final message = ChatMessage(
      id: _newId('msg'),
      channelKey: key,
      userId: session.userId,
      username: session.username,
      body: trimmed,
      createdAt: _nowIso(),
      guildTag: memberGuild?.tag,
      rankLabel: rankLabel,
      rankIcon: rankIcon,
      guest: guest,
    );
    db.messages.add(message);
    db.lastChatAt[stampKey] = message.createdAt;
    _write(db);
    return ChatSendResult.ok(message);
  }

  List<ChatMessage> listChat(ChatChannel channel, String viewerId, [int limit = 50]) {
    final db = _db();
    final key = chatChannelKey(channel);
    final silenced = _silencedBy(db, viewerId);
    final rows = db.messages
        .where((row) => row.channelKey == key && !silenced.contains(row.userId))
        .toList();
    mergeSort(
      rows,
      compare: (a, b) =>
          jsCompareThen(jsDateParse(a.createdAt) - jsDateParse(b.createdAt), () => 0),
    );
    return _lastN(rows, limit);
  }

  /// Direct messages involving the viewer, inbox-style, oldest first.
  List<ChatMessage> listDirectMessages(String viewerId, [int limit = 80]) {
    final db = _db();
    final silenced = _silencedBy(db, viewerId);
    final rows = db.messages
        .where(
          (row) =>
              row.channelKey.startsWith('dm:') &&
              row.channelKey.contains(viewerId) &&
              !silenced.contains(row.userId),
        )
        .toList();
    mergeSort(
      rows,
      compare: (a, b) =>
          jsCompareThen(jsDateParse(a.createdAt) - jsDateParse(b.createdAt), () => 0),
    );
    return _lastN(rows, limit);
  }

  /// Direct messages from other players newer than [sinceIso], exclusive.
  int countUnreadDirectMessages(String viewerId, String? sinceIso) {
    final sinceMs = sinceIso != null ? jsDateParse(sinceIso) : 0;
    return listDirectMessages(
      viewerId,
      200,
    ).where((row) => row.userId != viewerId && jsDateParse(row.createdAt) > sinceMs).length;
  }

  Set<String> _silencedBy(LocalDb db, String viewerId) => <String>{
    for (final row in db.mutes)
      if (row.userId == viewerId) row.otherUserId,
    for (final row in db.blocks)
      if (row.userId == viewerId) row.otherUserId,
  };

  List<T> _lastN<T>(List<T> rows, int limit) =>
      rows.length <= limit ? rows : rows.sublist(rows.length - limit);

  void muteUser(String userId, String mutedUserId) {
    final db = _db();
    if (db.mutes.any((row) => row.userId == userId && row.otherUserId == mutedUserId)) return;
    db.mutes.add(UserPair(userId: userId, otherUserId: mutedUserId));
    _write(db);
  }

  void blockUser(String userId, String blockedUserId) {
    final db = _db();
    if (db.blocks.any((row) => row.userId == userId && row.otherUserId == blockedUserId)) return;
    db.blocks.add(UserPair(userId: userId, otherUserId: blockedUserId));
    _dropRelationship(db, userId, blockedUserId);
    _write(db);
  }

  void unblockUser(String userId, String blockedUserId) {
    final db = _db();
    db.blocks = db.blocks
        .where((row) => !(row.userId == userId && row.otherUserId == blockedUserId))
        .toList();
    _write(db);
  }

  Set<String> blockedIds(String userId) => <String>{
    for (final row in _db().blocks)
      if (row.userId == userId) row.otherUserId,
  };

  ActionResult removeFriend(String userId, String otherUserId) {
    if (userId == otherUserId) return const ActionResult.failed('Cannot unfriend yourself.');
    final db = _db();
    final pair = <String>[userId, otherUserId]..sort();
    final before = db.friends.length;
    db.friends = db.friends
        .where((row) => !(row.userA == pair[0] && row.userB == pair[1]))
        .toList();
    if (db.friends.length == before) {
      return const ActionResult.failed('Not friends.');
    }
    _write(db);
    return const ActionResult.ok();
  }

  List<SocialContact> listFriends(String userId) {
    final db = _db();
    final others = <String>[
      for (final row in db.friends)
        if (row.userA == userId) row.userB else if (row.userB == userId) row.userA,
    ];
    return [for (final other in others) ?_contact(db, other)];
  }

  List<SocialContact> listIncomingFriendRequests(String userId) {
    final db = _db();
    return [
      for (final row in db.friendRequests)
        if (row.toUserId == userId) ?_contact(db, row.fromUserId),
    ];
  }

  List<SocialContact> listOutgoingFriendRequests(String userId) {
    final db = _db();
    return [
      for (final row in db.friendRequests)
        if (row.fromUserId == userId) ?_contact(db, row.toUserId),
    ];
  }

  List<SocialContact> listIgnored(String userId) {
    final db = _db();
    return [for (final other in blockedIds(userId)) ?_contact(db, other)];
  }

  SocialContact? _contact(LocalDb db, String userId) {
    final profile = db.profiles.firstWhereOrNull((row) => row.userId == userId);
    if (profile == null) return null;
    return SocialContact(
      userId: profile.userId,
      username: profile.username,
      appearance: profile.appearance,
      guildName: profile.guildName,
    );
  }

  void _dropRelationship(LocalDb db, String userId, String otherUserId) {
    final pair = <String>[userId, otherUserId]..sort();
    db.friends = db.friends
        .where((row) => !(row.userA == pair[0] && row.userB == pair[1]))
        .toList();
    db.friendRequests = db.friendRequests
        .where(
          (row) =>
              !((row.fromUserId == userId && row.toUserId == otherUserId) ||
                  (row.fromUserId == otherUserId && row.toUserId == userId)),
        )
        .toList();
  }

  void reportUser(String reporterId, String targetUserId, String reason) {
    final db = _db();
    final trimmed = reason.trim();
    final clipped = trimmed.length > 200 ? trimmed.substring(0, 200) : trimmed;
    db.reports.add(
      PlayerReport(
        id: _newId('rpt'),
        reporterId: reporterId,
        targetUserId: targetUserId,
        reason: clipped.isEmpty ? 'Unspecified' : clipped,
        createdAt: _nowIso(),
      ),
    );
    _write(db);
  }

  // --- Guilds ---------------------------------------------------------------

  /// The name, portrait, and level a roster row shows, taken from the newest
  /// source that has them: the cloud save, then the profile, then the session.
  _MemberSnapshot _memberSnapshot(LocalDb db, String userId, String username) {
    final profile = db.profiles.firstWhereOrNull((row) => row.userId == userId);
    final cloud = db.saves.firstWhereOrNull((row) => row.userId == userId);
    final level = cloud != null ? totalLevel(cloud.payload) : 1;
    final saveName = cloud?.payload.characterName?.trim();
    return _MemberSnapshot(
      username: isNotBlank(saveName) ? saveName! : (profile?.username ?? username),
      appearance: cloud?.payload.appearance ?? profile?.appearance ?? defaultPlayerAppearance,
      totalLevel: math.max(1, level),
    );
  }

  CreateGuildResult createGuild(
    MultiplayerSession session,
    CreateGuildInput input,
    num goldAvailable,
  ) {
    final trimmedName = input.name.trim();
    final clean = trimmedName.length > 28 ? trimmedName.substring(0, 28) : trimmedName;
    final letters = input.tag.replaceAll(RegExp('[^a-zA-Z]'), '').toUpperCase();
    final tag = letters.length > 4 ? letters.substring(0, 4) : letters;
    if (clean.length < 3) {
      return const CreateGuildResult.failed('Guild name needs at least 3 characters.');
    }
    if (tag.length < 2 || tag.length > 4) {
      return const CreateGuildResult.failed('Guild tag must be 2–4 letters.');
    }
    if (goldAvailable < guildCreateGoldCost) {
      return CreateGuildResult.failed(
        'Creating a guild costs ${jsNumberToString(guildCreateGoldCost)} gold.',
      );
    }
    final db = _db();
    if (db.members.any((row) => row.userId == session.userId)) {
      return const CreateGuildResult.failed('Leave your current guild before creating another.');
    }
    if (db.guilds.any((row) => row.name.toLowerCase() == clean.toLowerCase())) {
      return const CreateGuildResult.failed('That guild name is taken.');
    }
    if (db.guilds.any((row) => row.tag.toUpperCase() == tag)) {
      return const CreateGuildResult.failed('That guild tag is taken.');
    }
    final snapshot = _memberSnapshot(db, session.userId, session.username);
    final description = (input.description ?? '').trim();
    final guild = GuildRecord(
      id: _newId('gld'),
      name: clean,
      tag: tag,
      description: description.length > 160 ? description.substring(0, 160) : description,
      emblem: normalizeEmblem(input.emblem),
      leaderId: session.userId,
      joinPolicy: guildJoinOpen,
      rankLabels: <GuildRankKey, String>{...defaultGuildRankLabels},
      createdAt: _nowIso(),
    );
    db.guilds.add(guild);
    db.members.add(
      GuildMember(
        guildId: guild.id,
        userId: session.userId,
        username: snapshot.username,
        role: guildRoleLeader,
        joinedAt: _nowIso(),
        appearance: snapshot.appearance,
        totalLevel: snapshot.totalLevel,
      ),
    );
    db.profiles = _withGuild(db.profiles, session.userId, guild);
    db.projects.add(
      GuildProject(
        id: _newId('gprj'),
        guildId: guild.id,
        name: 'Guild Storehouse',
        description: 'Pool resources for cosmetic recognition.',
        goalAmount: 1000,
        contributed: 0,
        rewardLabel: 'Guild banner cosmetic (recognition)',
      ),
    );
    db.challenges.add(
      GuildChallenge(
        id: _newId('gch'),
        guildId: guild.id,
        name: 'Weekly Monster Hunt',
        boardKey: boardMonstersKilled,
        goalValue: 100,
        currentValue: 0,
      ),
    );
    db.halls.add(GuildHallState.fresh(guild.id));
    _write(db);
    return CreateGuildResult.ok(guild, guildCreateGoldCost);
  }

  List<MultiplayerProfile> _withGuild(
    List<MultiplayerProfile> profiles,
    String userId,
    GuildRecord? guild,
  ) => profiles
      .map(
        (row) => row.userId != userId
            ? row
            : guild == null
            ? row.copyWith(clearGuild: true, updatedAt: _nowIso())
            : row.copyWith(guildId: guild.id, guildName: guild.name, updatedAt: _nowIso()),
      )
      .toList();

  List<GuildListing> listGuilds() {
    final db = _db();
    final listings = db.guilds
        .map((guild) => GuildListing(guild: guild, memberCount: _guildMemberCount(db, guild.id)))
        .toList();
    mergeSort(listings, compare: (a, b) => jsLocaleCompare(a.guild.name, b.guild.name));
    return listings;
  }

  GuildRecord? getGuild(String guildId) =>
      _db().guilds.firstWhereOrNull((row) => row.id == guildId);

  List<GuildMember> guildMembers(String guildId) {
    final db = _db();
    return db.members.where((row) => row.guildId == guildId).map((row) {
      final snapshot = _memberSnapshot(db, row.userId, row.username);
      return row.copyWith(
        role: normalizeRole(row.role),
        username: snapshot.username,
        appearance: snapshot.appearance,
        totalLevel: snapshot.totalLevel,
      );
    }).toList();
  }

  ApplyToGuildResult applyToGuild(MultiplayerSession session, String guildId, String message) {
    final db = _db();
    final guild = db.guilds.firstWhereOrNull((row) => row.id == guildId);
    if (guild == null) return const ApplyToGuildResult.failed('Guild not found.');
    if (db.members.any((row) => row.userId == session.userId)) {
      return const ApplyToGuildResult.failed('Already in a guild.');
    }
    if (_guildMemberCount(db, guildId) >= guildMaxMembers) {
      return ApplyToGuildResult.failed('That guild is full ($guildMaxMembers members).');
    }
    if (guild.joinPolicy == guildJoinOpen) {
      final snapshot = _memberSnapshot(db, session.userId, session.username);
      db.members.add(
        GuildMember(
          guildId: guild.id,
          userId: session.userId,
          username: snapshot.username,
          role: guildRoleRecruit,
          joinedAt: _nowIso(),
          appearance: snapshot.appearance,
          totalLevel: snapshot.totalLevel,
        ),
      );
      db.profiles = _withGuild(db.profiles, session.userId, guild);
      db.applications = db.applications
          .where((row) => !(row.guildId == guildId && row.userId == session.userId))
          .toList();
      db.guests = db.guests
          .where((row) => !(row.guildId == guildId && row.userId == session.userId))
          .toList();
      _write(db);
      return const ApplyToGuildResult.ok(joined: true);
    }
    if (db.applications.any(
      (row) => row.guildId == guildId && row.userId == session.userId && !row.guest,
    )) {
      return const ApplyToGuildResult.failed('Application already pending.');
    }
    final trimmed = message.trim();
    db.applications.add(
      GuildApplication(
        id: _newId('app'),
        guildId: guildId,
        userId: session.userId,
        username: session.username,
        message: trimmed.length > 120 ? trimmed.substring(0, 120) : trimmed,
        createdAt: _nowIso(),
      ),
    );
    _write(db);
    return const ApplyToGuildResult.ok(joined: false);
  }

  ApplyToGuildResult joinAsGuest(MultiplayerSession session, String guildId, String message) {
    final db = _db();
    final guild = db.guilds.firstWhereOrNull((row) => row.id == guildId);
    if (guild == null) return const ApplyToGuildResult.failed('Guild not found.');
    if (db.members.any((row) => row.guildId == guildId && row.userId == session.userId)) {
      return const ApplyToGuildResult.failed('Already a member of that guild.');
    }
    if (db.guests.any((row) => row.guildId == guildId && row.userId == session.userId)) {
      return const ApplyToGuildResult.failed('Already a guest of that guild.');
    }
    if (db.guests.any((row) => row.userId == session.userId)) {
      return const ApplyToGuildResult.failed('Leave your current guest guild first.');
    }
    if (guild.guestAutoAccept) {
      final snapshot = _memberSnapshot(db, session.userId, session.username);
      db.guests.add(
        GuildGuest(
          guildId: guild.id,
          userId: session.userId,
          username: snapshot.username,
          joinedAt: _nowIso(),
          appearance: snapshot.appearance,
        ),
      );
      db.applications = db.applications
          .where((row) => !(row.guildId == guildId && row.userId == session.userId && row.guest))
          .toList();
      _write(db);
      return const ApplyToGuildResult.ok(joined: true);
    }
    if (db.applications.any(
      (row) => row.guildId == guildId && row.userId == session.userId && row.guest,
    )) {
      return const ApplyToGuildResult.failed('Guest request already pending.');
    }
    final trimmed = message.trim();
    db.applications.add(
      GuildApplication(
        id: _newId('app'),
        guildId: guildId,
        userId: session.userId,
        username: session.username,
        message: trimmed.length > 120 ? trimmed.substring(0, 120) : trimmed,
        createdAt: _nowIso(),
        guest: true,
      ),
    );
    _write(db);
    return const ApplyToGuildResult.ok(joined: false);
  }

  ActionResult leaveGuest(String userId) {
    final db = _db();
    if (!db.guests.any((row) => row.userId == userId)) {
      return const ActionResult.failed('Not a guest of a guild.');
    }
    db.guests = db.guests.where((row) => row.userId != userId).toList();
    _write(db);
    return const ActionResult.ok();
  }

  String? currentGuestGuildId(String userId) => _guestOf(_db(), userId)?.guildId;

  List<GuildApplication> listApplications(String guildId) =>
      _db().applications.where((row) => row.guildId == guildId).toList();

  ActionResult decideApplication(String leaderId, String applicationId, bool accept) {
    final db = _db();
    final application = db.applications.firstWhereOrNull((row) => row.id == applicationId);
    if (application == null) return const ActionResult.failed('Application not found.');
    final guild = db.guilds.firstWhereOrNull((row) => row.id == application.guildId);
    if (guild == null || guild.leaderId != leaderId) {
      return const ActionResult.failed('Only the guild leader can decide applications.');
    }
    db.applications = db.applications.where((row) => row.id != applicationId).toList();
    if (accept) {
      if (application.guest) {
        if (db.guests.any((row) => row.userId == application.userId)) {
          _write(db);
          return const ActionResult.failed('Applicant is already a guest elsewhere.');
        }
        if (db.members.any((row) => row.guildId == guild.id && row.userId == application.userId)) {
          _write(db);
          return const ActionResult.failed('Applicant already joined that guild.');
        }
        final snapshot = _memberSnapshot(db, application.userId, application.username);
        db.guests.add(
          GuildGuest(
            guildId: guild.id,
            userId: application.userId,
            username: snapshot.username,
            joinedAt: _nowIso(),
            appearance: snapshot.appearance,
          ),
        );
        _write(db);
        return const ActionResult.ok();
      }
      if (db.members.any((row) => row.userId == application.userId)) {
        _write(db);
        return const ActionResult.failed('Applicant already joined another guild.');
      }
      if (_guildMemberCount(db, guild.id) >= guildMaxMembers) {
        _write(db);
        return ActionResult.failed('Guild is full ($guildMaxMembers members).');
      }
      final snapshot = _memberSnapshot(db, application.userId, application.username);
      db.members.add(
        GuildMember(
          guildId: guild.id,
          userId: application.userId,
          username: snapshot.username,
          role: guildRoleRecruit,
          joinedAt: _nowIso(),
          appearance: snapshot.appearance,
          totalLevel: snapshot.totalLevel,
        ),
      );
      db.profiles = _withGuild(db.profiles, application.userId, guild);
      db.guests = db.guests
          .where((row) => !(row.guildId == guild.id && row.userId == application.userId))
          .toList();
    }
    _write(db);
    return const ActionResult.ok();
  }

  ActionResult setMemberRole(String actorId, String guildId, String targetUserId, GuildRole role) {
    final db = _db();
    final guild = db.guilds.firstWhereOrNull((row) => row.id == guildId);
    if (guild == null || guild.leaderId != actorId) {
      return const ActionResult.failed('Only the leader can change roles.');
    }
    if (role == guildRoleLeader) {
      return const ActionResult.failed('Transfer leadership is not available yet.');
    }
    if (targetUserId == guild.leaderId) {
      return const ActionResult.failed('Cannot change the leader rank this way.');
    }
    if (!promotableGuildRanks.contains(role)) {
      return const ActionResult.failed('Invalid rank.');
    }
    db.members = db.members
        .map(
          (row) =>
              row.guildId == guildId && row.userId == targetUserId ? row.copyWith(role: role) : row,
        )
        .toList();
    _write(db);
    return const ActionResult.ok();
  }

  ActionResult setGuildJoinPolicy(String actorId, String guildId, GuildJoinPolicy joinPolicy) {
    final db = _db();
    final index = db.guilds.indexWhere((row) => row.id == guildId);
    if (index < 0 || db.guilds[index].leaderId != actorId) {
      return const ActionResult.failed('Only the leader can change join settings.');
    }
    db.guilds[index] = db.guilds[index].copyWith(joinPolicy: joinPolicy);
    _write(db);
    return const ActionResult.ok();
  }

  ActionResult setGuildGuestAutoAccept(String actorId, String guildId, bool guestAutoAccept) {
    final db = _db();
    final index = db.guilds.indexWhere((row) => row.id == guildId);
    if (index < 0 || db.guilds[index].leaderId != actorId) {
      return const ActionResult.failed('Only the leader can change join settings.');
    }
    db.guilds[index] = db.guilds[index].copyWith(guestAutoAccept: guestAutoAccept);
    _write(db);
    return const ActionResult.ok();
  }

  ActionResult setGuildRankIconTheme(String actorId, String guildId, String theme) {
    final db = _db();
    final index = db.guilds.indexWhere((row) => row.id == guildId);
    if (index < 0 || db.guilds[index].leaderId != actorId) {
      return const ActionResult.failed('Only the leader can change rank icons.');
    }
    db.guilds[index] = db.guilds[index].copyWith(rankIconTheme: normalizeRankIconTheme(theme));
    _write(db);
    return const ActionResult.ok();
  }

  ActionResult setGuildRankLabels(
    String actorId,
    String guildId,
    Map<GuildRankKey, String> rankLabels,
  ) {
    final db = _db();
    final index = db.guilds.indexWhere((row) => row.id == guildId);
    if (index < 0 || db.guilds[index].leaderId != actorId) {
      return const ActionResult.failed('Only the leader can rename ranks.');
    }
    db.guilds[index] = db.guilds[index].copyWith(
      rankLabels: normalizeRankLabels(<String, Object?>{
        ...db.guilds[index].rankLabels,
        ...rankLabels,
      }),
    );
    _write(db);
    return const ActionResult.ok();
  }

  ActionResult setGuildEmblem(String actorId, String guildId, GuildEmblem emblem) {
    final db = _db();
    final index = db.guilds.indexWhere((row) => row.id == guildId);
    if (index < 0 || db.guilds[index].leaderId != actorId) {
      return const ActionResult.failed('Only the leader can edit the banner.');
    }
    db.guilds[index] = db.guilds[index].copyWith(emblem: normalizeEmblem(emblem));
    _write(db);
    return const ActionResult.ok();
  }

  ActionResult leaveGuild(String userId) {
    final db = _db();
    final membership = db.members.firstWhereOrNull((row) => row.userId == userId);
    if (membership == null) return const ActionResult.failed('Not in a guild.');
    final guild = db.guilds.firstWhereOrNull((row) => row.id == membership.guildId);
    if (guild?.leaderId == userId) {
      final others = db.members.where(
        (row) => row.guildId == membership.guildId && row.userId != userId,
      );
      if (others.isNotEmpty) {
        return const ActionResult.failed('Transfer leadership or remove members before leaving.');
      }
      db.guilds = db.guilds.where((row) => row.id != membership.guildId).toList();
      db.projects = db.projects.where((row) => row.guildId != membership.guildId).toList();
      db.challenges = db.challenges.where((row) => row.guildId != membership.guildId).toList();
      db.halls = db.halls.where((row) => row.guildId != membership.guildId).toList();
      db.applications = db.applications.where((row) => row.guildId != membership.guildId).toList();
      db.guests = db.guests.where((row) => row.guildId != membership.guildId).toList();
    }
    db.members = db.members.where((row) => row.userId != userId).toList();
    db.profiles = _withGuild(db.profiles, userId, null);
    _write(db);
    return const ActionResult.ok();
  }

  ContributeProjectResult contributeToProject(String userId, String projectId, num amount) {
    final db = _db();
    final membership = db.members.firstWhereOrNull((row) => row.userId == userId);
    if (membership == null) return const ContributeProjectResult.failed('Join a guild first.');
    final index = db.projects.indexWhere(
      (row) => row.id == projectId && row.guildId == membership.guildId,
    );
    if (index < 0) return const ContributeProjectResult.failed('Project not found.');
    final project = db.projects[index];
    final add = math.max(1, amount.floor());
    final next = project.copyWith(
      contributed: math.min(project.goalAmount, project.contributed + add),
    );
    db.projects[index] = next;
    _write(db);
    return ContributeProjectResult.ok(next);
  }

  List<GuildProject> guildProjects(String guildId) =>
      _db().projects.where((row) => row.guildId == guildId).toList();

  List<GuildChallenge> guildChallenges(String guildId) =>
      _db().challenges.where((row) => row.guildId == guildId).toList();

  GuildHallState _ensureHall(LocalDb db, String guildId) {
    final index = db.halls.indexWhere((row) => row.guildId == guildId);
    if (index >= 0) return db.halls[index];
    final hall = GuildHallState.fresh(guildId);
    db.halls.add(hall);
    return hall;
  }

  void _putHall(LocalDb db, GuildHallState hall) {
    db.halls = db.halls.where((row) => row.guildId != hall.guildId).toList();
    db.halls.add(hall);
  }

  GuildHallState? guildHall(String guildId) {
    final db = _db();
    if (!db.guilds.any((row) => row.id == guildId)) return null;
    final hall = _ensureHall(db, guildId);
    _write(db);
    return hall;
  }

  GuildHallActionResult payGuildDebt(String userId, PlayerSave save, num amount) {
    final db = _db();
    final membership = db.members.firstWhereOrNull((row) => row.userId == userId);
    if (membership == null) {
      return const GuildHallActionResult.failed('Join a guild first.');
    }
    if (!canPayGuildDebt(membership.role)) {
      return const GuildHallActionResult.failed('Recruits cannot pay the hall debt.');
    }
    final want = math.max(0, amount.floor());
    if (want <= 0) return const GuildHallActionResult.failed('Choose an amount.');
    if (save.gold < want) return const GuildHallActionResult.failed('Not enough gold.');
    var hall = _ensureHall(db, membership.guildId);
    if (hall.debtPaidOff || hall.debtRemaining <= 0) {
      return GuildHallActionResult.ok(hall);
    }
    final alreadyPaid = hall.debtPaidOff;
    final pay = math.min(want, hall.debtRemaining.floor());
    final remaining = hall.debtRemaining - pay;
    final paidOff = remaining <= 0;
    final paidBy = <String, num>{...hall.debtPaidBy};
    paidBy[userId] = (paidBy[userId] ?? 0) + pay;
    hall = hall.copyWith(
      debtRemaining: paidOff ? 0 : remaining,
      debtPaidBy: paidBy,
      debtPaidOff: paidOff,
    );
    _putHall(db, hall);
    _write(db);
    return GuildHallActionResult.ok(
      hall,
      save: save.copyWith(gold: save.gold - pay),
      paidOffJustNow: paidOff && !alreadyPaid,
    );
  }

  GuildHallActionResult contributeHallItem(
    String userId,
    PlayerSave save,
    int inventoryIndex,
    num quantity,
  ) {
    final db = _db();
    final membership = db.members.firstWhereOrNull((row) => row.userId == userId);
    if (membership == null) {
      return const GuildHallActionResult.failed('Join a guild first.');
    }
    if (inventoryIndex < 0 || inventoryIndex >= save.inventory.length) {
      return const GuildHallActionResult.failed('That stack is not there.');
    }
    final stack = save.inventory[inventoryIndex];
    if (stackIsUnbankableGold(stack)) {
      return const GuildHallActionResult.failed('Gold stays on you.');
    }
    final want = math.max(0, quantity.floor());
    if (want <= 0) return const GuildHallActionResult.failed('Choose a quantity.');
    final takenQty = math.min(want, stack.quantity.floor());
    var hall = _ensureHall(db, membership.guildId);
    final bagged = save.copyWith(inventory: hall.storehouse);
    final added = addItemToInventoryExact(
      bagged,
      stack.itemId,
      takenQty,
      stack.enchantmentId,
      stack.favorite ?? false,
    );
    if (!added.ok || added.save == null) {
      return GuildHallActionResult.failed(added.reason ?? 'The storehouse is full.');
    }
    final nextInventory = [...save.inventory];
    if (takenQty >= stack.quantity) {
      nextInventory.removeAt(inventoryIndex);
    } else {
      nextInventory[inventoryIndex] = stack.copyWith(quantity: stack.quantity - takenQty);
    }
    final boxingWas = hall.boxingUnlocked;
    final contributed = hall.itemsContributed + takenQty;
    var unlocks = [...hall.unlocks];
    if (contributed >= boxingRingUnlockItems && !unlocks.contains(boxingRingUnlockId)) {
      unlocks.add(boxingRingUnlockId);
    }
    hall = hall.copyWith(
      storehouse: added.save!.inventory,
      itemsContributed: contributed,
      unlocks: unlocks,
    );
    _putHall(db, hall);
    _write(db);
    return GuildHallActionResult.ok(
      hall,
      save: save.copyWith(inventory: nextInventory),
      unlockedBoxing: hall.boxingUnlocked && !boxingWas,
    );
  }

  GuildHallActionResult withdrawHallItem(
    String userId,
    PlayerSave save,
    int storehouseIndex,
    num quantity,
  ) {
    final db = _db();
    final membership = db.members.firstWhereOrNull((row) => row.userId == userId);
    if (membership == null) {
      return const GuildHallActionResult.failed('Join a guild first.');
    }
    var hall = _ensureHall(db, membership.guildId);
    if (storehouseIndex < 0 || storehouseIndex >= hall.storehouse.length) {
      return const GuildHallActionResult.failed('That stack is not there.');
    }
    final stack = hall.storehouse[storehouseIndex];
    final want = math.max(0, quantity.floor());
    if (want <= 0) return const GuildHallActionResult.failed('Choose a quantity.');
    final takenQty = math.min(want, stack.quantity.floor());
    final added = addItemToInventoryExact(
      save,
      stack.itemId,
      takenQty,
      stack.enchantmentId,
      stack.favorite ?? false,
    );
    if (!added.ok || added.save == null) {
      return GuildHallActionResult.failed(added.reason ?? 'Inventory is full.');
    }
    final nextStore = [...hall.storehouse];
    if (takenQty >= stack.quantity) {
      nextStore.removeAt(storehouseIndex);
    } else {
      nextStore[storehouseIndex] = stack.copyWith(quantity: stack.quantity - takenQty);
    }
    hall = hall.copyWith(storehouse: nextStore);
    _putHall(db, hall);
    _write(db);
    return GuildHallActionResult.ok(hall, save: added.save);
  }

  List<ArenaOpponent> hallBoxingOpponents(String userId) {
    final db = _db();
    final membership = db.members.firstWhereOrNull((row) => row.userId == userId);
    if (membership == null) return const <ArenaOpponent>[];
    final rows = <ArenaOpponent>[];
    for (final member in db.members.where((row) => row.guildId == membership.guildId)) {
      if (member.userId == userId) continue;
      final save = db.saves.firstWhereOrNull((row) => row.userId == member.userId);
      if (save == null) continue;
      rows.add(
        ArenaOpponent(
          userId: member.userId,
          username: member.username,
          combatLevel: combatLevelOf(save.payload),
          totalLevel: totalLevel(save.payload),
          appearance: member.appearance,
        ),
      );
    }
    return rows;
  }

  /// Re-totals each challenge from its members' submitted board values.
  void refreshGuildChallengeAggregates(String guildId) {
    final db = _db();
    final memberIds = db.members
        .where((row) => row.guildId == guildId)
        .map((row) => row.userId)
        .toSet();
    db.challenges = db.challenges.map((challenge) {
      if (challenge.guildId != guildId) return challenge;
      num currentValue = 0;
      for (final row in db.leaderboards) {
        if (memberIds.contains(row.userId) && row.boardKey == challenge.boardKey) {
          currentValue += row.value;
        }
      }
      return challenge.copyWith(currentValue: currentValue);
    }).toList();
    _write(db);
  }

  // --- Presence -------------------------------------------------------------

  ActivityPresence upsertPresence(MultiplayerSession session, PresenceInput input) {
    final db = _db();
    final profile = db.profiles.firstWhereOrNull((row) => row.userId == session.userId);
    final updatedAt = _nowIso();
    final expiresAt = isoFromMs(_now() + presenceTtlSeconds * 1000);
    final row = ActivityPresence(
      userId: session.userId,
      username: session.username,
      appearance: input.appearance,
      guildName: profile?.guildName,
      locationId: input.locationId,
      currentActivityId: input.currentActivityId,
      skillId: input.skillId,
      skillLevel: input.skillLevel,
      outfitCosmeticId: input.outfitCosmeticId,
      mountCosmeticId: input.mountCosmeticId,
      updatedAt: updatedAt,
      expiresAt: expiresAt,
    );
    db.presence = db.presence
        .where(
          (entry) =>
              entry.userId != session.userId &&
              (isDemoPlayerId(entry.userId) || jsDateParse(entry.expiresAt) > _now()),
        )
        .toList();
    db.presence.add(row);
    _write(db);
    return row;
  }

  void clearPresence(String userId) {
    final db = _db();
    db.presence = db.presence.where((row) => row.userId != userId).toList();
    _write(db);
  }

  /// Live presence rows, optionally narrowed to one location and activity.
  List<ActivityPresence> listPresence({String? locationId, String? activityId}) {
    final db = _db();
    final now = _now();
    return db.presence
        .where((row) => isDemoPlayerId(row.userId) || jsDateParse(row.expiresAt) > now)
        .where((row) => locationId == null || row.locationId == locationId)
        .where((row) => activityId == null || row.currentActivityId == activityId)
        .toList();
  }

  ActionResult sendFriendRequest(String fromUserId, String toUserId) {
    if (fromUserId == toUserId) return const ActionResult.failed('Cannot friend yourself.');
    final db = _db();
    if (db.blocks.any(
      (row) =>
          (row.userId == fromUserId && row.otherUserId == toUserId) ||
          (row.userId == toUserId && row.otherUserId == fromUserId),
    )) {
      return const ActionResult.failed('That player is ignored.');
    }
    final pair = <String>[fromUserId, toUserId]..sort();
    if (db.friends.any((row) => row.userA == pair[0] && row.userB == pair[1])) {
      return const ActionResult.failed('Already friends.');
    }
    if (db.friendRequests.any((row) => row.fromUserId == fromUserId && row.toUserId == toUserId)) {
      return const ActionResult.failed('Friend request already sent.');
    }
    final reverse = db.friendRequests.firstWhereOrNull(
      (row) => row.fromUserId == toUserId && row.toUserId == fromUserId,
    );
    if (reverse != null) {
      db.friendRequests = db.friendRequests.where((row) => row != reverse).toList();
      db.friends.add(Friendship(userA: pair[0], userB: pair[1]));
      _write(db);
      return const ActionResult.ok();
    }
    db.friendRequests.add(
      FriendRequest(fromUserId: fromUserId, toUserId: toUserId, createdAt: _nowIso()),
    );
    _write(db);
    return const ActionResult.ok();
  }

  /// What another player shows publicly, from their cloud save when the hint is
  /// absent and from nothing at all when they opted out of public skills.
  PublicPlayerProfile? publicProfile(String userId, [PlayerSave? saveHint]) {
    final profile = getProfile(userId);
    if (profile == null) return null;
    final save = saveHint ?? readCloudSave(userId)?.payload;
    final skills = (save?.skills ?? const <SkillProgress>[])
        .map((skill) => PublicSkillLine(skillId: skill.skillId, level: skill.level, xp: skill.xp))
        .toList();
    num total = 0;
    for (final skill in skills) {
      total += skill.level;
    }
    return PublicPlayerProfile(
      userId: userId,
      username: profile.username,
      appearance: profile.appearance,
      guildName: profile.guildName,
      publicSkills: profile.privacyPublicSkills ? skills : const <PublicSkillLine>[],
      achievementsUnlocked: save?.achievements.where((row) => row.unlocked).length ?? 0,
      totalLevel: total,
    );
  }

  // --- Bounties -------------------------------------------------------------

  List<BountyClaimRecord> listBountyClaims(String hourKey) =>
      _db().bountyClaims.where((row) => row.hourKey == hourKey).toList();

  BountyClaimRecord? getBountyClaim(String hourKey, String bountyId) => _db().bountyClaims
      .firstWhereOrNull((row) => row.hourKey == hourKey && row.bountyId == bountyId);

  /// Records the first completer for an hourly bounty slot. Later callers still
  /// succeed, since they can collect the personal base reward.
  BountyClaimResult claimBounty(MultiplayerSession session, String hourKey, String bountyId) {
    final db = _db();
    final existing = db.bountyClaims.firstWhereOrNull(
      (row) => row.hourKey == hourKey && row.bountyId == bountyId,
    );
    if (existing != null) {
      return BountyClaimResult.ok(existing, firstCompleter: existing.userId == session.userId);
    }
    final claim = BountyClaimRecord(
      hourKey: hourKey,
      bountyId: bountyId,
      userId: session.userId,
      username: session.username,
      claimedAt: _nowIso(),
    );
    db.bountyClaims.add(claim);
    _write(db);
    return BountyClaimResult.ok(claim, firstCompleter: true);
  }

  // --- Grand Bazaar ---------------------------------------------------------

  List<BazaarPost> listBazaarPosts([int limit = 40]) {
    final rows = _db().bazaarPosts.toList();
    mergeSort(
      rows,
      compare: (a, b) =>
          jsCompareThen(jsDateParse(a.createdAt) - jsDateParse(b.createdAt), () => 0),
    );
    return _lastN(rows, limit);
  }

  BazaarPostResult postBazaar(MultiplayerSession session, BazaarPostKind kind, String body) {
    final prepared = prepareBazaarPost(kind, body);
    if (!prepared.ok) return BazaarPostResult.failed(prepared.reason!);
    final db = _db();
    final cooldownKey = '${session.userId}:bazaar';
    final last = db.lastChatAt[cooldownKey];
    if (isNotBlank(last) && _now() - jsDateParse(last) < ChatCooldownSeconds.local * 1000) {
      final wait = ((ChatCooldownSeconds.local * 1000 - (_now() - jsDateParse(last))) / 1000)
          .ceil();
      return BazaarPostResult.failed('Wait ${wait}s before posting again.');
    }
    final post = BazaarPost(
      id: _newId('bzr'),
      kind: kind,
      userId: session.userId,
      username: session.username,
      body: prepared.body!,
      createdAt: _nowIso(),
    );
    db.bazaarPosts.add(post);
    if (db.bazaarPosts.length > 200) {
      db.bazaarPosts = _lastN(db.bazaarPosts, 200);
    }
    db.lastChatAt[cooldownKey] = post.createdAt;
    _write(db);
    return BazaarPostResult.ok(post);
  }

  /// Puts The Watch and its three static members on this device.
  void ensureDemoWorld(GameDatabase gameDb) {
    final db = _db();
    applyDemoWorld(db, gameDb, nowMs: _now(), nowIso: _nowIso());
    _write(db);
  }
}
