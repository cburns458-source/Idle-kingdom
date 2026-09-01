import 'dart:convert';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'bazaar.dart';
import 'config.dart';
import 'demo_world.dart';
import 'guild_rules.dart';
import 'local_db.dart';
import 'moderation.dart';
import 'name_color.dart';
import 'remote.dart';
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
        // JS bitwise width makes `1 << 32` become 0, which nextInt rejects.
        final noise = rng.nextInt(0x7fffffff).toRadixString(36);
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
    this.raceId,
    required this.totalLevel,
  });

  final String username;
  final PlayerAppearance appearance;
  final String? raceId;
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
    if (!cleanEmail.contains('@') ||
        password.length < 4 ||
        (trimmedUser.isNotEmpty && trimmedUser.length < 2)) {
      return const SessionResult.failed('Enter a valid email, username (2+), and password (4+).');
    }
    if (db.users.any((user) => user.email == cleanEmail)) {
      return const SessionResult.failed('An account with that email already exists.');
    }
    final userId = _newId('usr');
    final cleanUser = trimmedUser.length >= 2
        ? (trimmedUser.length > 24 ? trimmedUser.substring(0, 24) : trimmedUser)
        : pendingAccountUsername(userId);
    if (db.users.any((user) => user.username.toLowerCase() == cleanUser.toLowerCase())) {
      return const SessionResult.failed('That username is taken.');
    }
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

  /// Names the account from the first character name. Later names do not replace it.
  ActionResult claimAccountUsername(String userId, String name) {
    final cleaned = remoteUsername(name);
    if (cleaned.length < 2) {
      return const ActionResult.failed('Enter a name to continue.');
    }
    final db = _db();
    final accountIndex = db.users.indexWhere((row) => row.userId == userId);
    if (accountIndex < 0) return const ActionResult.failed('Sign in required.');
    final current = db.users[accountIndex].username;
    if (current.toLowerCase() == cleaned.toLowerCase()) return const ActionResult.ok();
    if (!isPendingAccountUsername(current)) return const ActionResult.ok();
    if (db.users.any(
      (row) => row.userId != userId && row.username.toLowerCase() == cleaned.toLowerCase(),
    )) {
      return const ActionResult.failed('That name is taken.');
    }
    db.users[accountIndex] = db.users[accountIndex].copyWith(username: cleaned);
    final profileIndex = db.profiles.indexWhere((row) => row.userId == userId);
    if (profileIndex >= 0) {
      db.profiles[profileIndex] = db.profiles[profileIndex].copyWith(
        username: cleaned,
        updatedAt: _nowIso(),
      );
    }
    _write(db);
    return const ActionResult.ok();
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

  Map<String, String> publishedNameColors(Iterable<String> userIds) {
    final wanted = userIds.toSet();
    final colors = <String, String>{};
    for (final profile in _db().profiles) {
      if (!wanted.contains(profile.userId)) continue;
      final color = normalizeNameColorHex(profile.nameColor);
      if (color != null) colors[profile.userId] = color;
    }
    return colors;
  }

  void claimPlaySession(String userId, String sessionId) {
    final db = _db();
    db.playSessions[userId] = sessionId;
    _write(db);
  }

  String? activePlaySessionId(String userId) => _db().playSessions[userId];

  /// Null when this device may write; a reason when another device holds the seat.
  String? playSessionRefusal(String userId, String? playSessionId) {
    final active = activePlaySessionId(userId);
    if (active == null || playSessionId == active) return null;
    return remoteSignedInElsewhere;
  }

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

  /// Keeps a contact we have already seen, so ignore lists can name them.
  void rememberProfile({
    required String userId,
    required String username,
    PlayerAppearance? appearance,
    String? raceId,
    String? guildName,
  }) {
    final existing = getProfile(userId);
    if (existing != null) {
      upsertProfile(userId, appearance: appearance, raceId: raceId, username: username);
      return;
    }
    final db = _db();
    db.profiles.add(
      MultiplayerProfile(
        userId: userId,
        username: username,
        appearance: appearance ?? defaultPlayerAppearance,
        raceId: raceId,
        guildId: null,
        guildName: guildName,
        privacyPublicSkills: true,
        updatedAt: _nowIso(),
      ),
    );
    _write(db);
  }

  MultiplayerProfile? upsertProfile(
    String userId, {
    PlayerAppearance? appearance,
    String? raceId,
    bool? privacyPublicSkills,
    bool? privacyPublicGear,
    String? privacyDirectMessages,
    String? privacyLocalChat,
    String? username,
    String? nameColor,
    String? motto,
    String? petCosmeticId,
    bool clearNameColor = false,
    bool clearMotto = false,
    bool clearPetCosmeticId = false,
  }) {
    final db = _db();
    final index = db.profiles.indexWhere((row) => row.userId == userId);
    if (index < 0) return null;
    db.profiles[index] = db.profiles[index].copyWith(
      appearance: appearance,
      raceId: raceId,
      privacyPublicSkills: privacyPublicSkills,
      privacyPublicGear: privacyPublicGear,
      privacyDirectMessages: privacyDirectMessages,
      privacyLocalChat: privacyLocalChat,
      username: username,
      nameColor: nameColor,
      motto: motto,
      petCosmeticId: petCosmeticId,
      clearNameColor: clearNameColor,
      clearMotto: clearMotto,
      clearPetCosmeticId: clearPetCosmeticId,
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
    _overlayPvpLiveStats(db, userId, save);
    _write(db);
    return CloudSaveWriteResult.ok(record);
  }

  /// Every stored fighter except [excludeUserId], which is the signed-in player.
  ///
  /// A saved PvP snapshot wins over the live cloud save so later gear changes
  /// stay off the arena until the player presses Save equipment again. Demo
  /// characters that never saved still appear from their stored save.
  List<ArenaOpponent> listArenaOpponents({String? excludeUserId}) {
    final db = _db();
    final snapshots = {for (final row in db.pvpSnapshots) row.userId: row};
    final saves = {for (final row in db.saves) row.userId: row};
    final rows = <ArenaOpponent>[];
    for (final userId in {...snapshots.keys, ...saves.keys}) {
      if (excludeUserId != null && userId == excludeUserId) continue;
      final record = snapshots[userId] ?? saves[userId];
      if (record == null) continue;
      rows.add(_arenaOpponentFromRecord(db, record));
    }
    rows.sort((a, b) {
      final byName = a.username.compareTo(b.username);
      return byName != 0 ? byName : a.userId.compareTo(b.userId);
    });
    return rows;
  }

  PlayerSave? opponentSave(String userId) {
    final db = _db();
    final record =
        db.pvpSnapshots.firstWhereOrNull((row) => row.userId == userId) ?? readCloudSave(userId);
    if (record == null) return null;
    return parseSave(record.payload.toJson(), _now());
  }

  /// Stores [save] as the loadout others fight, without changing the cloud save.
  ActionResult savePvpEquipment(String userId, PlayerSave save) {
    if (getProfile(userId) == null) {
      return const ActionResult.failed('Sign in to save PvP equipment.');
    }
    final db = _db();
    db.pvpSnapshots = db.pvpSnapshots.where((row) => row.userId != userId).toList();
    db.pvpSnapshots.add(
      CloudSaveRecord(
        userId: userId,
        saveVersion: save.saveVersion,
        updatedAt: isNotBlank(save.updatedAt) ? save.updatedAt : _nowIso(),
        payload: save,
      ),
    );
    _write(db);
    return const ActionResult.ok();
  }

  PlayerSave? ownPvpSnapshot(String userId) {
    final record = _db().pvpSnapshots.firstWhereOrNull((row) => row.userId == userId);
    if (record == null) return null;
    return parseSave(record.payload.toJson(), _now());
  }

  void refreshPvpLiveStats(String userId, PlayerSave live) {
    final db = _db();
    _overlayPvpLiveStats(db, userId, live);
    _write(db);
  }

  void _overlayPvpLiveStats(LocalDb db, String userId, PlayerSave live) {
    final existing = db.pvpSnapshots.firstWhereOrNull((row) => row.userId == userId);
    if (existing == null) return;
    db.pvpSnapshots = [
      for (final row in db.pvpSnapshots)
        if (row.userId == userId)
          CloudSaveRecord(
            userId: userId,
            saveVersion: live.saveVersion,
            updatedAt: isNotBlank(live.updatedAt) ? live.updatedAt : _nowIso(),
            payload: overlayPvpLiveStats(existing.payload, live),
          )
        else
          row,
    ];
  }

  ArenaOpponent _arenaOpponentFromRecord(LocalDb db, CloudSaveRecord record) {
    final profile = db.profiles.firstWhereOrNull((row) => row.userId == record.userId);
    final username = isNotBlank(profile?.username)
        ? profile!.username
        : (isNotBlank(record.payload.characterName)
              ? record.payload.characterName!
              : record.userId);
    return ArenaOpponent(
      userId: record.userId,
      username: username,
      combatLevel: combatLevelOf(record.payload),
      totalLevel: totalLevel(record.payload),
      appearance: profile?.appearance ?? record.payload.appearance,
    );
  }

  // --- Leaderboards ---------------------------------------------------------

  void submitLeaderboardSnapshot(
    GameDatabase gameDb,
    String userId,
    PlayerSave save, {
    String? nameColor,
    bool publishNameColor = false,
  }) {
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
          secondaryValue: board.secondaryValue ?? 0,
        ),
      );
    }
    // Refresh the profile's cosmetics snapshot from the save.
    db.profiles = db.profiles
        .map(
          (row) => row.userId == userId
              ? row.copyWith(
                  appearance: save.appearance,
                  raceId: save.raceId,
                  username: isNotBlank(save.characterName) ? save.characterName : row.username,
                  publishedEquipment: snapshot.equipment,
                  nameColor: publishNameColor ? normalizeNameColorHex(nameColor) : row.nameColor,
                  clearNameColor: publishNameColor && normalizeNameColorHex(nameColor) == null,
                  motto: save.motto,
                  clearMotto: save.motto == null,
                  petCosmeticId: save.cosmetics.equipped[petCosmeticSlotId],
                  clearPetCosmeticId: save.cosmetics.equipped[petCosmeticSlotId] == null,
                  updatedAt: updatedAt,
                )
              : row,
        )
        .toList();
    _overlayPvpLiveStats(db, userId, save);
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
      return rankLeaderboardEntries(scored).take(limit).toList();
    }
    final rows = db.leaderboards.where((row) => row.boardKey == boardKey).toList();
    final entries = rows.map((row) {
      final profile = db.profiles.firstWhereOrNull((candidate) => candidate.userId == row.userId);
      final guild = profile?.guildId == null
          ? null
          : db.guilds.firstWhereOrNull((candidate) => candidate.id == profile!.guildId);
      return LeaderboardEntry(
        userId: row.userId,
        username: profile?.username ?? 'Adventurer',
        appearance: profile?.appearance ?? defaultPlayerAppearance,
        raceId: profile?.raceId,
        guildName: profile?.guildName,
        guildTag: guild?.tag,
        boardKey: boardKey,
        value: row.value,
        rank: 0,
        secondaryValue: boardCarriesExperience(boardKey) ? row.secondaryValue : null,
        entryKind: LeaderboardEntryKind.player,
        emblem: null,
      );
    });
    // A zero on a qualify-or-not board means the player is not on it at all.
    final standing = boardHidesZeroes(boardKey)
        ? entries.where((entry) => entry.value > 0).toList()
        : entries.toList();
    return rankLeaderboardEntries(standing).take(limit).toList();
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

  String? _chatPrivacyRefusal(String senderId, ChatChannel channel) {
    if (channel is LocalChatChannel) {
      final mine = getProfile(senderId);
      return refuseOutgoingLocalChat(mine?.privacyLocalChat ?? chatPrivacyPublic);
    }
    if (channel is DirectChatChannel) {
      final peer = _dmPeerId(channel.pairKey, senderId);
      if (peer == null) return 'Unknown chat channel.';
      final theirs = getProfile(peer);
      return refuseIncomingDirectMessage(
        theirs?.privacyDirectMessages ?? chatPrivacyPublic,
        areFriends: _areFriends(senderId, peer),
      );
    }
    return null;
  }

  bool _canSeeChatLine(LocalDb db, ChatChannel channel, String viewerId, ChatMessage row) {
    if (channel is! LocalChatChannel) return true;
    final viewer = getProfile(viewerId);
    final sender = getProfile(row.userId);
    return canSeeLocalChatLine(
      viewerId: viewerId,
      senderId: row.userId,
      viewerPrivacy: viewer?.privacyLocalChat ?? chatPrivacyPublic,
      senderPrivacy: sender?.privacyLocalChat ?? chatPrivacyPublic,
      areFriends: _areFriends(viewerId, row.userId),
    );
  }

  bool _areFriends(String userA, String userB) =>
      listFriends(userA).any((row) => row.userId == userB);

  String? _dmPeerId(String pairKey, String me) {
    final parts = pairKey.split(':');
    if (parts.length < 2) return null;
    if (parts[0] == me) return parts[1];
    if (parts[1] == me) return parts[0];
    return null;
  }

  // --- Chat -----------------------------------------------------------------

  ChatSendResult sendChat(MultiplayerSession session, ChatChannel channel, String body) {
    final trimmedBody = body.trim();
    final trimmed = trimmedBody.length > 240 ? trimmedBody.substring(0, 240) : trimmedBody;
    if (trimmed.isEmpty) return const ChatSendResult.failed('Message is empty.');
    final privacyBlock = _chatPrivacyRefusal(session.userId, channel);
    if (privacyBlock != null) return ChatSendResult.failed(privacyBlock);
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
    String? rankIcon;
    var guest = false;
    if (channel is GuildChatChannel) {
      final member = db.members.firstWhereOrNull(
        (row) => row.guildId == channel.guildId && row.userId == session.userId,
      );
      if (member != null) {
        final guild = db.guilds.firstWhereOrNull((row) => row.id == channel.guildId);
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
        .where((row) => _canSeeChatLine(db, channel, viewerId, row))
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

  /// Public-channel lines from other players newer than [sinceIso], exclusive.
  int countUnreadChat(String viewerId, ChatChannel channel, String? sinceIso) {
    final sinceMs = sinceIso != null ? jsDateParse(sinceIso) : 0;
    return listChat(
      channel,
      viewerId,
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

  /// Mutes and blocks this account will not see in private chat.
  Set<String> silencedIds(String userId) => _silencedBy(_db(), userId);

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
    return [
      for (final other in blockedIds(userId))
        _contact(db, other) ??
            SocialContact(
              userId: other,
              username: 'Adventurer',
              appearance: defaultPlayerAppearance,
            ),
    ];
  }

  SocialContact? _contact(LocalDb db, String userId) {
    final profile = db.profiles.firstWhereOrNull((row) => row.userId == userId);
    if (profile == null) return null;
    return SocialContact(
      userId: profile.userId,
      username: profile.username,
      appearance: profile.appearance,
      raceId: profile.raceId,
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
      raceId: cloud?.payload.raceId ?? profile?.raceId,
      totalLevel: math.max(1, level),
    );
  }

  /// Founds a guild on this device.
  ///
  /// The name and tag are checked against the table first, which is all a single
  /// device can do. The server settles the same question with a unique index,
  /// because two players can ask for one name at the same moment.
  CreateGuildResult createGuild(
    MultiplayerSession session,
    CreateGuildInput input,
    num goldAvailable,
  ) {
    final refusal = createGuildRefusal(input, goldAvailable);
    if (refusal != null) return CreateGuildResult.failed(refusal);
    final clean = guildNameFromInput(input.name);
    final tag = guildTagFromInput(input.tag);
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
    final guild = guildFromCreateInput(session.userId, input, _nowIso(), id: _newId('gld'));
    db.guilds.add(guild);
    db.members.add(
      GuildMember(
        guildId: guild.id,
        userId: session.userId,
        username: snapshot.username,
        role: guildRoleLeader,
        joinedAt: _nowIso(),
        appearance: snapshot.appearance,
        raceId: snapshot.raceId,
        totalLevel: snapshot.totalLevel,
      ),
    );
    db.profiles = _withGuild(db.profiles, session.userId, guild);
    db.projects.add(
      GuildProject(
        id: _newId('gprj'),
        guildId: guild.id,
        name: guildStorehouseProjectName,
        description: guildStorehouseProjectDescription,
        goalAmount: guildStorehouseProjectGoal,
        contributed: 0,
        rewardLabel: guildStorehouseProjectReward,
      ),
    );
    db.challenges.add(
      GuildChallenge(
        id: _newId('gch'),
        guildId: guild.id,
        name: guildMonsterChallengeName,
        boardKey: boardMonstersKilled,
        goalValue: guildMonsterChallengeGoal,
        currentValue: 0,
      ),
    );
    db.halls.add(GuildHallState.fresh(guild.id));
    _write(db);
    return CreateGuildResult.ok(guild, guildCreateGoldCost);
  }

  /// Records which guild [userId] is in, without owning the membership.
  ///
  /// A hosted build keeps the roster on the server, but the screens that never
  /// left the device — the nearby list, a friend row — read the guild name from
  /// the profile here, so it is kept in step.
  void noteGuild(String userId, GuildRecord? guild) {
    final db = _db();
    final profile = db.profiles.firstWhereOrNull((row) => row.userId == userId);
    if (profile == null) return;
    if (profile.guildId == guild?.id && profile.guildName == guild?.name) return;
    db.profiles = _withGuild(db.profiles, userId, guild);
    _write(db);
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

  List<GuildGuest> guildGuests(String guildId) {
    return _db().guests.where((row) => row.guildId == guildId).toList();
  }

  List<GuildMember> guildMembers(String guildId) {
    final db = _db();
    return db.members.where((row) => row.guildId == guildId).map((row) {
      final snapshot = _memberSnapshot(db, row.userId, row.username);
      return row.copyWith(
        role: normalizeRole(row.role),
        username: snapshot.username,
        appearance: snapshot.appearance,
        raceId: snapshot.raceId,
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
          raceId: snapshot.raceId,
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
          raceId: snapshot.raceId,
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
    if (guild == null) return const ActionResult.failed('Guild not found.');
    final actor = db.members.firstWhereOrNull(
      (row) => row.guildId == application.guildId && row.userId == leaderId,
    );
    final refusal = decideApplicationRefusal(guild, leaderId, actor?.role);
    if (refusal != null) {
      return ActionResult.failed(refusal);
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
            raceId: snapshot.raceId,
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
          raceId: snapshot.raceId,
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

  ActionResult removeGuildMember(String actorId, String guildId, String targetUserId) {
    final db = _db();
    final guild = db.guilds.firstWhereOrNull((row) => row.id == guildId);
    if (guild == null) return const ActionResult.failed('Guild not found.');
    final refusal = removeGuildMemberRefusal(guild, actorId, targetUserId);
    if (refusal != null) return ActionResult.failed(refusal);
    if (!db.members.any((row) => row.guildId == guildId && row.userId == targetUserId)) {
      return const ActionResult.failed('Not a member of that guild.');
    }
    db.members = db.members
        .where((row) => !(row.guildId == guildId && row.userId == targetUserId))
        .toList();
    db.profiles = _withGuild(db.profiles, targetUserId, null);
    _write(db);
    return const ActionResult.ok();
  }

  ActionResult removeGuildGuest(String actorId, String guildId, String targetUserId) {
    final db = _db();
    final guild = db.guilds.firstWhereOrNull((row) => row.id == guildId);
    if (guild == null) return const ActionResult.failed('Guild not found.');
    final actor = db.members.firstWhereOrNull(
      (row) => row.guildId == guildId && row.userId == actorId,
    );
    final refusal = removeGuildGuestRefusal(guild, actorId, actor?.role);
    if (refusal != null) return ActionResult.failed(refusal);
    if (!db.guests.any((row) => row.guildId == guildId && row.userId == targetUserId)) {
      return const ActionResult.failed('Not a guest of that guild.');
    }
    db.guests = db.guests
        .where((row) => !(row.guildId == guildId && row.userId == targetUserId))
        .toList();
    _write(db);
    return const ActionResult.ok();
  }

  ActionResult setMemberRole(String actorId, String guildId, String targetUserId, GuildRole role) {
    final db = _db();
    final guild = db.guilds.firstWhereOrNull((row) => row.id == guildId);
    if (guild == null || guild.leaderId != actorId) {
      return const ActionResult.failed('Only the leader can change roles.');
    }
    final refusal = memberRoleRefusal(guild, targetUserId, role);
    if (refusal != null) return ActionResult.failed(refusal);
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

  ActionResult setGuildSkillMilestoneSettings(
    String actorId,
    String guildId,
    GuildSkillMilestoneSettings settings,
  ) {
    final db = _db();
    final index = db.guilds.indexWhere((row) => row.id == guildId);
    if (index < 0 || db.guilds[index].leaderId != actorId) {
      return const ActionResult.failed('Only the leader can change skill milestones.');
    }
    db.guilds[index] = db.guilds[index].copyWith(
      skillMilestoneSettings: normalizeGuildSkillMilestoneSettings(settings.toJson()),
    );
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
    final next = contributedProject(db.projects[index], amount);
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
    final paid = payGuildHallDebt(_ensureHall(db, membership.guildId), userId, save, amount);
    if (!paid.ok) return paid;
    _putHall(db, paid.hall!);
    _write(db);
    return paid;
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
    final given = donateToGuildHall(
      _ensureHall(db, membership.guildId),
      save,
      inventoryIndex,
      quantity,
    );
    if (!given.ok) return given;
    _putHall(db, given.hall!);
    _write(db);
    return given;
  }

  List<ArenaOpponent> hallBoxingOpponents(String userId) {
    final db = _db();
    final membership = db.members.firstWhereOrNull((row) => row.userId == userId);
    if (membership == null) return const <ArenaOpponent>[];
    final rows = <ArenaOpponent>[];
    for (final member in db.members.where((row) => row.guildId == membership.guildId)) {
      if (member.userId == userId) continue;
      final save =
          db.pvpSnapshots.firstWhereOrNull((row) => row.userId == member.userId) ??
          db.saves.firstWhereOrNull((row) => row.userId == member.userId);
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
    final expiresAt = isoFromMs(_now() + presenceAwayTtlSeconds * 1000);
    final row = ActivityPresence(
      userId: session.userId,
      username: session.username,
      appearance: input.appearance,
      raceId: input.raceId ?? profile?.raceId,
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
  List<ActivityPresence> listPresence({
    String? locationId,
    String? activityId,
    bool includeExpired = false,
  }) {
    final db = _db();
    final now = _now();
    return db.presence
        .where(
          (row) => includeExpired || isDemoPlayerId(row.userId) || jsDateParse(row.expiresAt) > now,
        )
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
      raceId: save?.raceId ?? profile.raceId,
      guildName: profile.guildName,
      publicSkills: profile.privacyPublicSkills ? skills : const <PublicSkillLine>[],
      publicEquipment: !profile.privacyPublicGear
          ? null
          : save != null
          ? publicEquipmentFromSave(save)
          : profile.publishedEquipment,
      achievementsUnlocked: save?.achievements.where((row) => row.unlocked).length ?? 0,
      totalLevel: total < 1 ? 13 : total,
      logCompletionPercent:
          _db().leaderboards
              .where((row) => row.userId == userId && row.boardKey == boardLogCompletion)
              .map((row) => row.value)
              .firstOrNull ??
          0,
      motto: save != null ? save.motto : profile.motto,
      petCosmeticId: save != null
          ? save.cosmetics.equipped[petCosmeticSlotId]
          : profile.petCosmeticId,
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

  /// Clears whatever an earlier offline build seeded here.
  void clearDemoWorld() {
    final db = _db();
    removeDemoWorld(db);
    _write(db);
  }
}
