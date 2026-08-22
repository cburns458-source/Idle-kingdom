import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'bazaar.dart';
import 'cloud_save.dart';
import 'config.dart';
import 'local_backend.dart';
import 'noted_reads.dart';
import 'presence.dart';
import 'remote.dart';
import 'remote_guild_backend.dart';
import 'remote_transport.dart';
import 'results.dart';
import 'service.dart';
import 'session_store.dart';
import 'snapshots.dart';
import 'types.dart';

/// The hosted backend, reached over a [RemoteTransport].
///
/// What a server owns goes over the wire: accounts, cloud saves, leaderboards,
/// chat, guilds, presence, and arena fighter snapshots — so other devices can
/// find someone to fight without reading their private save. What is left on
/// the device is what only the device can answer: ignores, the Bazaar, and
/// bounty claims.
class RemoteMultiplayerService implements MultiplayerService {
  RemoteMultiplayerService({
    required RemoteTransport transport,
    required SaveStorage storage,
    LocalBackendPorts? ports,
  }) : _reads = NotedReads(transport),
       _sessions = SessionStore(storage),
       _local = LocalMultiplayerService(storage: storage, ports: ports) {
    _guilds = RemoteGuildBackend(
      transport: this.transport,
      sessionOf: () => session,
      factsOf: _ownMemberFacts,
      nowIso: () => isoFromMs(_nowMs()),
    );
  }

  final NotedReads _reads;

  /// The wire, wrapped so a refused read is noticed rather than read as empty.
  RemoteTransport get transport => _reads;

  @override
  String? takeReadProblem() => _reads.take();

  @override
  Future<num> authoritativeNowMs() async {
    final remote = await transport.serverNowMs();
    return remote ?? _nowMs();
  }

  final SessionStore _sessions;
  final LocalMultiplayerService _local;
  late final RemoteGuildBackend _guilds;
  bool _seatClaimedOnServer = false;

  /// The guild this account was last seen in, so a ranking update can refresh
  /// its own roster row without a read to find out where to write it.
  String? _guildIdSeen;

  /// The name that guild last had, stamped onto this account's presence row.
  String? _guildNameSeen;

  /// Whether `profiles` has the chat-privacy columns. Null until a read tells
  /// us. A hosted project that has not applied migration 011 answers without
  /// them; once we see that, later reads skip the missing columns.
  bool? _profilesHaveChatPrivacy;

  String get _publicProfileSelectColumns => _profilesHaveChatPrivacy == false
      ? remotePublicProfileBaseColumns
      : remotePublicProfileColumns;

  /// Whether friend tables exist on the project. Null until a read tells us.
  /// Missing migration 014 falls back to the device list.
  bool? _friendsHosted;

  /// Whether `pvp_snapshots` exists. Null until a read tells us. Missing
  /// migration 015 falls back to the empty device list.
  bool? _pvpSnapshotsHosted;

  /// Friend ids from the last hosted read, so chat privacy does not re-list.
  Set<String>? _friendIdsCache;

  /// This player's roster facts, taken from the save the account already has.
  Future<GuildMemberFacts> _ownMemberFacts() async {
    final current = session;
    if (current == null) {
      return const GuildMemberFacts(
        username: 'Adventurer',
        appearance: defaultPlayerAppearance,
        totalLevel: 1,
      );
    }
    final row = await _readSaveRow(current.userId);
    return guildMemberFactsFrom(current, row?.toCloudSaveRecordOrNull()?.payload);
  }

  /// The device-local half, exposed for the same reasons the local service
  /// exposes its backend: seeding a demo world, and tests.
  LocalMultiplayerService get local => _local;

  num _nowMs() => _local.backend.ports.nowMs();

  @override
  MultiplayerSession? get session => _sessions.read();

  @override
  bool get isSignedIn => _sessions.isSignedIn;

  @override
  Future<SessionResult> signUp(String email, String username, String password) async {
    final result = await transport.signUp(
      email: email.trim(),
      password: password,
      username: remoteUsername(username),
    );
    final account = result.account;
    if (!result.ok || account == null) {
      return SessionResult.failed(result.reason ?? remoteSignUpFailed);
    }
    final chosen = username.trim().length >= 2
        ? remoteUsername(username)
        : pendingAccountUsername(account.userId);
    final created = sessionFromSignUp(account.userId, email, chosen, account.accessToken);
    // Best effort: the row may already exist, and row-level security decides
    // whether this account may write it at all.
    await transport.upsert(RemoteTables.profiles, <RemoteRow>[profileRowForSignUp(created)]);
    _adopt(created);
    return SessionResult.ok(created);
  }

  @override
  Future<SessionResult> signIn(String email, String password) async {
    final result = await transport.signIn(email: email.trim(), password: password);
    final account = result.account;
    if (!result.ok || account == null) {
      return SessionResult.failed(result.reason ?? remoteSignInFailed);
    }
    final signed = sessionFromSignIn(
      account.userId,
      account.email,
      email,
      account.username,
      account.accessToken,
    );
    final named = await _profileUsername(account.userId);
    final adopted = named == null || named.isEmpty ? signed : signed.copyWith(username: named);
    _adopt(adopted);
    return SessionResult.ok(adopted);
  }

  @override
  Future<ActionResult> claimAccountUsername(String name) async {
    final current = session;
    if (current == null) return const ActionResult.failed('Sign in required.');
    final cleaned = remoteUsername(name);
    if (cleaned.length < 2) return const ActionResult.failed('Enter a name to continue.');
    if (current.username.toLowerCase() == cleaned.toLowerCase()) {
      return const ActionResult.ok();
    }
    if (!isPendingAccountUsername(current.username)) {
      return const ActionResult.ok();
    }
    final taken = await transport.select(
      RemoteTables.profiles,
      columns: 'user_id, username',
      equals: <String, Object?>{'username': cleaned},
      limit: 1,
    );
    if (taken.ok && taken.single != null && '${taken.single!['user_id']}' != current.userId) {
      return const ActionResult.failed('That name is taken.');
    }
    final refused = await transport.upsert(RemoteTables.profiles, <RemoteRow>[
      <String, Object?>{'user_id': current.userId, 'username': cleaned},
    ], onConflict: 'user_id');
    if (refused != null) return ActionResult.failed(refused);
    await transport.updateAuthUsername(cleaned);
    _local.backend.upsertProfile(current.userId, username: cleaned);
    final next = current.copyWith(username: cleaned);
    _adopt(next);
    return const ActionResult.ok();
  }

