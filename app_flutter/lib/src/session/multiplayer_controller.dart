import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

/// The screen-facing half of multiplayer.
///
/// Everything that decides anything lives in `ik_net`; this holds what a screen
/// needs between rebuilds — who is signed in, the guild in hand, the last board
/// that was read, who is nearby — and notifies listeners when any of it moves.
///
/// Nothing here blocks the game: a signed-out player never sees a failed call,
/// because every panel asks [isSignedIn] first, and presence is published on a
/// timer that stops with the controller.
class MultiplayerController extends ChangeNotifier {
  MultiplayerController({
    required this.database,
    required this.service,
    required this.storage,
    required this.clock,
  });

  /// The wall clock, for the read cursor a DM tab writes.
  final num Function() clock;

  final LoadedDatabase database;
  final MultiplayerService service;

  /// Where the DM read cursors live, next to the save and the backend document.
  final SaveStorage storage;

  /// How often presence is republished, matching the React client.
  static const Duration presenceInterval = Duration(seconds: 15);

  /// How often the unread count and the visitor lists are refreshed.
  static const Duration pollInterval = Duration(seconds: 4);

  Timer? _presenceTimer;
  Timer? _pollTimer;

  String? _guildId;
  GuildRecord? _guild;
  List<GuildMember> _members = const <GuildMember>[];
  List<GuildApplication> _applications = const <GuildApplication>[];
  List<GuildListing> _listings = const <GuildListing>[];
  MultiplayerBoardKey _boardKey = boardTotalLevel;
  List<LeaderboardEntry> _board = const <LeaderboardEntry>[];
  List<ActivityPresence> _peers = const <ActivityPresence>[];
  List<ActivityPresence> _citadelVisitors = const <ActivityPresence>[];
  List<ChatMessage> _messages = const <ChatMessage>[];
  List<BountyClaimRecord> _bountyClaims = const <BountyClaimRecord>[];
  List<BazaarPost> _bazaarPosts = const <BazaarPost>[];
  ChatTab _chatTab = ChatTab.global;
  int _unreadDms = 0;
  String? _notice;
  bool _busy = false;

  GameDatabase get db => database.launch;

  MultiplayerSession? get session => service.session;
  bool get isSignedIn => service.isSignedIn;

  /// Which backend this build talks to, which the account screen says out loud.
  MultiplayerMode get mode =>
      service is RemoteMultiplayerService ? MultiplayerMode.supabase : MultiplayerMode.local;

  /// The guild the player belongs to, once a refresh has looked.
  String? get guildId => _guildId;
  GuildRecord? get guild => _guild;
  List<GuildMember> get members => _members;
  List<GuildApplication> get applications => _applications;

  /// Every guild there is, for the browser. Empty while the player has one.
  List<GuildListing> get listings => _listings;

  MultiplayerBoardKey get boardKey => _boardKey;
  List<LeaderboardEntry> get board => _board;
  List<ActivityPresence> get peers => _peers;
  List<ActivityPresence> get citadelVisitors => _citadelVisitors;
  List<ChatMessage> get messages => _messages;

  /// Who claimed each of this hour's bounties first, as far as the last read saw.
  List<BountyClaimRecord> get bountyClaims => _bountyClaims;
  List<BazaarPost> get bazaarPosts => _bazaarPosts;
  ChatTab get chatTab => _chatTab;
  int get unreadDms => _unreadDms;

  /// What the last action said, success or refusal, until something else speaks.
  String? get notice => _notice;

