import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'bazaar.dart';
import 'cloud_save.dart';
import 'local_backend.dart';
import 'remote.dart';
import 'remote_transport.dart';
import 'results.dart';
import 'service.dart';
import 'session_store.dart';
import 'snapshots.dart';
import 'types.dart';

/// The hosted backend, reached over a [RemoteTransport].
///
/// Only what a server actually owns goes over the wire: accounts, cloud saves,
/// leaderboards, and chat. Guilds, presence, bounty claims, and the Bazaar are
/// still answered by the local backend, which is the same division the web
/// client makes — those tables have no migrations yet, and a screen that half
/// works is worse than one that plainly runs on this device.
class RemoteMultiplayerService implements MultiplayerService {
  RemoteMultiplayerService({
    required this.transport,
    required SaveStorage storage,
    LocalBackendPorts? ports,
  }) : _sessions = SessionStore(storage),
       _local = LocalMultiplayerService(storage: storage, ports: ports);

  final RemoteTransport transport;
  final SessionStore _sessions;
  final LocalMultiplayerService _local;

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
      saveRowFor(current.userId, stamped),
    ]);
    if (refused != null) return CloudSyncResult.failed(refused);

    await submitLeaderboard(db, stamped);
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
  Future<CreateGuildResult> createGuild(CreateGuildInput input, num goldAvailable) =>
      _local.createGuild(input, goldAvailable);

  @override
  Future<List<GuildListing>> listGuilds() => _local.listGuilds();

  @override
  Future<GuildRecord?> guild(String guildId) => _local.guild(guildId);

  @override
  Future<List<GuildMember>> guildMembers(String guildId) => _local.guildMembers(guildId);

  @override
  Future<ApplyToGuildResult> applyToGuild(String guildId, String message) =>
      _local.applyToGuild(guildId, message);

  @override
  Future<ApplyToGuildResult> joinAsGuest(String guildId, String message) =>
      _local.joinAsGuest(guildId, message);

  @override
  Future<ActionResult> leaveGuest() => _local.leaveGuest();

  @override
  Future<String?> currentGuestGuildId() => _local.currentGuestGuildId();

  @override
  Future<List<GuildApplication>> guildApplications(String guildId) =>
      _local.guildApplications(guildId);

  @override
  Future<ActionResult> decideGuildApplication(String applicationId, bool accept) =>
      _local.decideGuildApplication(applicationId, accept);

  @override
  Future<ActionResult> setGuildMemberRole(String guildId, String targetUserId, GuildRole role) =>
      _local.setGuildMemberRole(guildId, targetUserId, role);

  @override
  Future<ActionResult> setGuildJoinPolicy(String guildId, GuildJoinPolicy joinPolicy) =>
      _local.setGuildJoinPolicy(guildId, joinPolicy);

  @override
  Future<ActionResult> setGuildGuestAutoAccept(String guildId, bool guestAutoAccept) =>
      _local.setGuildGuestAutoAccept(guildId, guestAutoAccept);

  @override
  Future<ActionResult> setGuildRankIconTheme(String guildId, String theme) =>
      _local.setGuildRankIconTheme(guildId, theme);

  @override
  Future<ActionResult> setGuildRankLabels(String guildId, Map<GuildRankKey, String> rankLabels) =>
      _local.setGuildRankLabels(guildId, rankLabels);

  @override
  Future<ActionResult> setGuildEmblem(String guildId, GuildEmblem emblem) =>
      _local.setGuildEmblem(guildId, emblem);

  @override
  Future<ActionResult> leaveGuild() => _local.leaveGuild();

  @override
  Future<ContributeProjectResult> contributeGuildProject(String projectId, num amount) =>
      _local.contributeGuildProject(projectId, amount);

  @override
  Future<List<GuildProject>> guildProjects(String guildId) => _local.guildProjects(guildId);

  @override
  Future<List<GuildChallenge>> guildChallenges(String guildId) => _local.guildChallenges(guildId);

  @override
  Future<String?> currentGuildId() => _local.currentGuildId();

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
  Future<GuildHallState?> guildHall(String guildId) => _local.guildHall(guildId);

  @override
  Future<GuildHallActionResult> payGuildDebt(PlayerSave save, num amount) =>
      _local.payGuildDebt(save, amount);

  @override
  Future<GuildHallActionResult> contributeHallItem(
    PlayerSave save,
    int inventoryIndex,
    num quantity,
  ) => _local.contributeHallItem(save, inventoryIndex, quantity);

  @override
  Future<GuildHallActionResult> withdrawHallItem(
    PlayerSave save,
    int storehouseIndex,
    num quantity,
  ) => _local.withdrawHallItem(save, storehouseIndex, quantity);

  @override
  Future<List<ArenaOpponent>> hallBoxingOpponents() => _local.hallBoxingOpponents();
}