  Future<String?> _profileUsername(String userId) async {
    final result = await transport.select(
      RemoteTables.profiles,
      columns: 'user_id, username',
      equals: <String, Object?>{'user_id': userId},
      limit: 1,
    );
    if (!result.ok || result.single == null) return null;
    final name = result.single!['username'];
    return name is String && name.isNotEmpty ? name : null;
  }

  /// Records the session and gives it a local profile, which the screens this
  /// service still answers from the device all hang off.
  void _adopt(MultiplayerSession session) {
    _sessions.write(session);
    _local.backend.registerProfile(session.userId, session.username);
  }

  @override
  Future<ActionResult> sendMagicLink(String email) async {
    final reason = await transport.sendMagicLink(email.trim());
    return reason == null ? const ActionResult.ok() : ActionResult.failed(reason);
  }

  @override
  Future<void> signOut() async {
    _sessions.write(null);
    await transport.signOut();
  }

  @override
  Future<ActionResult> claimPlaySession() async {
    final current = session;
    if (current == null) return const ActionResult.failed('Sign in to play.');
    final next = current.copyWith(playSessionId: current.playSessionId ?? newPlaySessionId());
    _sessions.write(next);
    final refused = await transport.upsert(RemoteTables.profiles, <RemoteRow>[
      profilePlaySessionRow(next),
    ]);
    // The column is missing until the play-session migration is applied; play
    // still works, but this device cannot kick or be kicked.
    _seatClaimedOnServer = refused == null;
    return const ActionResult.ok();
  }

  @override
  Future<String?> activePlaySessionId() async {
    final current = session;
    if (current == null) return null;
    final result = await transport.select(
      RemoteTables.profiles,
      columns: 'user_id, $remotePlaySessionColumn',
      equals: <String, Object?>{'user_id': current.userId},
      limit: 1,
    );
    if (!result.ok) return null;
    final row = result.single;
    final value = row?[remotePlaySessionColumn];
    return value is String && value.isNotEmpty ? value : null;
  }

  @override
  Future<MultiplayerProfile?> profile(String userId) async {
    var result = await transport.select(
      RemoteTables.profiles,
      columns: _publicProfileSelectColumns,
      equals: <String, Object?>{'user_id': userId},
      limit: 1,
    );
    if (!result.ok && remoteMissingChatPrivacyColumn(result.reason)) {
      _profilesHaveChatPrivacy = false;
      _reads.clearIf(remoteMissingChatPrivacyColumn);
      result = await transport.select(
        RemoteTables.profiles,
        columns: remotePublicProfileBaseColumns,
        equals: <String, Object?>{'user_id': userId},
        limit: 1,
      );
    } else if (result.ok) {
      _profilesHaveChatPrivacy ??= true;
    }
    if (!result.ok) return null;
    final profile = multiplayerProfileFromRemote(result.single);
    if (profile == null) return null;
    final guildName = await _guildNameFor(profile.guildId);
    if (guildName == null) return profile;
    return profile.copyWith(guildName: guildName);
  }

  Future<String?> _guildNameFor(String? guildId) async {
    if (guildId == null || guildId.isEmpty) return null;
    final result = await transport.select(
      RemoteTables.guilds,
      columns: 'id, name',
      equals: <String, Object?>{'id': guildId},
      limit: 1,
    );
    if (!result.ok || result.single == null) return null;
    final name = result.single!['name'];
    return name is String && name.isNotEmpty ? name : null;
  }

  /// Every board this account has posted, which is what the leaderboard shows.
  Future<PublicProfileStats> _leaderboardProfileStats(String userId, {GameDatabase? db}) async {
    final result = await transport.select(
      RemoteTables.leaderboard,
      columns: 'board_key, value, value_secondary',
      equals: <String, Object?>{'user_id': userId},
    );
    if (!result.ok) return const PublicProfileStats(totalLevel: 0, skills: <PublicSkillLine>[]);
    return publicProfileStatsFromLeaderboardRows(result.rows ?? const <RemoteRow>[], db: db);
  }

  @override
  Future<PublicPlayerProfile?> publicProfile(String userId, {GameDatabase? db}) async {
    final account = await profile(userId);
    if (account == null) return null;

    List<PublicSkillLine> skills = const <PublicSkillLine>[];
    num achievements = 0;
    num totalLevel = 0;

    // Cloud saves are self-only under RLS. The viewer's own save can fill
    // skills and achievements; everyone else uses the same snapshot rows
    // the leaderboard already published.
    if (session?.userId == userId) {
      final row = await _readSaveRow(userId);
      final save = row?.toCloudSaveRecordOrNull()?.payload;
      if (save != null) {
        skills = [
          for (final skill in save.skills)
            PublicSkillLine(skillId: skill.skillId, level: skill.level, xp: skill.xp),
        ];
        achievements = save.achievements.where((row) => row.unlocked).length;
        totalLevel = 0;
        for (final skill in skills) {
          totalLevel += skill.level;
        }
      }
    }

    if (session?.userId != userId || totalLevel < 1) {
      final stats = await _leaderboardProfileStats(userId, db: db);
      if (session?.userId != userId) {
        skills = stats.skills;
        totalLevel = stats.totalLevel;
      } else if (totalLevel < 1) {
        totalLevel = stats.totalLevel;
        if (skills.isEmpty) skills = stats.skills;
      }
    }

    return PublicPlayerProfile(
      userId: account.userId,
      username: account.username,
      appearance: account.appearance,
      guildName: account.guildName,
      publicSkills: account.privacyPublicSkills ? skills : const <PublicSkillLine>[],
      achievementsUnlocked: achievements,
      totalLevel: totalLevel,
    );
  }

  @override
  Future<MultiplayerProfile?> setPrivacyPublicSkills(bool value) =>
      _local.setPrivacyPublicSkills(value);