  /// True while a call is in flight, so buttons can stop taking presses.
  bool get busy => _busy;

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }

  void announce(String? text) {
    _notice = text;
    notifyListeners();
  }

  /// Runs [action], reporting whatever it says and repainting either way.
  Future<void> run(Future<String?> Function() action) async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      _notice = await action();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // --- Accounts -------------------------------------------------------------

  Future<void> signUp(String email, String username, String password, PlayerSave save) {
    return run(() async {
      final result = await service.signUp(email, username, password);
      if (!result.ok) return result.reason;
      // A brand new account starts from the save already on the device, so the
      // first sync is an upload rather than a fight over which one is newer.
      await service.pushSave(db, save);
      await refresh(save);
      return 'Account created for ${result.session!.username}.';
    });
  }

  Future<void> signIn(String email, String password, PlayerSave save) {
    return run(() async {
      final result = await service.signIn(email, password);
      if (!result.ok) return result.reason;
      await refresh(save);
      return 'Welcome back, ${result.session!.username}.';
    });
  }

  /// Emails a one-time sign-in link, where the backend can send one.
  Future<void> sendMagicLink(String email) {
    return run(() async {
      final result = await service.sendMagicLink(email);
      return result.ok ? 'Magic link sent.' : result.reason;
    });
  }

  /// Signs out, after one last upload so nothing earned is left behind.
  Future<void> signOut(PlayerSave save) {
    return run(() async {
      await service.pushSave(db, save);
      await service.clearPresence();
      await service.signOut();
      _resetSignedOutState();
      return 'Signed out. Local save remains on this device.';
    });
  }

  void _resetSignedOutState() {
    _guildId = null;
    _guild = null;
    _members = const <GuildMember>[];
    _applications = const <GuildApplication>[];
    _listings = const <GuildListing>[];
    _board = const <LeaderboardEntry>[];
    _peers = const <ActivityPresence>[];
    _citadelVisitors = const <ActivityPresence>[];
    _messages = const <ChatMessage>[];
    _bountyClaims = const <BountyClaimRecord>[];
    _bazaarPosts = const <BazaarPost>[];
    _unreadDms = 0;
  }

  // --- Cloud saves ----------------------------------------------------------

  Future<void> pushSave(PlayerSave save) {
    return run(() async {
      final result = await service.pushSave(db, save);
      return result.ok ? 'Cloud save uploaded.' : result.reason;
    });
  }

  /// Pulls the cloud save and hands it to [onLoaded] to store and adopt.
  Future<void> pullSave(void Function(PlayerSave save) onLoaded) {
    return run(() async {
      final result = await service.pullSave();
      if (!result.ok) return result.reason;
      onLoaded(result.save!);
      return 'Cloud save loaded onto this device.';
    });
  }

  // --- Refresh --------------------------------------------------------------

  /// Reads everything a social screen shows, in one pass.
  Future<void> refresh(PlayerSave save) async {
    if (!isSignedIn) {
      _resetSignedOutState();
      notifyListeners();
      return;
    }
    _guildId = await service.currentGuildId();
    final guildId = _guildId;
    if (guildId == null) {
      _guild = null;
      _members = const <GuildMember>[];
      _applications = const <GuildApplication>[];
      _listings = await service.listGuilds();
    } else {
      _guild = await service.guild(guildId);
      _members = await service.guildMembers(guildId);
      _applications = await service.guildApplications(guildId);
      _listings = const <GuildListing>[];
    }
    _board = await service.leaderboard(_boardKey);
    _citadelVisitors = await service.citadelVisitors();
    _unreadDms = await service.countUnreadDirectMessages(_dmCursor());
    notifyListeners();
  }

  /// Starts the timers that keep presence alive and the counts current.
  ///
  /// [saveOf] is read on every tick rather than captured, because the player
  /// moves and changes clothes while the timers run.
  void startPolling(PlayerSave Function() saveOf) {
    _presenceTimer?.cancel();
    _pollTimer?.cancel();
    _presenceTimer = Timer.periodic(presenceInterval, (_) => publishPresence(saveOf()));
    _pollTimer = Timer.periodic(pollInterval, (_) => _poll(saveOf()));
    publishPresence(saveOf());
  }

  /// Stops both timers, for whoever started them going off screen.
  void stopPolling() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _poll(PlayerSave save) async {
    if (!isSignedIn) return;
    _unreadDms = await service.countUnreadDirectMessages(_dmCursor());
    _citadelVisitors = await service.citadelVisitors();
    _peers = await service.peersAtActivity(save.currentLocationId, save.currentActivityId);
    notifyListeners();
  }

  // --- Presence -------------------------------------------------------------

  /// Says where the player is, so others can see them and they can see others.
  Future<void> publishPresence(PlayerSave save) async {
    if (!isSignedIn) return;
    await service.publishPresence(presenceFromSave(save));
    _peers = await service.peersAtActivity(save.currentLocationId, save.currentActivityId);
    notifyListeners();
  }

  Future<PublicPlayerProfile?> publicProfile(String userId) => service.publicProfile(userId);

  Future<void> sendFriendRequest(String userId) {
    return run(() async {
      final result = await service.sendFriendRequest(userId);
      return result.ok ? 'Friend request sent.' : result.reason;
    });
  }

  // --- Leaderboards ---------------------------------------------------------

  Future<void> selectBoard(MultiplayerBoardKey key) async {
    _boardKey = key;
    _board = isSignedIn ? await service.leaderboard(key) : const <LeaderboardEntry>[];
    notifyListeners();
  }

  // --- Chat -----------------------------------------------------------------

  String? _dmCursor() {
    final userId = session?.userId;
    if (userId == null) return null;
    return storage.getItem(dmReadCursorKey(userId));
  }

  void _markDmsRead() {
    final userId = session?.userId;
    if (userId == null) return;
    storage.setItem(dmReadCursorKey(userId), isoFromMs(clock()));
    _unreadDms = 0;
  }

  /// Opens a chat tab and loads what it holds.
  Future<void> selectChatTab(ChatTab tab, String locationId, {bool citadelHub = false}) async {
    _chatTab = tab;
    if (!isSignedIn) {
      _messages = const <ChatMessage>[];
      notifyListeners();
      return;
    }
    if (tab == ChatTab.dm) {
      _messages = await service.listDirectMessages();
      _markDmsRead();
      notifyListeners();
      return;
    }
    final channel = chatChannelForTab(
      tab,
      locationId: locationId,
      citadelHub: citadelHub,
      guildId: _guildId,
    );
    _messages = channel == null
        ? const <ChatMessage>[]
        : await service.listChat(channel);
    notifyListeners();
  }

  /// Sends [body] to the open tab, then shows the room again.
  Future<void> sendChat(String body, String locationId, {bool citadelHub = false}) {
    return run(() async {
      final channel = chatChannelForTab(
        _chatTab,
        locationId: locationId,
        citadelHub: citadelHub,
        guildId: _guildId,
      );
      if (channel == null) return chatNoGuildNotice;
      final result = await service.sendChat(channel, body);
      if (!result.ok) return result.reason;
      _messages = await service.listChat(channel);
      return null;
    });
  }

  /// Answers a peer where they can read it, without leaving the panel.
  Future<void> sendDirectMessage(String userId, String body) {
    return run(() async {
      final me = session?.userId;
      if (me == null) return 'Sign in to chat.';
      final result = await service.sendChat(
        ChatChannel.dm(dmPairKey(me, userId)),
        body,
      );
      return result.ok ? 'Message sent.' : result.reason;
    });
  }

  // --- Guilds ---------------------------------------------------------------

  /// Creates a guild and reports what it cost, so the caller can spend it.
  Future<void> createGuild(CreateGuildInput input, PlayerSave save, void Function(num goldCost) onPaid) {
    return run(() async {
      final result = await service.createGuild(input, save.gold);
      if (!result.ok) return result.reason;
      onPaid(result.goldCost!);
      await refresh(save);
      return 'Guild created.';
    });
  }

  Future<void> applyToGuild(String guildId, String message, PlayerSave save) {
    return run(() async {
      final result = await service.applyToGuild(guildId, message);
      if (!result.ok) return result.reason;
      final joined = result.joined ?? false;
      await refresh(save);
      return joined ? 'Joined the guild.' : 'Application sent.';
    });
  }

  Future<void> decideApplication(String applicationId, bool accept, PlayerSave save) {
    return run(() async {
      final result = await service.decideGuildApplication(applicationId, accept);
      if (!result.ok) return result.reason;
      await refresh(save);
      return accept ? 'Accepted.' : 'Declined.';
    });
  }

  Future<void> setMemberRole(String userId, GuildRole role, PlayerSave save) {
    return run(() async {
      final guildId = _guildId;
      if (guildId == null) return 'Join a guild first.';
      final result = await service.setGuildMemberRole(guildId, userId, role);
      if (!result.ok) return result.reason;
      await refresh(save);
      return 'Rank updated.';
    });
  }

  /// Saves the three things guild settings can change, stopping at the first no.
  Future<void> saveGuildSettings({
    required GuildJoinPolicy joinPolicy,
    required GuildEmblem emblem,
    required Map<GuildRankKey, String> rankLabels,
    required PlayerSave save,
  }) {
    return run(() async {
      final guildId = _guildId;
      if (guildId == null) return 'Join a guild first.';
      final policy = await service.setGuildJoinPolicy(guildId, joinPolicy);
      if (!policy.ok) return policy.reason;
      final banner = await service.setGuildEmblem(guildId, emblem);
      if (!banner.ok) return banner.reason;
      final ranks = await service.setGuildRankLabels(guildId, rankLabels);
      if (!ranks.ok) return ranks.reason;
      await refresh(save);
      return 'Guild settings saved.';
    });
  }

  // --- Citadel boards -------------------------------------------------------

  /// Reads the hour's first turn-ins, so the board can name who beat the player.
  Future<void> refreshBountyClaims(String hourKey) async {
    _bountyClaims = isSignedIn
        ? await service.bountyClaims(hourKey)
        : const <BountyClaimRecord>[];
    notifyListeners();
  }

  /// Turns [bounty] in, handing the paid save to [onPaid] to commit.
  Future<void> turnIn(
    BountyDefinition bounty,
    PlayerSave save,
    num nowMs,
    void Function(PlayerSave save) onPaid,
  ) {
    return run(() async {
      final result = await turnInBounty(service, db, save, bounty, nowMs);
      if (!result.ok) {
        await refreshBountyClaims(hourlyBountyBoard(nowMs).hourKey);
        return result.reason;
      }
      onPaid(result.save!);
      await refreshBountyClaims(result.claim!.hourKey);
      return bountyClaimedNotice(result.goldGained!, result.firstCompleter!);
    });
  }

  Future<void> refreshBazaar() async {
    _bazaarPosts = isSignedIn ? await service.bazaarPosts() : const <BazaarPost>[];
    notifyListeners();
  }

  /// Posts to the Bazaar and shows the board again, or says why it was refused.
  Future<void> postToBazaar(BazaarPostKind kind, String body) {
    return run(() async {
      final result = await service.postBazaar(kind, body);
      if (!result.ok) return result.reason;
      await refreshBazaar();
      return bazaarPostedNotice;
    });
  }

  Future<void> leaveGuild(PlayerSave save) {
    return run(() async {
      final result = await service.leaveGuild();
      if (!result.ok) return result.reason;
      await refresh(save);
      return 'Left guild.';
    });
  }
}
