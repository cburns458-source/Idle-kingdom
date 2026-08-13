import 'dart:convert';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'bazaar.dart';
import 'config.dart';
import 'local_db.dart';
import 'results.dart';
import 'snapshots.dart';
import 'types.dart';

final RegExp _basicProfanity = RegExp(
  r'\b(fuck|shit|asshole|cunt|nigger|faggot)\b',
  caseSensitive: false,
);

/// Masks the words the shipped word list covers, leaving length intact so the
/// reader can tell something was removed.
String filterProfanity(String body) => body.replaceAllMapped(
  _basicProfanity,
  (match) => '*' * match.group(0)!.length,
);

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
      return const SessionResult.failed(
        'Enter a valid email, username (2+), and password (4+).',
      );
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

  CloudSaveWriteResult writeCloudSave(String userId, PlayerSave save) {
    final db = _db();
    final existing = db.saves.firstWhereOrNull((row) => row.userId == userId);
    if (existing != null &&
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
    final stampKey = '${session.userId}:$key';
    final last = db.lastChatAt[stampKey];
    if (isNotBlank(last) && _now() - jsDateParse(last) < cooldown * 1000) {
      final wait = ((cooldown * 1000 - (_now() - jsDateParse(last))) / 1000).ceil();
      return ChatSendResult.failed('Wait ${wait}s before chatting again.');
    }
    if (channel is GuildChatChannel) {
      final member = db.members.firstWhereOrNull(
        (row) => row.guildId == channel.guildId && row.userId == session.userId,
      );
      if (member == null) {
        return const ChatSendResult.failed('Join the guild to use guild chat.');
      }
    }
    final message = ChatMessage(
      id: _newId('msg'),
      channelKey: key,
      userId: session.userId,
      username: session.username,
      body: filterProfanity(trimmed),
      createdAt: _nowIso(),
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
      compare: (a, b) => jsCompareThen(jsDateParse(a.createdAt) - jsDateParse(b.createdAt), () => 0),
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
      compare: (a, b) => jsCompareThen(jsDateParse(a.createdAt) - jsDateParse(b.createdAt), () => 0),
    );
    return _lastN(rows, limit);
  }

  /// Direct messages from other players newer than [sinceIso], exclusive.
  int countUnreadDirectMessages(String viewerId, String? sinceIso) {
    final sinceMs = sinceIso != null ? jsDateParse(sinceIso) : 0;
    return listDirectMessages(viewerId, 200)
        .where((row) => row.userId != viewerId && jsDateParse(row.createdAt) > sinceMs)
        .length;
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
    _write(db);
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
    mergeSort(
      listings,
      compare: (a, b) => jsLocaleCompare(a.guild.name, b.guild.name),
    );
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

  ApplyToGuildResult applyToGuild(
    MultiplayerSession session,
    String guildId,
    String message,
  ) {
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
      _write(db);
      return const ApplyToGuildResult.ok(joined: true);
    }
    if (db.applications.any((row) => row.guildId == guildId && row.userId == session.userId)) {
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
    }
    _write(db);
    return const ActionResult.ok();
  }

  ActionResult setMemberRole(
    String actorId,
    String guildId,
    String targetUserId,
    GuildRole role,
  ) {
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
          (row) => row.guildId == guildId && row.userId == targetUserId
              ? row.copyWith(role: role)
              : row,
        )
        .toList();
    _write(db);
    return const ActionResult.ok();
  }

  ActionResult setGuildJoinPolicy(
    String actorId,
    String guildId,
    GuildJoinPolicy joinPolicy,
  ) {
    final db = _db();
    final index = db.guilds.indexWhere((row) => row.id == guildId);
    if (index < 0 || db.guilds[index].leaderId != actorId) {
      return const ActionResult.failed('Only the leader can change join settings.');
    }
    db.guilds[index] = db.guilds[index].copyWith(joinPolicy: joinPolicy);
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
      db.applications = db.applications.where((row) => row.guildId != membership.guildId).toList();
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
        .where((entry) => entry.userId != session.userId && jsDateParse(entry.expiresAt) > _now())
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
        .where((row) => jsDateParse(row.expiresAt) > now)
        .where((row) => locationId == null || row.locationId == locationId)
        .where((row) => activityId == null || row.currentActivityId == activityId)
        .toList();
  }

  ActionResult sendFriendRequest(String fromUserId, String toUserId) {
    if (fromUserId == toUserId) return const ActionResult.failed('Cannot friend yourself.');
    final db = _db();
    final pair = <String>[fromUserId, toUserId]..sort();
    if (db.friends.any((row) => row.userA == pair[0] && row.userB == pair[1])) {
      return const ActionResult.failed('Already friends.');
    }
    if (db.friendRequests.any(
      (row) => row.fromUserId == fromUserId && row.toUserId == toUserId,
    )) {
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
  BountyClaimResult claimBounty(
    MultiplayerSession session,
    String hourKey,
    String bountyId,
  ) {
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
      compare: (a, b) => jsCompareThen(jsDateParse(a.createdAt) - jsDateParse(b.createdAt), () => 0),
    );
    return _lastN(rows, limit);
  }

  BazaarPostResult postBazaar(
    MultiplayerSession session,
    BazaarPostKind kind,
    String body,
  ) {
    final trimmedBody = body.trim();
    final trimmed = trimmedBody.length > 240 ? trimmedBody.substring(0, 240) : trimmedBody;
    if (trimmed.isEmpty) return const BazaarPostResult.failed('Message is empty.');
    if (!bazaarPostKinds.contains(kind)) {
      return const BazaarPostResult.failed('Unknown bazaar post kind.');
    }
    final db = _db();
    final cooldownKey = '${session.userId}:bazaar';
    final last = db.lastChatAt[cooldownKey];
    if (isNotBlank(last) && _now() - jsDateParse(last) < ChatCooldownSeconds.local * 1000) {
      final wait = ((ChatCooldownSeconds.local * 1000 - (_now() - jsDateParse(last))) / 1000).ceil();
      return BazaarPostResult.failed('Wait ${wait}s before posting again.');
    }
    final post = BazaarPost(
      id: _newId('bzr'),
      kind: kind,
      userId: session.userId,
      username: session.username,
      body: filterProfanity(trimmed),
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
}
