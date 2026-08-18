import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'bazaar.dart';
import 'cloud_save.dart';
import 'local_backend.dart';
import 'noted_reads.dart';
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
/// chat, and guilds — rosters, requests, guests, and each guild's hall. What is
/// left on the device is what only the device can answer: presence, the Bazaar,
/// bounty claims, and sparring partners, which need to read another player's
/// save that row-level security rightly will not hand over.
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

  final SessionStore _sessions;
  final LocalMultiplayerService _local;
  late final RemoteGuildBackend _guilds;
  bool _seatClaimedOnServer = false;

  /// The guild this account was last seen in, so a ranking update can refresh
  /// its own roster row without a read to find out where to write it.
  String? _guildIdSeen;

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
    final created = sessionFromSignUp(account.userId, email, username, account.accessToken);
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
    _adopt(signed);
    return SessionResult.ok(signed);
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
  Future<MultiplayerProfile?> profile(String userId) => _local.profile(userId);

  @override
  Future<MultiplayerProfile?> setPrivacyPublicSkills(bool value) =>
      _local.setPrivacyPublicSkills(value);

  /// The account's stored save row, or null when it has none.
  Future<RemoteSaveRow?> _readSaveRow(String userId) async {
    final result = await transport.select(
      RemoteTables.saves,
      columns: remoteSaveColumns,
      equals: <String, Object?>{'user_id': userId},
      limit: 1,
    );
    if (!result.ok) return null;
    return remoteSaveRowFrom(userId, result.single);
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

    return CloudSyncResult.ok(stamped, CloudSyncSource.uploaded);
  }

  @override
  Future<CloudSyncResult> pullSave() async {
    final current = session;
    if (current == null) {
      return const CloudSyncResult.failed('Sign in to load cloud saves.');
    }
    final row = await _readSaveRow(current.userId);
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
    // A roster lists each member's name, look, and level, and only that member
    // may write their own row, so the submit that refreshes the boards refreshes
    // the roster too.
    final guildId = _guildIdSeen;
    if (guildId != null) await _guilds.refreshOwnMemberRow(guildId, current, save);
    return refused == null ? const ActionResult.ok() : ActionResult.failed(refused);
  }

  @override
  Future<List<LeaderboardEntry>> leaderboard(MultiplayerBoardKey boardKey, {int limit = 25}) async {
    final result = await transport.select(
      RemoteTables.leaderboard,
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
    return result.rows!.map(chatMessageFrom).toList();
  }

  @override
  Future<List<ChatMessage>> listDirectMessages() => _local.listDirectMessages();

  @override
  Future<int> countUnreadDirectMessages(String? sinceIso) =>
      _local.countUnreadDirectMessages(sinceIso);

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
  Future<ActivityPresence?> publishPresence(PresenceInput input) => _local.publishPresence(input);

  @override
  Future<void> clearPresence() => _local.clearPresence();

  @override
  Future<List<ActivityPresence>> peersAtLocation(String locationId, {bool excludeSelf = true}) =>
      _local.peersAtLocation(locationId, excludeSelf: excludeSelf);

  @override
  Future<List<ActivityPresence>> peersAtActivity(
    String locationId,
    String? activityId, {
    bool excludeSelf = true,
  }) => _local.peersAtActivity(locationId, activityId, excludeSelf: excludeSelf);

  @override
  Future<List<ActivityPresence>> citadelVisitors() => _local.citadelVisitors();

  @override
  Future<List<ActivityPresence>> presenceRecords() => _local.presenceRecords();

  @override
  Future<PublicPlayerProfile?> publicProfile(String userId) => _local.publicProfile(userId);

  @override
  Future<ActionResult> sendFriendRequest(String targetUserId) =>
      _local.sendFriendRequest(targetUserId);

  @override
  Future<ActionResult> removeFriend(String targetUserId) => _local.removeFriend(targetUserId);

  @override
  Future<void> ignorePlayer(String targetUserId) => _local.ignorePlayer(targetUserId);

  @override
  Future<void> unignorePlayer(String targetUserId) => _local.unignorePlayer(targetUserId);

  @override
  Future<List<SocialContact>> friends() => _local.friends();

  @override
  Future<List<SocialContact>> incomingFriendRequests() => _local.incomingFriendRequests();

  @override
  Future<List<SocialContact>> outgoingFriendRequests() => _local.outgoingFriendRequests();

  @override
  Future<List<SocialContact>> ignoredPlayers() => _local.ignoredPlayers();

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
  Future<List<ArenaOpponent>> listArenaOpponents() => _local.listArenaOpponents();

  @override
  Future<PlayerSave?> readOpponentSave(String userId) => _local.readOpponentSave(userId);

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

  /// Sparring partners in the hall, which stay on the device.
  ///
  /// A fight needs the other player's save, and an account's save is readable
  /// only by that account. Opening it up to a guild would mean handing every
  /// member's whole game to anyone who joined, so the boxing ring spars with
  /// whoever this device knows, as the arena does.
  @override
  Future<List<ArenaOpponent>> hallBoxingOpponents() => _local.hallBoxingOpponents();
}
