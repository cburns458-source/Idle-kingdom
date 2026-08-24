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

  /// Sets the account name from the first character name. Later names stay put.
  Future<ActionResult> claimAccountUsername(String name);

  /// Emails a one-time sign-in link, where the backend can send one.
  Future<ActionResult> sendMagicLink(String email);

  Future<void> signOut();

  /// Marks this device as the only one allowed to play. A later sign-in
  /// elsewhere replaces the id and kicks this device.
  Future<ActionResult> claimPlaySession();

  /// The account's active play session, or null when none is stored.
  Future<String?> activePlaySessionId();

  Future<MultiplayerProfile?> profile(String userId);

  Future<MultiplayerProfile?> setPrivacyPublicSkills(bool value);

  Future<MultiplayerProfile?> setPrivacyPublicGear(bool value);

  Future<MultiplayerProfile?> setChatPrivacy({String? directMessages, String? localChat});

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

  Future<ActionResult> sendFriendRequest(String targetUserId);

  Future<ActionResult> removeFriend(String targetUserId);

  Future<void> ignorePlayer(String targetUserId);

  Future<void> unignorePlayer(String targetUserId);

  Future<List<SocialContact>> friends();

  Future<List<SocialContact>> incomingFriendRequests();

  Future<List<SocialContact>> outgoingFriendRequests();

  Future<List<SocialContact>> ignoredPlayers();

  Future<CreateGuildResult> createGuild(CreateGuildInput input, num goldAvailable);

  Future<List<GuildListing>> listGuilds();

  Future<GuildRecord?> guild(String guildId);

  Future<List<GuildMember>> guildMembers(String guildId);

  Future<List<GuildGuest>> guildGuests(String guildId);

  Future<ApplyToGuildResult> applyToGuild(String guildId, String message);

  Future<ApplyToGuildResult> joinAsGuest(String guildId, String message);

  Future<ActionResult> leaveGuest();

  Future<String?> currentGuestGuildId();

  Future<List<GuildApplication>> guildApplications(String guildId);

  Future<ActionResult> decideGuildApplication(String applicationId, bool accept);

  Future<ActionResult> setGuildMemberRole(String guildId, String targetUserId, GuildRole role);

  Future<ActionResult> setGuildJoinPolicy(String guildId, GuildJoinPolicy joinPolicy);

  Future<ActionResult> setGuildGuestAutoAccept(String guildId, bool guestAutoAccept);

  Future<ActionResult> setGuildRankIconTheme(String guildId, String theme);

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

  /// Presence rows for last-online, including expired so a roster can say when.
  Future<List<ActivityPresence>> presenceRecords();

  Future<PublicPlayerProfile?> publicProfile(String userId, {GameDatabase? db});

  Future<List<BountyClaimRecord>> bountyClaims(String hourKey);

  Future<BountyClaimResult> claimBounty(String hourKey, String bountyId);

  Future<List<BazaarPost>> bazaarPosts({int limit = 40});

  Future<BazaarPostResult> postBazaar(BazaarPostKind kind, String body);

  /// Players who have a fighter snapshot others can search or rank against.
  ///
  /// Hosted play lists only accounts that pressed Save equipment. Local demo
  /// still lists stored characters so Bram, Mira, and Kael stay fightable.
  Future<List<ArenaOpponent>> listArenaOpponents();

  /// The saved PvP loadout for [userId], not their live cloud save.
  Future<PlayerSave?> readOpponentSave(String userId);

  /// Publishes [save] as the loadout others fight in the arena.
  Future<ActionResult> savePvpEquipment(PlayerSave save);

  /// The signed-in player's saved PvP loadout, or null if they have not saved.
  Future<PlayerSave?> ownPvpSnapshot();

  Future<GuildHallState?> guildHall(String guildId);

  Future<GuildHallActionResult> payGuildDebt(PlayerSave save, num amount);

  /// Puts an item into the storehouse, which is also how a tier gets paid for.
  /// Nothing comes back out, so there is no matching withdraw.
  Future<GuildHallActionResult> contributeHallItem(
    PlayerSave save,
    int inventoryIndex,
    num quantity,
  );

  Future<List<ArenaOpponent>> hallBoxingOpponents();

  /// Why the most recent read was refused, cleared by the taking.
  ///
  /// A read answers with what arrived, so a screen short of one list still draws
  /// the rest. This is how it then says why that list is short, instead of
  /// showing an empty panel that looks like a game with nothing in it.
  String? takeReadProblem();

  /// Authoritative clock for catch-up on login.
  ///
  /// Hosted play uses the server's time so a device clock cannot invent AFK
  /// progress. Local play uses the device clock.
  Future<num> authoritativeNowMs();
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

  /// A table on this device is always there to be read.
  @override
  String? takeReadProblem() => null;

  @override
  Future<num> authoritativeNowMs() async => _backend.ports.nowMs();

  @override
  Future<SessionResult> signUp(String email, String username, String password) async {
    final result = _backend.signUp(email, username, password);
    if (result.ok) _sessions.write(result.session);
    return result;
  }

  @override
  Future<ActionResult> claimAccountUsername(String name) async {
    final current = session;
    if (current == null) return const ActionResult.failed('Sign in required.');
    final result = _backend.claimAccountUsername(current.userId, name);
    if (!result.ok) return result;
    final cleaned = remoteUsername(name);
    if (isPendingAccountUsername(current.username) ||
        current.username.toLowerCase() == cleaned.toLowerCase()) {
      _sessions.write(current.copyWith(username: cleaned));
    }
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
  Future<ActionResult> claimPlaySession() async {
    final current = session;
    if (current == null) return const ActionResult.failed('Sign in to play.');
    final next = current.copyWith(playSessionId: current.playSessionId ?? newPlaySessionId());
    _sessions.write(next);
    _backend.claimPlaySession(next.userId, next.playSessionId!);
    return const ActionResult.ok();
  }

  @override
  Future<String?> activePlaySessionId() async {
    final current = session;
    if (current == null) return null;
    return _backend.activePlaySessionId(current.userId);
  }

  @override
  Future<MultiplayerProfile?> profile(String userId) async => _backend.getProfile(userId);

  @override
  Future<MultiplayerProfile?> setPrivacyPublicSkills(bool value) async {
    final current = session;
    if (current == null) return null;
    return _backend.upsertProfile(current.userId, privacyPublicSkills: value);
  }

  @override
  Future<MultiplayerProfile?> setPrivacyPublicGear(bool value) async {
    final current = session;
    if (current == null) return null;
    return _backend.upsertProfile(current.userId, privacyPublicGear: value);
  }

  @override
  Future<MultiplayerProfile?> setChatPrivacy({String? directMessages, String? localChat}) async {
    final current = session;
    if (current == null) return null;
    return _backend.upsertProfile(
      current.userId,
      privacyDirectMessages: directMessages == null ? null : normalizeChatPrivacy(directMessages),
      privacyLocalChat: localChat == null ? null : normalizeChatPrivacy(localChat),
    );
  }

  @override
  Future<CloudSyncResult> pushSave(GameDatabase db, PlayerSave save, {bool force = false}) async {
    final current = session;
    if (current == null) {
      return const CloudSyncResult.failed('Sign in to sync cloud saves.');
    }
    final stamped = save.copyWith(updatedAt: isoFromMs(_backend.ports.nowMs()));
    final validation = softValidateSave(stamped);
    if (!validation.ok) return CloudSyncResult.failed(validation.reason!);
    final refusedSession = _backend.playSessionRefusal(current.userId, current.playSessionId);
    if (refusedSession != null) return CloudSyncResult.failed(refusedSession);

    final written = _backend.writeCloudSave(current.userId, stamped, force: force);
    if (!written.ok) {
      return CloudSyncResult.failed(written.reason!, remote: written.remote);
    }
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
      return CloudSyncResult.failed('Cloud save is newer than the local save.', remote: remote);
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
    return _backend.listChat(channel, current?.userId ?? '');
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
  Future<ActionResult> sendFriendRequest(String targetUserId) async {
    final current = session;
    if (current == null) return const ActionResult.failed('Sign in required.');
    return _backend.sendFriendRequest(current.userId, targetUserId);
  }

  @override
  Future<ActionResult> removeFriend(String targetUserId) async {
    final current = session;
    if (current == null) return const ActionResult.failed('Sign in required.');
    return _backend.removeFriend(current.userId, targetUserId);
  }

  @override
  Future<void> ignorePlayer(String targetUserId) async {
    final current = session;
    if (current == null) return;
    _backend.blockUser(current.userId, targetUserId);
  }

  @override
  Future<void> unignorePlayer(String targetUserId) async {
    final current = session;
    if (current == null) return;
    _backend.unblockUser(current.userId, targetUserId);
  }

  @override
  Future<List<SocialContact>> friends() async {
    final current = session;
    if (current == null) return const <SocialContact>[];
    return _backend.listFriends(current.userId);
  }

  @override
  Future<List<SocialContact>> incomingFriendRequests() async {
    final current = session;
    if (current == null) return const <SocialContact>[];
    return _backend.listIncomingFriendRequests(current.userId);
  }

  @override
  Future<List<SocialContact>> outgoingFriendRequests() async {
    final current = session;
    if (current == null) return const <SocialContact>[];
    return _backend.listOutgoingFriendRequests(current.userId);
  }

  @override
  Future<List<SocialContact>> ignoredPlayers() async {
    final current = session;
    if (current == null) return const <SocialContact>[];
    return _backend.listIgnored(current.userId);
  }

  /// Puts the static demo guild on this device. Safe to call on every boot.
  void ensureDemoWorld(GameDatabase db) => _backend.ensureDemoWorld(db);

  /// Takes the demo guild back off this device. Safe to call on every boot.
  void clearDemoWorld() => _backend.clearDemoWorld();

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
  Future<List<GuildGuest>> guildGuests(String guildId) async => _backend.guildGuests(guildId);

  @override
  Future<ApplyToGuildResult> applyToGuild(String guildId, String message) async {
    final current = session;
    if (current == null) return const ApplyToGuildResult.failed('Sign in to apply.');
    return _backend.applyToGuild(current, guildId, message);
  }

  @override
  Future<ApplyToGuildResult> joinAsGuest(String guildId, String message) async {
    final current = session;
    if (current == null) return const ApplyToGuildResult.failed('Sign in to guest.');
    return _backend.joinAsGuest(current, guildId, message);
  }

  @override
  Future<ActionResult> leaveGuest() async {
    final current = session;
    if (current == null) return const ActionResult.failed('Sign in required.');
    return _backend.leaveGuest(current.userId);
  }

  @override
  Future<String?> currentGuestGuildId() async {
    final current = session;
    if (current == null) return null;
    return _backend.currentGuestGuildId(current.userId);
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
  Future<ActionResult> setGuildGuestAutoAccept(String guildId, bool guestAutoAccept) async {
    final current = session;
    if (current == null) return const ActionResult.failed('Sign in required.');
    return _backend.setGuildGuestAutoAccept(current.userId, guildId, guestAutoAccept);
  }

  @override
  Future<ActionResult> setGuildRankIconTheme(String guildId, String theme) async {
    final current = session;
    if (current == null) return const ActionResult.failed('Sign in required.');
    return _backend.setGuildRankIconTheme(current.userId, guildId, theme);
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
  Future<List<GuildProject>> guildProjects(String guildId) async => _backend.guildProjects(guildId);

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
  }) async => _visiblePeers(_backend.listPresence(locationId: locationId), excludeSelf);

  @override
  Future<List<ActivityPresence>> peersAtActivity(
    String locationId,
    String? activityId, {
    bool excludeSelf = true,
  }) async => _visiblePeers(
    _backend.listPresence(locationId: locationId, activityId: activityId),
    excludeSelf,
  );

  List<ActivityPresence> _visiblePeers(List<ActivityPresence> peers, bool excludeSelf) {
    final current = session;
    if (current == null) return peers;
    final hidden = _backend.blockedIds(current.userId);
    return peers
        .where((row) => !hidden.contains(row.userId))
        .where((row) => !excludeSelf || row.userId != current.userId)
        .toList();
  }

  @override
  Future<List<ActivityPresence>> citadelVisitors() async =>
      _visiblePeers(_backend.listPresence(locationId: citadelLocationId()), true);

  @override
  Future<List<ActivityPresence>> presenceRecords() async =>
      _backend.listPresence(includeExpired: true);

  @override
  Future<PublicPlayerProfile?> publicProfile(String userId, {GameDatabase? db}) async =>
      _backend.publicProfile(userId);

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
  Future<List<BazaarPost>> bazaarPosts({int limit = 40}) async => _backend.listBazaarPosts(limit);

  @override
  Future<BazaarPostResult> postBazaar(BazaarPostKind kind, String body) async {
    final current = session;
    if (current == null) {
      return const BazaarPostResult.failed('Sign in to post in the Grand Bazaar.');
    }
    return _backend.postBazaar(current, kind, body);
  }

  @override
  Future<List<ArenaOpponent>> listArenaOpponents() async {
    final current = session;
    return _backend.listArenaOpponents(excludeUserId: current?.userId);
  }

  @override
  Future<PlayerSave?> readOpponentSave(String userId) async {
    final current = session;
    if (current != null && current.userId == userId) return null;
    return _backend.opponentSave(userId);
  }

  @override
  Future<ActionResult> savePvpEquipment(PlayerSave save) async {
    final current = session;
    if (current == null) {
      return const ActionResult.failed('Sign in to save PvP equipment.');
    }
    return _backend.savePvpEquipment(current.userId, save);
  }

  @override
  Future<PlayerSave?> ownPvpSnapshot() async {
    final current = session;
    if (current == null) return null;
    return _backend.ownPvpSnapshot(current.userId);
  }

  @override
  Future<GuildHallState?> guildHall(String guildId) async => _backend.guildHall(guildId);

  @override
  Future<GuildHallActionResult> payGuildDebt(PlayerSave save, num amount) async {
    final current = session;
    if (current == null) {
      return const GuildHallActionResult.failed('Sign in to use the guild hall.');
    }
    return _backend.payGuildDebt(current.userId, save, amount);
  }

  @override
  Future<GuildHallActionResult> contributeHallItem(
    PlayerSave save,
    int inventoryIndex,
    num quantity,
  ) async {
    final current = session;
    if (current == null) {
      return const GuildHallActionResult.failed('Sign in to use the guild hall.');
    }
    return _backend.contributeHallItem(current.userId, save, inventoryIndex, quantity);
  }

  @override
  Future<List<ArenaOpponent>> hallBoxingOpponents() async {
    final current = session;
    if (current == null) return const <ArenaOpponent>[];
    return _backend.hallBoxingOpponents(current.userId);
  }
}