  @override
  Future<MultiplayerProfile?> setChatPrivacy({String? directMessages, String? localChat}) async {
    final current = session;
    if (current == null) return null;
    final dms = directMessages == null ? null : normalizeChatPrivacy(directMessages);
    final local = localChat == null ? null : normalizeChatPrivacy(localChat);
    if (_profilesHaveChatPrivacy != false) {
      final refused = await transport.upsert(RemoteTables.profiles, <RemoteRow>[
        <String, Object?>{
          'user_id': current.userId,
          'privacy_direct_messages': ?dms,
          'privacy_local_chat': ?local,
        },
      ], onConflict: 'user_id');
      if (refused != null && remoteMissingChatPrivacyColumn(refused)) {
        _profilesHaveChatPrivacy = false;
      }
    }
    return _local.setChatPrivacy(directMessages: dms, localChat: local);
  }

  /// The account's stored save row, or null when it has none or the read failed.
  Future<RemoteSaveRow?> _readSaveRow(String userId) async {
    final loaded = await _querySaveRow(userId);
    return loaded.row;
  }

  /// Distinguishes a missing row from a refused read so pull can say which.
  Future<({RemoteSaveRow? row, String? readError})> _querySaveRow(String userId) async {
    final result = await transport.select(
      RemoteTables.saves,
      columns: remoteSaveColumns,
      equals: <String, Object?>{'user_id': userId},
      limit: 1,
    );
    if (!result.ok) {
      return (row: null, readError: result.reason ?? 'Could not read cloud save.');
    }
    return (row: remoteSaveRowFrom(userId, result.single), readError: null);
  }

  @override
  Future<CloudSyncResult> pushSave(GameDatabase db, PlayerSave save, {bool force = false}) async {
    final current = session;
    if (current == null) {
      return const CloudSyncResult.failed('Sign in to sync cloud saves.');
    }
    final stamped = save.copyWith(updatedAt: isoFromMs(_nowMs()));
    final validation = softValidateSave(stamped);
    if (!validation.ok) return CloudSyncResult.failed(validation.reason!);

    final existing = force ? null : await _readSaveRow(current.userId);
    if (existing != null && isRemoteSaveNewer(existing, stamped)) {
      return CloudSyncResult.failed(remoteSaveConflict, remote: existing.toCloudSaveRecordOrNull());
    }

    final refused = await transport.upsert(RemoteTables.saves, <RemoteRow>[
      saveRowFor(
        current.userId,
        stamped,
        playSessionId: _seatClaimedOnServer ? current.playSessionId : null,
      ),
    ]);
    if (refused != null) return CloudSyncResult.failed(refused);

    await _refreshPvpLiveStats(stamped);
    return CloudSyncResult.ok(stamped, CloudSyncSource.uploaded);
  }

  @override
  Future<CloudSyncResult> pullSave() async {
    final current = session;
    if (current == null) {
      return const CloudSyncResult.failed('Sign in to load cloud saves.');
    }
    final loaded = await _querySaveRow(current.userId);
    if (loaded.readError != null) {
      return CloudSyncResult.failed(friendlyRemoteError(loaded.readError!));
    }
    final row = loaded.row;
    if (row == null) {
      return const CloudSyncResult.failed('No cloud save for this account yet.');
    }
    final PlayerSave payload;
    try {
      payload = parseSave(row.payload, _nowMs());
    } on Object {
      return const CloudSyncResult.failed('The cloud save could not be read.');
    }
    final validation = softValidateSave(payload);
    if (!validation.ok) return CloudSyncResult.failed(validation.reason!);
    return CloudSyncResult.ok(payload, CloudSyncSource.downloaded);
  }

  @override
  Future<CloudSyncResult> syncSave(
    GameDatabase db,
    PlayerSave local, {
    bool forceUpload = false,
  }) async {
    final current = session;
    if (current == null) return CloudSyncResult.ok(local, CloudSyncSource.unchanged);
    final row = forceUpload ? null : await _readSaveRow(current.userId);
    if (row == null) return pushSave(db, local, force: forceUpload);

    final record = row.toCloudSaveRecordOrNull();
    // A payload this build cannot read is not evidence of a newer save, so the
    // upload goes ahead and replaces it.
    if (record == null) return pushSave(db, local, force: true);
    if (remoteSaveWins(local, record.payload)) {
      return CloudSyncResult.failed('Cloud save is newer than the local save.', remote: record);
    }
    return pushSave(db, local);
  }

  @override
  Future<ActionResult> submitLeaderboard(GameDatabase db, PlayerSave save) async {
    final current = session;
    if (current == null) {
      return const ActionResult.failed('Sign in to submit leaderboard scores.');
    }
    final snapshot = buildLeaderboardSnapshot(db, save);
    final refused = await transport.upsert(
      RemoteTables.leaderboard,
      leaderboardRowsFor(current.userId, snapshot, isoFromMs(_nowMs())),
      onConflict: remoteLeaderboardConflict,
    );
    await transport.upsert(RemoteTables.profiles, <RemoteRow>[
      <String, Object?>{
        'user_id': current.userId,
        'username': current.username,
        'appearance_json': save.appearance.toJson(),
      },
    ], onConflict: 'user_id');
    // A roster lists each member's name, look, and level, and only that member
    // may write their own row, so the submit that refreshes the boards refreshes
    // the roster too.
    final guildId = _guildIdSeen;
    if (guildId != null) await _guilds.refreshOwnMemberRow(guildId, current, save);
    await _refreshPvpLiveStats(save);
    return refused == null ? const ActionResult.ok() : ActionResult.failed(refused);
  }

  @override
  Future<List<LeaderboardEntry>> leaderboard(MultiplayerBoardKey boardKey, {int limit = 25}) async {
    final result = await transport.select(
      RemoteTables.leaderboardEntries,
      columns: remoteLeaderboardColumns,
      equals: <String, Object?>{'board_key': boardKey},
      orderBy: 'value',
      ascending: false,
      limit: limit,
    );
    if (!result.ok) return const <LeaderboardEntry>[];
    return leaderboardEntriesFrom(result.rows!, boardKey);
  }

