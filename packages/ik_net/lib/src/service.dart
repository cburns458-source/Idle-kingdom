import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'bazaar.dart';
import 'cloud_save.dart';
import 'local_backend.dart';
import 'presence.dart';
import 'remote.dart';
import 'results.dart';
import 'session_store.dart';
import 'types.dart';

/// What the client calls for anything that involves other players.
///
/// Every method is asynchronous even where the local backend answers at once,
/// because a remote backend cannot, and the UI must not be written twice.
abstract interface class MultiplayerService {
  /// The signed-in session, or null. Read synchronously: the UI decides whether
  /// to draw a social panel at all from this.
  MultiplayerSession? get session;

  bool get isSignedIn;

  Future<SessionResult> signUp(String email, String username, String password);

  Future<SessionResult> signIn(String email, String password);

  /// Emails a one-time sign-in link, where the backend can send one.
  Future<ActionResult> sendMagicLink(String email);

  Future<void> signOut();

  Future<MultiplayerProfile?> profile(String userId);

  Future<MultiplayerProfile?> setPrivacyPublicSkills(bool value);

  /// Uploads [save] as the account's cloud copy.
  ///
  /// [force] is the player choosing this save over the stored one, having been
  /// shown that the other is newer.
  Future<CloudSyncResult> pushSave(GameDatabase db, PlayerSave save, {bool force = false});

  Future<CloudSyncResult> pullSave();

  /// Uploads at a safe point, or reports that the backend's copy is newer.
  Future<CloudSyncResult> syncSave(GameDatabase db, PlayerSave local, {bool forceUpload = false});

  Future<ActionResult> submitLeaderboard(GameDatabase db, PlayerSave save);

  Future<List<LeaderboardEntry>> leaderboard(MultiplayerBoardKey boardKey, {int limit = 25});

  Future<ChatSendResult> sendChat(ChatChannel channel, String body);

  Future<List<ChatMessage>> listChat(ChatChannel channel);

  Future<List<ChatMessage>> listDirectMessages();

  Future<int> countUnreadDirectMessages(String? sinceIso);

  Future<void> mutePlayer(String targetUserId);

  Future<void> blockPlayer(String targetUserId);

  Future<void> reportPlayer(String targetUserId, String reason);

  Future<CreateGuildResult> createGuild(CreateGuildInput input, num goldAvailable);

  Future<List<GuildListing>> listGuilds();

  Future<GuildRecord?> guild(String guildId);

  Future<List<GuildMember>> guildMembers(String guildId);

  Future<ApplyToGuildResult> applyToGuild(String guildId, String message);

  Future<List<GuildApplication>> guildApplications(String guildId);

  Future<ActionResult> decideGuildApplication(String applicationId, bool accept);

  Future<ActionResult> setGuildMemberRole(String guildId, String targetUserId, GuildRole role);

  Future<ActionResult> setGuildJoinPolicy(String guildId, GuildJoinPolicy joinPolicy);

  Future<ActionResult> setGuildRankLabels(String guildId, Map<GuildRankKey, String> rankLabels);

  Future<ActionResult> setGuildEmblem(String guildId, GuildEmblem emblem);

  Future<ActionResult> leaveGuild();

  Future<ContributeProjectResult> contributeGuildProject(String projectId, num amount);

  Future<List<GuildProject>> guildProjects(String guildId);

  Future<List<GuildChallenge>> guildChallenges(String guildId);

  /// The guild the signed-in player belongs to, read from their profile.
  Future<String?> currentGuildId();

  Future<ActivityPresence?> publishPresence(PresenceInput input);

  Future<void> clearPresence();

  Future<List<ActivityPresence>> peersAtLocation(String locationId, {bool excludeSelf = true});

  Future<List<ActivityPresence>> peersAtActivity(
    String locationId,
    String? activityId, {
    bool excludeSelf = true,
  });

  /// Whoever is standing in the Citadel, which is one crowd across its districts.
  Future<List<ActivityPresence>> citadelVisitors();

  Future<PublicPlayerProfile?> publicProfile(String userId);