  @override
  Future<ChatSendResult> sendChat(ChatChannel channel, String body) async {
    if (!isSignedIn) return const ChatSendResult.failed('Sign in to chat.');
    final blocked = await _remoteChatPrivacyRefusal(channel);
    if (blocked != null) return ChatSendResult.failed(blocked);
    final result = await transport.invoke(remoteSendChatFunction, <String, Object?>{
      'channelKey': chatChannelKey(channel),
      'body': body,
    });
    if (!result.ok) return ChatSendResult.failed(result.reason!);
    final message = chatMessageFromFunction(result.data);
    if (message == null) return const ChatSendResult.failed(remoteChatSendFailed);
    return ChatSendResult.ok(message);
  }

  @override
  Future<List<ChatMessage>> listChat(ChatChannel channel) async {
    if (!isSignedIn) return const <ChatMessage>[];
    final result = await transport.select(
      RemoteTables.chat,
      columns: remoteChatColumns,
      equals: <String, Object?>{'channel_key': chatChannelKey(channel)},
      orderBy: 'created_at',
      limit: remoteChatLimit,
    );
    if (!result.ok) return const <ChatMessage>[];
    final messages = result.rows!.map(chatMessageFrom).toList();
    if (channel is! LocalChatChannel) return messages;
    return _filterLocalChat(messages);
  }

  @override
  Future<List<ChatMessage>> listDirectMessages() async {
    if (!isSignedIn) return const <ChatMessage>[];
    final viewerId = session!.userId;
    final result = await transport.select(
      RemoteTables.chat,
      columns: remoteChatColumns,
      like: const <String, String>{'channel_key': 'dm:%'},
      orderBy: 'created_at',
      limit: remoteDirectMessageLimit,
    );
    if (!result.ok) return const <ChatMessage>[];
    final silenced = _local.backend.silencedIds(viewerId);
    return [
      for (final message in result.rows!.map(chatMessageFrom))
        if (dmChannelInvolves(message.channelKey, viewerId) && !silenced.contains(message.userId))
          message,
    ];
  }

  @override
  Future<int> countUnreadDirectMessages(String? sinceIso) async {
    if (!isSignedIn) return 0;
    final viewerId = session!.userId;
    final sinceMs = sinceIso != null ? jsDateParse(sinceIso) : 0;
    return (await listDirectMessages())
        .where((row) => row.userId != viewerId && jsDateParse(row.createdAt) > sinceMs)
        .length;
  }

  @override
  Future<void> mutePlayer(String targetUserId) => _local.mutePlayer(targetUserId);

  @override
  Future<void> blockPlayer(String targetUserId) => _local.blockPlayer(targetUserId);

  @override
  Future<void> reportPlayer(String targetUserId, String reason) =>
      _local.reportPlayer(targetUserId, reason);

  @override
  Future<CreateGuildResult> createGuild(CreateGuildInput input, num goldAvailable) async {
    final result = await _guilds.createGuild(input, goldAvailable);
    if (result.ok) _noteGuild(result.guild);
    return result;
  }

  /// Keeps this device's note of which guild the player is in current.
  void _noteGuild(GuildRecord? guild) {
    _guildIdSeen = guild?.id;
    _guildNameSeen = guild?.name;
    final current = session;
    if (current != null) _local.backend.noteGuild(current.userId, guild);
  }

  @override
  Future<List<GuildListing>> listGuilds() => _guilds.listGuilds();

  @override
  Future<GuildRecord?> guild(String guildId) async {
    final record = await _guilds.guildById(guildId);
    if (record != null && record.id == _guildIdSeen) _noteGuild(record);
    return record;
  }

  @override
  Future<List<GuildMember>> guildMembers(String guildId) => _guilds.guildMembers(guildId);

  @override
  Future<List<GuildGuest>> guildGuests(String guildId) => _guilds.guildGuests(guildId);

  @override
  Future<ApplyToGuildResult> applyToGuild(String guildId, String message) =>
      _guilds.applyToGuild(guildId, message);

  @override
  Future<ApplyToGuildResult> joinAsGuest(String guildId, String message) =>
      _guilds.joinAsGuest(guildId, message);

  @override
  Future<ActionResult> leaveGuest() => _guilds.leaveGuest();

  @override
  Future<String?> currentGuestGuildId() => _guilds.currentGuestGuildId();

  @override
  Future<List<GuildApplication>> guildApplications(String guildId) =>
      _guilds.guildApplications(guildId);

  @override
  Future<ActionResult> decideGuildApplication(String applicationId, bool accept) =>
      _guilds.decideGuildApplication(applicationId, accept);

  @override
  Future<ActionResult> setGuildMemberRole(String guildId, String targetUserId, GuildRole role) =>
      _guilds.setGuildMemberRole(guildId, targetUserId, role);

  @override
  Future<ActionResult> setGuildJoinPolicy(String guildId, GuildJoinPolicy joinPolicy) =>
      _guilds.setGuildJoinPolicy(guildId, joinPolicy);

  @override
  Future<ActionResult> setGuildGuestAutoAccept(String guildId, bool guestAutoAccept) =>
      _guilds.setGuildGuestAutoAccept(guildId, guestAutoAccept);

  @override
  Future<ActionResult> setGuildRankIconTheme(String guildId, String theme) =>
      _guilds.setGuildRankIconTheme(guildId, theme);

  @override
  Future<ActionResult> setGuildRankLabels(String guildId, Map<GuildRankKey, String> rankLabels) =>
      _guilds.setGuildRankLabels(guildId, rankLabels);

  @override
  Future<ActionResult> setGuildEmblem(String guildId, GuildEmblem emblem) =>
      _guilds.setGuildEmblem(guildId, emblem);

  @override
  Future<ActionResult> leaveGuild() async {
    final result = await _guilds.leaveGuild();
    if (result.ok) _noteGuild(null);
    return result;
  }

  @override
  Future<ContributeProjectResult> contributeGuildProject(String projectId, num amount) =>
      _guilds.contributeGuildProject(projectId, amount);

  @override
  Future<List<GuildProject>> guildProjects(String guildId) => _guilds.guildProjects(guildId);

  @override
  Future<List<GuildChallenge>> guildChallenges(String guildId) => _guilds.guildChallenges(guildId);