  Future<ActionResult> sendFriendRequest(String targetUserId);

  Future<List<BountyClaimRecord>> bountyClaims(String hourKey);

  Future<BountyClaimResult> claimBounty(String hourKey, String bountyId);

  Future<List<BazaarPost>> bazaarPosts({int limit = 40});

  Future<BazaarPostResult> postBazaar(BazaarPostKind kind, String body);
}

/// The single-device implementation: the local backend plus the stored session.
class LocalMultiplayerService implements MultiplayerService {
  LocalMultiplayerService({required SaveStorage storage, LocalBackendPorts? ports})
    : _sessions = SessionStore(storage),
      _backend = LocalMultiplayerBackend(storage: storage, ports: ports);

  final SessionStore _sessions;
  final LocalMultiplayerBackend _backend;

  /// Exposed so a client can seed a demo world or inspect stored rows; the UI
  /// itself only ever goes through the service.
  LocalMultiplayerBackend get backend => _backend;

  @override
  MultiplayerSession? get session => _sessions.read();

  @override
  bool get isSignedIn => _sessions.isSignedIn;

  @override
  Future<SessionResult> signUp(String email, String username, String password) async {
    final result = _backend.signUp(email, username, password);
    if (result.ok) _sessions.write(result.session);
    return result;
  }

  @override
  Future<SessionResult> signIn(String email, String password) async {
    final result = _backend.signIn(email, password);
    if (result.ok) _sessions.write(result.session);
    return result;
  }

  /// Nothing to send to: an account here only exists on this device.
  @override
  Future<ActionResult> sendMagicLink(String email) async =>
      const ActionResult.failed(remoteMagicLinkUnavailable);

  @override
  Future<void> signOut() async => _sessions.write(null);

  @override
  Future<MultiplayerProfile?> profile(String userId) async => _backend.getProfile(userId);

  @override
  Future<MultiplayerProfile?> setPrivacyPublicSkills(bool value) async {
    final current = session;
    if (current == null) return null;
    return _backend.upsertProfile(current.userId, privacyPublicSkills: value);
  }

  @override
  Future<CloudSyncResult> pushSave(
    GameDatabase db,
    PlayerSave save, {
    bool force = false,
  }) async {
    final current = session;
    if (current == null) {
      return const CloudSyncResult.failed('Sign in to sync cloud saves.');
    }
    final stamped = save.copyWith(updatedAt: isoFromMs(_backend.ports.nowMs()));
    final validation = softValidateSave(stamped);
    if (!validation.ok) return CloudSyncResult.failed(validation.reason!);

    final written = _backend.writeCloudSave(current.userId, stamped, force: force);
    if (!written.ok) {
      return CloudSyncResult.failed(written.reason!, remote: written.remote);
    }
    _backend.submitLeaderboardSnapshot(db, current.userId, stamped);
    _backend.upsertProfile(
      current.userId,
      appearance: stamped.appearance,
      username: isNotBlank(stamped.characterName) ? stamped.characterName : current.username,
    );
    return CloudSyncResult.ok(stamped, CloudSyncSource.uploaded);
  }

  @override
  Future<CloudSyncResult> pullSave() async {
    final current = session;
    if (current == null) {
      return const CloudSyncResult.failed('Sign in to load cloud saves.');
    }
    final remote = _backend.readCloudSave(current.userId);
    if (remote == null) {
      return const CloudSyncResult.failed('No cloud save for this account yet.');
    }
    final validation = softValidateSave(remote.payload);
    if (!validation.ok) return CloudSyncResult.failed(validation.reason!);
    return CloudSyncResult.ok(
      parseSave(remote.payload.toJson(), _backend.ports.nowMs()),
      CloudSyncSource.downloaded,
    );
  }

  @override
  Future<CloudSyncResult> syncSave(
    GameDatabase db,
    PlayerSave local, {
    bool forceUpload = false,
  }) async {
    final current = session;
    if (current == null) return CloudSyncResult.ok(local, CloudSyncSource.unchanged);
    final remote = _backend.readCloudSave(current.userId);
    if (remote == null || forceUpload) return pushSave(db, local, force: forceUpload);
    if (remoteSaveWins(local, remote.payload)) {
      return CloudSyncResult.failed(
        'Cloud save is newer than the local save.',
        remote: remote,
      );
    }
    return pushSave(db, local);
  }

  @override
  Future<ActionResult> submitLeaderboard(GameDatabase db, PlayerSave save) async {
    final current = session;
    if (current == null) {
      return const ActionResult.failed('Sign in to submit leaderboard scores.');
    }
    _backend.submitLeaderboardSnapshot(db, current.userId, save);
    return const ActionResult.ok();
  }

  @override
  Future<List<LeaderboardEntry>> leaderboard(
    MultiplayerBoardKey boardKey, {
    int limit = 25,
  }) async => _backend.listLeaderboard(boardKey, limit);

  @override
  Future<ChatSendResult> sendChat(ChatChannel channel, String body) async {
    final current = session;
    if (current == null) return const ChatSendResult.failed('Sign in to chat.');
    return _backend.sendChat(current, channel, body);
  }

  @override
  Future<List<ChatMessage>> listChat(ChatChannel channel) async {
    final current = session;
    if (current == null) return const <ChatMessage>[];
    return _backend.listChat(channel, current.userId);
  }

  @override
  Future<List<ChatMessage>> listDirectMessages() async {
    final current = session;
    if (current == null) return const <ChatMessage>[];
    return _backend.listDirectMessages(current.userId);
  }

  @override
  Future<int> countUnreadDirectMessages(String? sinceIso) async {
    final current = session;
    if (current == null) return 0;
    return _backend.countUnreadDirectMessages(current.userId, sinceIso);
  }

  @override
  Future<void> mutePlayer(String targetUserId) async {
    final current = session;
    if (current == null) return;
    _backend.muteUser(current.userId, targetUserId);
  }

  @override
  Future<void> blockPlayer(String targetUserId) async {
    final current = session;
    if (current == null) return;
    _backend.blockUser(current.userId, targetUserId);
  }

  @override
  Future<void> reportPlayer(String targetUserId, String reason) async {
    final current = session;
    if (current == null) return;
    _backend.reportUser(current.userId, targetUserId, reason);
  }

  @override
  Future<CreateGuildResult> createGuild(CreateGuildInput input, num goldAvailable) async {
    final current = session;
    if (current == null) return const CreateGuildResult.failed('Sign in to create a guild.');
    return _backend.createGuild(current, input, goldAvailable);
  }

  @override
  Future<List<GuildListing>> listGuilds() async => _backend.listGuilds();

  @override
  Future<GuildRecord?> guild(String guildId) async => _backend.getGuild(guildId);

  @override
  Future<List<GuildMember>> guildMembers(String guildId) async => _backend.guildMembers(guildId);

  @override
  Future<ApplyToGuildResult> applyToGuild(String guildId, String message) async {
    final current = session;
    if (current == null) return const ApplyToGuildResult.failed('Sign in to apply.');
    return _backend.applyToGuild(current, guildId, message);
  }

  @override
  Future<List<GuildApplication>> guildApplications(String guildId) async =>
      _backend.listApplications(guildId);

  @override
  Future<ActionResult> decideGuildApplication(String applicationId, bool accept) async {
    final current = session;
    if (current == null) return const ActionResult.failed('Sign in required.');
    return _backend.decideApplication(current.userId, applicationId, accept);
  }

  @override
  Future<ActionResult> setGuildMemberRole(
    String guildId,
    String targetUserId,
    GuildRole role,
  ) async {
    final current = session;
    if (current == null) return const ActionResult.failed('Sign in required.');
    return _backend.setMemberRole(current.userId, guildId, targetUserId, role);
  }

  @override
  Future<ActionResult> setGuildJoinPolicy(String guildId, GuildJoinPolicy joinPolicy) async {
    final current = session;
    if (current == null) return const ActionResult.failed('Sign in required.');
    return _backend.setGuildJoinPolicy(current.userId, guildId, joinPolicy);
  }