  @override
  Future<String?> currentGuildId() async {
    final guildId = await _guilds.currentGuildId();
    _guildIdSeen = guildId;
    if (guildId == null) _noteGuild(null);
    return guildId;
  }

  @override
  Future<ActivityPresence?> publishPresence(PresenceInput input) async {
    final current = session;
    if (current == null) return null;
    final now = _nowMs();
    final row = presenceRowFor(
      session: current,
      input: input,
      guildName: _guildNameSeen,
      updatedAt: isoFromMs(now),
      expiresAt: isoFromMs(now + presenceAwayTtlSeconds * 1000),
    );
    final refused = await transport.upsert(RemoteTables.activityPresence, <RemoteRow>[
      row,
    ], onConflict: remotePresenceConflict);
    if (refused != null) return null;
    return activityPresenceFrom(row);
  }

  @override
  Future<void> clearPresence() async {
    final current = session;
    if (current == null) return;
    await transport.delete(
      RemoteTables.activityPresence,
      equals: <String, Object?>{'user_id': current.userId},
    );
  }

  @override
  Future<List<ActivityPresence>> peersAtLocation(
    String locationId, {
    bool excludeSelf = true,
  }) async {
    final result = await transport.select(
      RemoteTables.activityPresence,
      columns: remotePresenceColumns,
      equals: <String, Object?>{'location_id': locationId},
    );
    if (!result.ok) return const <ActivityPresence>[];
    return _visiblePeers(livePresenceFrom(result.rows!, _nowMs()), excludeSelf);
  }

  @override
  Future<List<ActivityPresence>> peersAtActivity(
    String locationId,
    String? activityId, {
    bool excludeSelf = true,
  }) async {
    final peers = await peersAtLocation(locationId, excludeSelf: excludeSelf);
    return [
      for (final row in peers)
        if (activityId == null || row.currentActivityId == activityId) row,
    ];
  }

  @override
  Future<List<ActivityPresence>> citadelVisitors() =>
      peersAtLocation(citadelLocationId(), excludeSelf: true);

  @override
  Future<List<ActivityPresence>> presenceRecords() async {
    final result = await transport.select(
      RemoteTables.activityPresence,
      columns: remotePresenceColumns,
    );
    if (!result.ok) return const <ActivityPresence>[];
    return result.rows!.map(activityPresenceFrom).toList();
  }

  List<ActivityPresence> _visiblePeers(List<ActivityPresence> peers, bool excludeSelf) {
    final current = session;
    if (current == null) return peers;
    final hidden = _local.backend.blockedIds(current.userId);
    return peers
        .where((row) => !hidden.contains(row.userId))
        .where((row) => !excludeSelf || row.userId != current.userId)
        .toList();
  }

  @override
  Future<ActionResult> sendFriendRequest(String targetUserId) async {
    final current = session;
    if (current == null) return const ActionResult.failed('Sign in required.');
    if (targetUserId == current.userId) {
      return const ActionResult.failed('Cannot friend yourself.');
    }
    if (_local.backend.blockedIds(current.userId).contains(targetUserId) ||
        _local.backend.blockedIds(targetUserId).contains(current.userId)) {
      return const ActionResult.failed('That player is ignored.');
    }
    if (!await _ensureFriendsHosted()) return _local.sendFriendRequest(targetUserId);

    if (await _hostedAreFriends(current.userId, targetUserId)) {
      return const ActionResult.failed('Already friends.');
    }

    final incoming = await transport.select(
      RemoteTables.friendRequests,
      columns: remoteFriendRequestColumns,
      equals: <String, Object?>{'from_user_id': targetUserId, 'to_user_id': current.userId},
      limit: 1,
    );
    if (!incoming.ok) {
      if (_markFriendsUnhosted(incoming.reason)) return _local.sendFriendRequest(targetUserId);
      return ActionResult.failed(incoming.reason ?? 'Could not send friend request.');
    }
    if (incoming.single != null) {
      final accepted = await _acceptHostedFriend(current.userId, targetUserId);
      _invalidateFriends();
      return accepted;
    }

    final outgoing = await transport.select(
      RemoteTables.friendRequests,
      columns: remoteFriendRequestColumns,
      equals: <String, Object?>{'from_user_id': current.userId, 'to_user_id': targetUserId},
      limit: 1,
    );
    if (!outgoing.ok) {
      return ActionResult.failed(outgoing.reason ?? 'Could not send friend request.');
    }
    if (outgoing.single != null) {
      return const ActionResult.failed('Friend request already sent.');
    }

    final written = await transport.insert(RemoteTables.friendRequests, <String, Object?>{
      'from_user_id': current.userId,
      'to_user_id': targetUserId,
    }, columns: remoteFriendRequestColumns);
    if (!written.ok) {
      if (_markFriendsUnhosted(written.reason)) return _local.sendFriendRequest(targetUserId);
      return ActionResult.failed(written.reason ?? 'Could not send friend request.');
    }
    _invalidateFriends();
    return const ActionResult.ok();
  }

  @override
  Future<ActionResult> removeFriend(String targetUserId) async {
    final current = session;
    if (current == null) return const ActionResult.failed('Sign in required.');
    if (!await _ensureFriendsHosted()) return _local.removeFriend(targetUserId);
    if (targetUserId == current.userId) {
      return const ActionResult.failed('Cannot unfriend yourself.');
    }
    if (!await _hostedAreFriends(current.userId, targetUserId)) {
      return const ActionResult.failed('Not friends.');
    }
    final pair = friendshipPair(current.userId, targetUserId);
    final refused = await transport.delete(
      RemoteTables.friendships,
      equals: <String, Object?>{'user_a': pair.userA, 'user_b': pair.userB},
    );
    if (refused != null) return ActionResult.failed(refused);
    _invalidateFriends();
    return const ActionResult.ok();
  }

  @override
  Future<void> ignorePlayer(String targetUserId) async {
    await _dropHostedRelationship(targetUserId);
    return _local.ignorePlayer(targetUserId);
  }

  @override
  Future<void> unignorePlayer(String targetUserId) => _local.unignorePlayer(targetUserId);