  @override
  Future<ActionResult> setGuildRankLabels(
    String guildId,
    Map<GuildRankKey, String> rankLabels,
  ) async {
    final current = session;
    if (current == null) return const ActionResult.failed('Sign in required.');
    return _backend.setGuildRankLabels(current.userId, guildId, rankLabels);
  }

  @override
  Future<ActionResult> setGuildEmblem(String guildId, GuildEmblem emblem) async {
    final current = session;
    if (current == null) return const ActionResult.failed('Sign in required.');
    return _backend.setGuildEmblem(current.userId, guildId, emblem);
  }

  @override
  Future<ActionResult> leaveGuild() async {
    final current = session;
    if (current == null) return const ActionResult.failed('Sign in required.');
    return _backend.leaveGuild(current.userId);
  }

  @override
  Future<ContributeProjectResult> contributeGuildProject(String projectId, num amount) async {
    final current = session;
    if (current == null) return const ContributeProjectResult.failed('Sign in required.');
    return _backend.contributeToProject(current.userId, projectId, amount);
  }

  @override
  Future<List<GuildProject>> guildProjects(String guildId) async =>
      _backend.guildProjects(guildId);

  @override
  Future<List<GuildChallenge>> guildChallenges(String guildId) async {
    _backend.refreshGuildChallengeAggregates(guildId);
    return _backend.guildChallenges(guildId);
  }

  @override
  Future<String?> currentGuildId() async {
    final current = session;
    if (current == null) return null;
    return _backend.getProfile(current.userId)?.guildId;
  }

  @override
  Future<ActivityPresence?> publishPresence(PresenceInput input) async {
    final current = session;
    if (current == null) return null;
    return _backend.upsertPresence(current, input);
  }

  @override
  Future<void> clearPresence() async {
    final current = session;
    if (current == null) return;
    _backend.clearPresence(current.userId);
  }

  @override
  Future<List<ActivityPresence>> peersAtLocation(
    String locationId, {
    bool excludeSelf = true,
  }) async => _withoutSelf(_backend.listPresence(locationId: locationId), excludeSelf);

  @override
  Future<List<ActivityPresence>> peersAtActivity(
    String locationId,
    String? activityId, {
    bool excludeSelf = true,
  }) async => _withoutSelf(
    _backend.listPresence(locationId: locationId, activityId: activityId),
    excludeSelf,
  );

  List<ActivityPresence> _withoutSelf(List<ActivityPresence> peers, bool excludeSelf) {
    final current = session;
    if (!excludeSelf || current == null) return peers;
    return peers.where((row) => row.userId != current.userId).toList();
  }

  @override
  Future<List<ActivityPresence>> citadelVisitors() async =>
      _withoutSelf(_backend.listPresence(locationId: citadelLocationId()), true);

  @override
  Future<PublicPlayerProfile?> publicProfile(String userId) async =>
      _backend.publicProfile(userId);

  @override
  Future<ActionResult> sendFriendRequest(String targetUserId) async {
    final current = session;
    if (current == null) return const ActionResult.failed('Sign in required.');
    return _backend.sendFriendRequest(current.userId, targetUserId);
  }

  @override
  Future<List<BountyClaimRecord>> bountyClaims(String hourKey) async =>
      _backend.listBountyClaims(hourKey);

  @override
  Future<BountyClaimResult> claimBounty(String hourKey, String bountyId) async {
    final current = session;
    if (current == null) return const BountyClaimResult.failed('Sign in to claim bounties.');
    return _backend.claimBounty(current, hourKey, bountyId);
  }

  @override
  Future<List<BazaarPost>> bazaarPosts({int limit = 40}) async =>
      _backend.listBazaarPosts(limit);

  @override
  Future<BazaarPostResult> postBazaar(BazaarPostKind kind, String body) async {
    final current = session;
    if (current == null) {
      return const BazaarPostResult.failed('Sign in to post in the Grand Bazaar.');
    }
    return _backend.postBazaar(current, kind, body);
  }
}