  @override
  Future<List<SocialContact>> friends() async {
    if (!await _ensureFriendsHosted()) {
      final local = await _local.friends();
      _friendIdsCache = {for (final row in local) row.userId};
      return local;
    }
    final current = session;
    if (current == null) return const <SocialContact>[];
    final ids = await _hostedFriendIds(current.userId);
    if (ids == null) return _local.friends();
    _friendIdsCache = ids;
    return _contactsFor(ids);
  }

  @override
  Future<List<SocialContact>> incomingFriendRequests() async {
    if (!await _ensureFriendsHosted()) return _local.incomingFriendRequests();
    final current = session;
    if (current == null) return const <SocialContact>[];
    final result = await transport.select(
      RemoteTables.friendRequests,
      columns: remoteFriendRequestColumns,
      equals: <String, Object?>{'to_user_id': current.userId},
    );
    if (!result.ok) {
      if (_markFriendsUnhosted(result.reason)) return _local.incomingFriendRequests();
      return const <SocialContact>[];
    }
    return _contactsFor({
      for (final row in result.rows ?? const <RemoteRow>[]) _strId(row['from_user_id']),
    });
  }

  @override
  Future<List<SocialContact>> outgoingFriendRequests() async {
    if (!await _ensureFriendsHosted()) return _local.outgoingFriendRequests();
    final current = session;
    if (current == null) return const <SocialContact>[];
    final result = await transport.select(
      RemoteTables.friendRequests,
      columns: remoteFriendRequestColumns,
      equals: <String, Object?>{'from_user_id': current.userId},
    );
    if (!result.ok) {
      if (_markFriendsUnhosted(result.reason)) return _local.outgoingFriendRequests();
      return const <SocialContact>[];
    }
    return _contactsFor({
      for (final row in result.rows ?? const <RemoteRow>[]) _strId(row['to_user_id']),
    });
  }

  @override
  Future<List<SocialContact>> ignoredPlayers() => _local.ignoredPlayers();

  void _invalidateFriends() => _friendIdsCache = null;

  Future<Set<String>> _friendIdSet() async {
    if (_friendIdsCache != null) return _friendIdsCache!;
    final rows = await friends();
    return _friendIdsCache = {for (final row in rows) row.userId};
  }

  bool _markFriendsUnhosted(String? reason) {
    if (!remoteMissingFriendsTable(reason)) return false;
    _friendsHosted = false;
    _reads.clearIf(remoteMissingFriendsTable);
    return true;
  }

  Future<bool> _ensureFriendsHosted() async {
    if (_friendsHosted == false) return false;
    if (_friendsHosted == true) return true;
    final current = session;
    if (current == null) return false;
    final result = await transport.select(
      RemoteTables.friendRequests,
      columns: remoteFriendRequestColumns,
      equals: <String, Object?>{'to_user_id': current.userId},
      limit: 1,
    );
    if (!result.ok) {
      if (_markFriendsUnhosted(result.reason)) return false;
      _friendsHosted = true;
      return true;
    }
    _friendsHosted = true;
    return true;
  }

  Future<ActionResult> _acceptHostedFriend(String me, String other) async {
    await transport.delete(
      RemoteTables.friendRequests,
      equals: <String, Object?>{'from_user_id': other, 'to_user_id': me},
    );
    await transport.delete(
      RemoteTables.friendRequests,
      equals: <String, Object?>{'from_user_id': me, 'to_user_id': other},
    );
    final pair = friendshipPair(me, other);
    final written = await transport.insert(RemoteTables.friendships, <String, Object?>{
      'user_a': pair.userA,
      'user_b': pair.userB,
    }, columns: remoteFriendshipColumns);
    if (!written.ok && !(written.reason ?? '').toLowerCase().contains('duplicate key')) {
      if (_markFriendsUnhosted(written.reason)) {
        return _local.sendFriendRequest(other);
      }
      return ActionResult.failed(written.reason ?? 'Could not accept friend request.');
    }
    return const ActionResult.ok();
  }

  Future<bool> _hostedAreFriends(String me, String other) async {
    final pair = friendshipPair(me, other);
    final result = await transport.select(
      RemoteTables.friendships,
      columns: remoteFriendshipColumns,
      equals: <String, Object?>{'user_a': pair.userA, 'user_b': pair.userB},
      limit: 1,
    );
    if (!result.ok) {
      _markFriendsUnhosted(result.reason);
      return false;
    }
    return result.single != null;
  }

  Future<Set<String>?> _hostedFriendIds(String me) async {
    final asA = await transport.select(
      RemoteTables.friendships,
      columns: remoteFriendshipColumns,
      equals: <String, Object?>{'user_a': me},
    );
    if (!asA.ok) {
      if (_markFriendsUnhosted(asA.reason)) return null;
      return const <String>{};
    }
    final asB = await transport.select(
      RemoteTables.friendships,
      columns: remoteFriendshipColumns,
      equals: <String, Object?>{'user_b': me},
    );
    if (!asB.ok) return const <String>{};
    return <String>{
      for (final row in asA.rows ?? const <RemoteRow>[]) _strId(row['user_b']),
      for (final row in asB.rows ?? const <RemoteRow>[]) _strId(row['user_a']),
    }..removeWhere((id) => id.isEmpty);
  }

  Future<void> _dropHostedRelationship(String otherUserId) async {
    final current = session;
    if (current == null || !await _ensureFriendsHosted()) return;
    await transport.delete(
      RemoteTables.friendRequests,
      equals: <String, Object?>{'from_user_id': current.userId, 'to_user_id': otherUserId},
    );
    await transport.delete(
      RemoteTables.friendRequests,
      equals: <String, Object?>{'from_user_id': otherUserId, 'to_user_id': current.userId},
    );
    final pair = friendshipPair(current.userId, otherUserId);
    await transport.delete(
      RemoteTables.friendships,
      equals: <String, Object?>{'user_a': pair.userA, 'user_b': pair.userB},
    );
    _invalidateFriends();
  }

  Future<List<SocialContact>> _contactsFor(Set<String> userIds) async {
    final out = <SocialContact>[];
    for (final userId in userIds) {
      if (userId.isEmpty) continue;
      final account = await profile(userId);
      out.add(
        SocialContact(
          userId: userId,
          username: account?.username ?? 'Adventurer',
          appearance: account?.appearance ?? defaultPlayerAppearance,
          guildName: account?.guildName,
        ),
      );
    }
    return out;
  }

  String _strId(Object? value) => value is String ? value : '$value';

  @override
  Future<List<BountyClaimRecord>> bountyClaims(String hourKey) async {
    final result = await transport.select(
      RemoteTables.bountyClaims,
      columns: remoteBountyClaimColumns,
      equals: <String, Object?>{'hour_key': hourKey},
      orderBy: 'claimed_at',
    );
    if (!result.ok) return const <BountyClaimRecord>[];
    return result.rows!.map(bountyClaimFrom).toList();
  }

  /// The claim already recorded for this bounty, if somebody got there first.
  Future<BountyClaimRecord?> _existingClaim(String hourKey, String bountyId) async {
    final result = await transport.select(
      RemoteTables.bountyClaims,
      columns: remoteBountyClaimColumns,
      equals: <String, Object?>{'hour_key': hourKey, 'bounty_id': bountyId},
      limit: 1,
    );
    final row = result.ok ? result.single : null;
    return row == null ? null : bountyClaimFrom(row);
  }

  /// Claims an hourly bounty, letting the backend decide who was first.
  ///
  /// This is the one thing the local backend cannot answer honestly, because on
  /// one device everybody is always first. The table's primary key settles it:
  /// the insert either lands, or is refused because somebody else won, and the
  /// loser is handed the winner's claim so the board can name them. Either way
  /// the turn-in succeeds — the base reward is not a race.
  @override
  Future<BountyClaimResult> claimBounty(String hourKey, String bountyId) async {
    final current = session;
    if (current == null) {
      return const BountyClaimResult.failed('Sign in to claim bounties.');
    }
    final already = await _existingClaim(hourKey, bountyId);
    if (already != null) {
      return BountyClaimResult.ok(already, firstCompleter: already.userId == current.userId);
    }

    final written = await transport.insert(
      RemoteTables.bountyClaims,
      bountyClaimRowFor(current, hourKey, bountyId),
      columns: remoteBountyClaimColumns,
    );
    if (written.ok && written.single != null) {
      return BountyClaimResult.ok(bountyClaimFrom(written.single!), firstCompleter: true);
    }

    // Refused: either somebody claimed it between the read and the write, or the
    // write itself failed. A claim now on the table means the former.
    final winner = await _existingClaim(hourKey, bountyId);
    if (winner == null) return BountyClaimResult.failed(written.reason!);
    return BountyClaimResult.ok(winner, firstCompleter: winner.userId == current.userId);
  }

  @override
  Future<List<BazaarPost>> bazaarPosts({int limit = remoteBazaarLimit}) async {
    final result = await transport.select(
      RemoteTables.bazaarPosts,
      columns: remoteBazaarColumns,
      orderBy: 'created_at',
      ascending: false,
      limit: limit,
    );
    if (!result.ok) return const <BazaarPost>[];
    return bazaarPostsFrom(result.rows!);
  }

  @override
  Future<BazaarPostResult> postBazaar(BazaarPostKind kind, String body) async {
    final current = session;
    if (current == null) {
      return const BazaarPostResult.failed('Sign in to post in the Grand Bazaar.');
    }
    final prepared = prepareBazaarPost(kind, body);
    if (!prepared.ok) return BazaarPostResult.failed(prepared.reason!);

    final written = await transport.insert(
      RemoteTables.bazaarPosts,
      bazaarPostRowFor(current, kind, prepared.body!),
      columns: remoteBazaarColumns,
    );
    final row = written.ok ? written.single : null;
    if (row == null) {
      return BazaarPostResult.failed(written.reason ?? remoteBazaarPostFailed);
    }
    return BazaarPostResult.ok(bazaarPostFrom(row));
  }

  @override
  Future<List<ArenaOpponent>> listArenaOpponents() async {
    if (!await _ensurePvpSnapshotsHosted()) return _local.listArenaOpponents();
    return _hostedArenaOpponents();
  }

  @override
  Future<ActionResult> savePvpEquipment(PlayerSave save) async {
    final current = session;
    if (current == null) {
      return const ActionResult.failed('Sign in to save PvP equipment.');
    }
    if (!await _ensurePvpSnapshotsHosted()) return _local.savePvpEquipment(save);
    final refused = await transport.upsert(RemoteTables.pvpSnapshots, <RemoteRow>[
      pvpSnapshotRowFor(session: current, save: save, updatedAt: isoFromMs(_nowMs())),
    ], onConflict: remotePvpSnapshotConflict);
    if (refused != null) {
      if (_markPvpSnapshotsUnhosted(refused)) return _local.savePvpEquipment(save);
      return ActionResult.failed(friendlyRemoteError(refused));
    }
    return const ActionResult.ok();
  }

  @override
  Future<PlayerSave?> ownPvpSnapshot() async {
    final current = session;
    if (current == null) return null;
    if (!await _ensurePvpSnapshotsHosted()) return _local.ownPvpSnapshot();
    final result = await transport.select(
      RemoteTables.pvpSnapshots,
      columns: remotePvpSnapshotColumns,
      equals: <String, Object?>{'user_id': current.userId},
      limit: 1,
    );
    if (!result.ok) {
      if (_markPvpSnapshotsUnhosted(result.reason)) return _local.ownPvpSnapshot();
      return null;
    }
    return _parsePvpSnapshotPayload(pvpSnapshotPayloadFrom(result.single));
  }

  @override
  Future<PlayerSave?> readOpponentSave(String userId) async {
    final current = session;
    if (current != null && current.userId == userId) return null;
    if (!await _ensurePvpSnapshotsHosted()) return _local.readOpponentSave(userId);
    final result = await transport.select(
      RemoteTables.pvpSnapshots,
      columns: remotePvpSnapshotColumns,
      equals: <String, Object?>{'user_id': userId},
      limit: 1,
    );
    if (!result.ok) {
      if (_markPvpSnapshotsUnhosted(result.reason)) return _local.readOpponentSave(userId);
      return null;
    }
    return _parsePvpSnapshotPayload(pvpSnapshotPayloadFrom(result.single));
  }

  @override
  Future<GuildHallState?> guildHall(String guildId) => _guilds.guildHall(guildId);

  @override
  Future<GuildHallActionResult> payGuildDebt(PlayerSave save, num amount) =>
      _guilds.payGuildDebt(save, amount);

  @override
  Future<GuildHallActionResult> contributeHallItem(
    PlayerSave save,
    int inventoryIndex,
    num quantity,
  ) => _guilds.contributeHallItem(save, inventoryIndex, quantity);

  Future<String?> _remoteChatPrivacyRefusal(ChatChannel channel) async {
    final me = session?.userId;
    if (me == null) return 'Sign in to chat.';
    if (channel is LocalChatChannel) {
      final mine = await profile(me) ?? _local.backend.getProfile(me);
      return refuseOutgoingLocalChat(mine?.privacyLocalChat ?? chatPrivacyPublic);
    }
    if (channel is DirectChatChannel) {
      final parts = channel.pairKey.split(':');
      final peer = parts.length < 2
          ? null
          : parts[0] == me
          ? parts[1]
          : parts[1];
      if (peer == null || peer.isEmpty) return 'Unknown chat channel.';
      final theirs = await profile(peer) ?? _local.backend.getProfile(peer);
      final friendIds = await _friendIdSet();
      return refuseIncomingDirectMessage(
        theirs?.privacyDirectMessages ?? chatPrivacyPublic,
        areFriends: friendIds.contains(peer),
      );
    }
    return null;
  }

  Future<List<ChatMessage>> _filterLocalChat(List<ChatMessage> messages) async {
    final me = session?.userId;
    if (me == null) return const <ChatMessage>[];
    final mine = await profile(me) ?? _local.backend.getProfile(me);
    final viewerPrivacy = mine?.privacyLocalChat ?? chatPrivacyPublic;
    final friends = await _friendIdSet();
    final out = <ChatMessage>[];
    for (final message in messages) {
      final sender = await profile(message.userId) ?? _local.backend.getProfile(message.userId);
      if (canSeeLocalChatLine(
        viewerId: me,
        senderId: message.userId,
        viewerPrivacy: viewerPrivacy,
        senderPrivacy: sender?.privacyLocalChat ?? chatPrivacyPublic,
        areFriends: friends.contains(message.userId),
      )) {
        out.add(message);
      }
    }
    return out;
  }

  /// Guildmates who have published a fighter snapshot.
  @override
  Future<List<ArenaOpponent>> hallBoxingOpponents() async {
    if (!await _ensurePvpSnapshotsHosted()) return _local.hallBoxingOpponents();
    final current = session;
    if (current == null) return const <ArenaOpponent>[];
    var guildId = _guildIdSeen;
    guildId ??= (await profile(current.userId))?.guildId;
    if (guildId == null || guildId.isEmpty) return const <ArenaOpponent>[];
    final members = await _guilds.guildMembers(guildId);
    final ids = {for (final member in members) member.userId};
    return [
      for (final row in await _hostedArenaOpponents())
        if (ids.contains(row.userId)) row,
    ];
  }

  Future<void> _refreshPvpLiveStats(PlayerSave live) async {
    final current = session;
    if (current == null) return;
    if (!await _ensurePvpSnapshotsHosted()) {
      _local.backend.refreshPvpLiveStats(current.userId, live);
      return;
    }
    final result = await transport.select(
      RemoteTables.pvpSnapshots,
      columns: remotePvpSnapshotColumns,
      equals: <String, Object?>{'user_id': current.userId},
      limit: 1,
    );
    if (!result.ok) {
      _markPvpSnapshotsUnhosted(result.reason);
      return;
    }
    final existing = _parsePvpSnapshotPayload(pvpSnapshotPayloadFrom(result.single));
    if (existing == null) return;
    await transport.upsert(RemoteTables.pvpSnapshots, <RemoteRow>[
      pvpSnapshotRowFor(
        session: current,
        save: overlayPvpLiveStats(existing, live),
        updatedAt: isoFromMs(_nowMs()),
      ),
    ], onConflict: remotePvpSnapshotConflict);
  }

  PlayerSave? _parsePvpSnapshotPayload(Map<String, Object?>? payload) {
    if (payload == null) return null;
    try {
      return parseSave(payload, _nowMs());
    } on Object {
      return null;
    }
  }

  Future<List<ArenaOpponent>> _hostedArenaOpponents() async {
    final current = session;
    final result = await transport.select(
      RemoteTables.pvpSnapshots,
      columns: remotePvpSnapshotColumns,
      orderBy: 'username',
    );
    if (!result.ok) {
      if (_markPvpSnapshotsUnhosted(result.reason)) return _local.listArenaOpponents();
      return const <ArenaOpponent>[];
    }
    final hidden = current == null ? const <String>{} : _local.backend.blockedIds(current.userId);
    final rows = [
      for (final row in result.rows!)
        if (row['user_id'] != current?.userId && !hidden.contains(_strId(row['user_id'])))
          arenaOpponentFromPvpRow(row),
    ];
    rows.sort((a, b) {
      final byName = a.username.compareTo(b.username);
      return byName != 0 ? byName : a.userId.compareTo(b.userId);
    });
    return rows;
  }

  bool _markPvpSnapshotsUnhosted(String? reason) {
    if (!remoteMissingPvpSnapshotsTable(reason)) return false;
    _pvpSnapshotsHosted = false;
    _reads.clearIf(remoteMissingPvpSnapshotsTable);
    return true;
  }

  Future<bool> _ensurePvpSnapshotsHosted() async {
    if (_pvpSnapshotsHosted == false) return false;
    if (_pvpSnapshotsHosted == true) return true;
    final result = await transport.select(RemoteTables.pvpSnapshots, columns: 'user_id', limit: 1);
    if (!result.ok) {
      if (_markPvpSnapshotsUnhosted(result.reason)) return false;
      _pvpSnapshotsHosted = true;
      return true;
    }
    _pvpSnapshotsHosted = true;
    return true;
  }
}
