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

  static const String chatFilterStorageKey = 'idle-kingdoms.client.filter-chat-profanity';

  static const String browseSocialStorageKey = 'idle-kingdoms.client.browse-social-unsigned';

  bool get filterChatProfanity => storage.getItem(chatFilterStorageKey) != '0';

  void setFilterChatProfanity(bool value) {
    storage.setItem(chatFilterStorageKey, value ? '1' : '0');
    notifyListeners();
  }

  /// When on, Guilds, Leaderboards, Chat, and Nearby open without an account.
  bool get canBrowseSocial => storage.getItem(browseSocialStorageKey) == '1';

  /// True when a social page should render its lists instead of a sign-in wall.
  bool get canSeeSocialPages => isSignedIn || canBrowseSocial;

  void setBrowseSocialUnsigned(bool value) {
    storage.setItem(browseSocialStorageKey, value ? '1' : '0');
    if (!value && !isSignedIn) _resetSignedOutState();
    notifyListeners();
  }

  /// How often presence is republished so the player stays on nearby lists.
  static const Duration presenceInterval = Duration(seconds: 15);

  /// How often the unread count and the visitor lists are refreshed.
  static const Duration pollInterval = Duration(seconds: 4);

  /// How long play can sit in memory before it is written to the account.
  static const Duration accountSaveDebounce = Duration(seconds: 8);

  Timer? _presenceTimer;
  Timer? _pollTimer;

  String? _guildId;
  GuildRecord? _guild;
  String? _guestGuildId;
  GuildRecord? _guestGuild;
  List<GuildMember> _members = const <GuildMember>[];
  List<GuildGuest> _guests = const <GuildGuest>[];
  List<GuildApplication> _applications = const <GuildApplication>[];
  List<GuildListing> _listings = const <GuildListing>[];
  MultiplayerBoardKey _boardKey = boardTotalLevel;
  List<LeaderboardEntry> _board = const <LeaderboardEntry>[];
  List<ActivityPresence> _peers = const <ActivityPresence>[];
  List<ActivityPresence> _citadelVisitors = const <ActivityPresence>[];
  List<ActivityPresence> _presence = const <ActivityPresence>[];
  List<SocialContact> _friends = const <SocialContact>[];
  List<SocialContact> _incomingFriendRequests = const <SocialContact>[];
  List<SocialContact> _outgoingFriendRequests = const <SocialContact>[];
  List<SocialContact> _ignored = const <SocialContact>[];
  List<ChatMessage> _messages = const <ChatMessage>[];
  List<BountyClaimRecord> _bountyClaims = const <BountyClaimRecord>[];
  List<BazaarPost> _bazaarPosts = const <BazaarPost>[];
  ChatTab _chatTab = ChatTab.global;
  int _unreadDms = 0;
  String? _notice;
  bool _busy = false;
  bool _suppressUploads = false;
  PlayerSave? _pendingAccountSave;
  Timer? _accountSaveTimer;

  /// A named save this device still holds from before accounts owned the save.
  /// Used once if the account has no playable row yet, then forgotten.
  PlayerSave? pendingLeftover;

  /// Called after sign-out or a kick so the shell can drop the character.
  VoidCallback? onAccountCleared;

  /// Called once the account has a playable save, so a leftover device file can go.
  VoidCallback? onAccountSaveReady;

  GameDatabase get db => database.launch;

  MultiplayerSession? get session => service.session;
  bool get isSignedIn => service.isSignedIn;

  /// Which backend this build talks to, which the account screen says out loud.
  MultiplayerMode get mode =>
      service is RemoteMultiplayerService ? MultiplayerMode.supabase : MultiplayerMode.local;

  /// The guild the player belongs to, once a refresh has looked.
  String? get guildId => _guildId;
  GuildRecord? get guild => _guild;
  String? get guestGuildId => _guestGuildId;
  GuildRecord? get guestGuild => _guestGuild;
  List<GuildMember> get members => _members;
  List<GuildGuest> get guests => _guests;
  List<GuildApplication> get applications => _applications;

  /// Every guild there is, for the browser and for guesting from chat.
  List<GuildListing> get listings => _listings;

  MultiplayerBoardKey get boardKey => _boardKey;
  List<LeaderboardEntry> get board => _board;
  List<ActivityPresence> get peers => _peers;
  List<ActivityPresence> get citadelVisitors => _citadelVisitors;
  List<ActivityPresence> get presence => _presence;
  List<SocialContact> get friends => _friends;
  List<SocialContact> get incomingFriendRequests => _incomingFriendRequests;
  List<SocialContact> get outgoingFriendRequests => _outgoingFriendRequests;
  List<SocialContact> get ignoredPlayers => _ignored;
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
    _accountSaveTimer?.cancel();
    stopPolling();
    super.dispose();
  }

  void announce(String? text) {
    _notice = text;
    notifyListeners();
  }

  /// Runs [action], reporting whatever it says and repainting either way.
  ///
  /// A thrown error is reported too. Without this a dropped connection or a
  /// backend that refuses in a way no result covers would leave the button
  /// pressed and the screen unchanged, which reads as the game ignoring you.
  Future<void> run(Future<String?> Function() action) async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      _notice = await action();
    } on Object catch (error) {
      _notice = unexpectedSocialError(error);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // --- Accounts -------------------------------------------------------------

  Future<void> signUp(
    String email,
    String username,
    String password,
    PlayerSave localHint, {
    required void Function(PlayerSave save) adopt,
  }) {
    return run(() async {
      final result = await service.signUp(email, username, password);
      if (!result.ok) return result.reason;
      await service.claimPlaySession();
      final playable = await _adoptAccountSave(localHint, adopt);
      String? claimReason;
      final leftoverName = playable?.characterName?.trim() ?? '';
      if (leftoverName.isNotEmpty) {
        final claimed = await service.claimAccountUsername(leftoverName);
        if (!claimed.ok) claimReason = claimed.reason;
      }
      await refresh(playable ?? localHint);
      if (playable != null) await maybeAutoSubmitRanking(playable);
      if (claimReason != null) return claimReason;
      final accountName = service.session?.username;
      if (accountName != null && !isPendingAccountUsername(accountName)) {
        return 'Account created for $accountName.';
      }
      return 'Account created.';
    });
  }

  /// Sets the account name from the first character name. Later names stay put.
  Future<String?> claimAccountUsername(String name) async {
    final result = await service.claimAccountUsername(name);
    notifyListeners();
    return result.ok ? null : result.reason;
  }

  Future<void> signIn(
    String email,
    String password,
    PlayerSave localHint, {
    required void Function(PlayerSave save) adopt,
  }) {
    return run(() async {
      final result = await service.signIn(email, password);
      if (!result.ok) return result.reason;
      await service.claimPlaySession();
      final playable = await _adoptAccountSave(localHint, adopt);
      await refresh(playable ?? localHint);
      if (playable != null) await maybeAutoSubmitRanking(playable);
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

  /// Signs out after writing the account save, then drops the character here.
  Future<void> signOut(PlayerSave save) {
    return run(() async {
      await flushAccountSave(save);
      await service.clearPresence();
      await service.signOut();
      _clearAccountLocally();
      return 'Signed out.';
    });
  }

  /// Rejoins an already-stored session: keep the seat if we still hold it,
  /// otherwise this device is kicked.
  Future<void> resumeAccount(
    PlayerSave localHint, {
    required void Function(PlayerSave save) adopt,
  }) {
    return run(() async {
      if (!isSignedIn) return null;
      final mine = session?.playSessionId;
      final active = await service.activePlaySessionId();
      if (mine != null && active != null && mine != active) {
        await _kickFromOtherDevice();
        return remoteSignedInElsewhere;
      }
      await service.claimPlaySession();
      final playable = await _adoptAccountSave(localHint, adopt);
      await refresh(playable ?? localHint);
      if (playable != null) await maybeAutoSubmitRanking(playable);
      return null;
    });
  }

  void _resetSignedOutState() {
    _guildId = null;
    _guild = null;
    _guestGuildId = null;
    _guestGuild = null;
    _members = const <GuildMember>[];
    _guests = const <GuildGuest>[];
    _applications = const <GuildApplication>[];
    _listings = const <GuildListing>[];
    _board = const <LeaderboardEntry>[];
    _peers = const <ActivityPresence>[];
    _citadelVisitors = const <ActivityPresence>[];
    _presence = const <ActivityPresence>[];
    _friends = const <SocialContact>[];
    _incomingFriendRequests = const <SocialContact>[];
    _outgoingFriendRequests = const <SocialContact>[];
    _ignored = const <SocialContact>[];
    _messages = const <ChatMessage>[];
    _bountyClaims = const <BountyClaimRecord>[];
    _bazaarPosts = const <BazaarPost>[];
    _unreadDms = 0;
  }

  // --- Account saves --------------------------------------------------------

  static bool isPlayableSave(PlayerSave? save) {
    if (save == null) return false;
    final name = save.characterName?.trim() ?? '';
    return name.isNotEmpty && save.raceId != null;
  }

  PlayerSave? _bestLeftover(PlayerSave localHint) {
    if (isPlayableSave(pendingLeftover)) return pendingLeftover;
    if (isPlayableSave(localHint)) return localHint;
    return null;
  }

  /// Loads the account row, or promotes a leftover named save onto the account.
  Future<PlayerSave?> _adoptAccountSave(
    PlayerSave localHint,
    void Function(PlayerSave save) adopt,
  ) async {
    final pulled = await service.pullSave();
    if (pulled.ok && isPlayableSave(pulled.save)) {
      adopt(pulled.save!);
      pendingLeftover = null;
      onAccountSaveReady?.call();
      return pulled.save;
    }
    final leftover = _bestLeftover(localHint);
    if (leftover != null) {
      if (!identical(leftover, localHint)) adopt(leftover);
      await service.pushSave(db, leftover, force: true);
      pendingLeftover = null;
      onAccountSaveReady?.call();
      return leftover;
    }
    return null;
  }

  /// Queues the live save for the account. Unnamed stubs are not written.
  void scheduleAccountSave(PlayerSave save) {
    if (!isSignedIn || _suppressUploads || !isPlayableSave(save)) return;
    _pendingAccountSave = save;
    _accountSaveTimer?.cancel();
    _accountSaveTimer = Timer(accountSaveDebounce, () {
      unawaited(flushAccountSave());
    });
  }

  /// Writes the pending (or given) save to the account now.
  Future<void> flushAccountSave([PlayerSave? save]) async {
    _accountSaveTimer?.cancel();
    _accountSaveTimer = null;
    final outgoing = save ?? _pendingAccountSave;
    _pendingAccountSave = null;
    if (!isSignedIn || _suppressUploads || !isPlayableSave(outgoing)) return;
    await service.pushSave(db, outgoing!, force: true);
    await maybeAutoSubmitRanking(outgoing);
  }

  /// Publishes a just-created character immediately.
  Future<void> publishAccountSave(PlayerSave save) => flushAccountSave(save);

  void _clearAccountLocally() {
    _suppressUploads = true;
    _accountSaveTimer?.cancel();
    _accountSaveTimer = null;
    _pendingAccountSave = null;
    pendingLeftover = null;
    stopPolling();
    _resetSignedOutState();
    onAccountCleared?.call();
    _suppressUploads = false;
  }

  Future<void> _kickFromOtherDevice() async {
    _suppressUploads = true;
    _accountSaveTimer?.cancel();
    _accountSaveTimer = null;
    _pendingAccountSave = null;
    await service.clearPresence();
    await service.signOut();
    _clearAccountLocally();
    _notice = remoteSignedInElsewhere;
  }

  // --- Refresh --------------------------------------------------------------

  /// Reads everything a social screen shows, in one pass.
  ///
  /// A read that fails reports itself and repaints with whatever did arrive. A
  /// screen with nothing on it and nothing to say looks like a broken game.
  Future<void> refresh(PlayerSave save) async {
    try {
      await _refresh(save);
      final problem = service.takeReadProblem();
      if (problem != null) {
        _notice = problem;
        notifyListeners();
      }
    } on Object catch (error) {
      _notice = unexpectedSocialError(error);
      notifyListeners();
    }
  }

  Future<void> _refresh(PlayerSave save) async {
    if (!isSignedIn && !canBrowseSocial) {
      _resetSignedOutState();
      notifyListeners();
      return;
    }
    if (!isSignedIn) {
      _listings = await service.listGuilds();
      _board = await _readBoard(save);
      _citadelVisitors = await service.citadelVisitors();
      _presence = await service.presenceRecords();
      _peers = await service.peersAtLocation(save.currentLocationId);
      notifyListeners();
      return;
    }
    _guildId = await service.currentGuildId();
    _guestGuildId = await service.currentGuestGuildId();
    _listings = await service.listGuilds();
    final guildId = _guildId;
    if (guildId == null) {
      _guild = null;
      _members = const <GuildMember>[];
      _guests = const <GuildGuest>[];
      _applications = const <GuildApplication>[];
    } else {
      _guild = await service.guild(guildId);
      _members = await service.guildMembers(guildId);
      _guests = await service.guildGuests(guildId);
      _applications = await service.guildApplications(guildId);
    }
    final guestId = _guestGuildId;
    _guestGuild = guestId == null ? null : await service.guild(guestId);
    _board = await _readBoard(save);
    _citadelVisitors = await service.citadelVisitors();
    _presence = await service.presenceRecords();
    _unreadDms = await service.countUnreadDirectMessages(_dmCursor());
    await _loadSocialLists();
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
    if (await _wasKicked()) return;
    _unreadDms = await service.countUnreadDirectMessages(_dmCursor());
    _citadelVisitors = await service.citadelVisitors();
    _presence = await service.presenceRecords();
    _peers = await service.peersAtLocation(save.currentLocationId);
    notifyListeners();
  }

  Future<bool> _wasKicked() async {
    final mine = session?.playSessionId;
    if (mine == null) return false;
    final active = await service.activePlaySessionId();
    if (active == null || active == mine) return false;
    await _kickFromOtherDevice();
    notifyListeners();
    return true;
  }

  // --- Presence -------------------------------------------------------------

  /// Says where the player is, so others can see them and they can see others.
  Future<void> publishPresence(PlayerSave save) async {
    if (!isSignedIn) return;
    await service.publishPresence(presenceFromSave(save));
    _peers = await service.peersAtLocation(save.currentLocationId);
    await _loadSocialLists();
    notifyListeners();
  }

  Future<PublicPlayerProfile?> publicProfile(String userId) => service.publicProfile(userId);

  bool isFriend(String userId) => _friends.any((row) => row.userId == userId);

  bool hasIncomingRequestFrom(String userId) =>
      _incomingFriendRequests.any((row) => row.userId == userId);

  bool hasOutgoingRequestTo(String userId) =>
      _outgoingFriendRequests.any((row) => row.userId == userId);

  bool isIgnored(String userId) => _ignored.any((row) => row.userId == userId);

  Future<void> _loadSocialLists() async {
    _friends = await service.friends();
    _incomingFriendRequests = await service.incomingFriendRequests();
    _outgoingFriendRequests = await service.outgoingFriendRequests();
    _ignored = await service.ignoredPlayers();
  }

  Future<void> sendFriendRequest(String userId) {
    return run(() async {
      final result = await service.sendFriendRequest(userId);
      await _loadSocialLists();
      if (!result.ok) return result.reason;
      return isFriend(userId) ? 'You are now friends.' : 'Friend request sent.';
    });
  }

  Future<void> removeFriend(String userId) {
    return run(() async {
      final result = await service.removeFriend(userId);
      await _loadSocialLists();
      return result.ok ? 'Removed from friends.' : result.reason;
    });
  }

  Future<void> ignorePlayer(String userId) {
    return run(() async {
      await service.ignorePlayer(userId);
      await _loadSocialLists();
      _peers = _peers.where((row) => row.userId != userId).toList();
      return 'Ignored.';
    });
  }

  Future<void> unignorePlayer(String userId) {
    return run(() async {
      await service.unignorePlayer(userId);
      await _loadSocialLists();
      return 'No longer ignored.';
    });
  }

  // --- Leaderboards ---------------------------------------------------------

  num? get lastRankingSubmitAt {
    final userId = session?.userId;
    if (userId == null) return null;
    return parseRankingSubmitAt(storage.getItem(rankingUpdateStorageKey(userId)));
  }

  bool get canPressUpdateRanking => isSignedIn && canUpdateRanking(lastRankingSubmitAt, clock());

  String get rankingUpdateHintText => rankingUpdateHint(lastRankingSubmitAt, clock());

  void _storeRankingSubmitAt(num nowMs) {
    final userId = session?.userId;
    if (userId == null) return;
    storage.setItem(rankingUpdateStorageKey(userId), nowMs.toString());
  }

  /// Quiet submit as the account saves, at the same rate the button allows.
  ///
  /// No notice: the player did not press anything, and a board that cannot be
  /// posted to is not something they can act on.
  Future<void> maybeAutoSubmitRanking(PlayerSave save) async {
    if (!isSignedIn || !isPlayableSave(save)) return;
    final now = clock();
    if (!canUpdateRanking(lastRankingSubmitAt, now)) return;
    final result = await service.submitLeaderboard(db, save);
    if (!result.ok) return;
    _storeRankingSubmitAt(now);
    _board = await _readBoard(save);
    notifyListeners();
  }

  /// Opens the boards, posting this account's totals if the hour is up.
  Future<void> openLeaderboards(PlayerSave save) async {
    await refresh(save);
    await maybeAutoSubmitRanking(save);
  }

  /// Player-pressed ranking update, limited to once an hour.
  Future<void> updateRanking(PlayerSave save) {
    return run(() async {
      if (!isSignedIn) return 'Sign in to update your ranking.';
      final now = clock();
      final last = lastRankingSubmitAt;
      if (!canUpdateRanking(last, now)) {
        return rankingCooldownMessage(rankingCooldownRemainingMs(last!, now));
      }
      final result = await service.submitLeaderboard(db, save);
      if (!result.ok) return result.reason;
      _storeRankingSubmitAt(now);
      _board = await _readBoard(save);
      return rankingUpdatedNotice;
    });
  }

  Future<void> selectBoard(MultiplayerBoardKey key, PlayerSave save) async {
    _boardKey = key;
    _board = canSeeSocialPages ? await _readBoard(save) : const <LeaderboardEntry>[];
    notifyListeners();
  }

  /// The stored board with this account's live score folded in.
  ///
  /// The table is a snapshot, so without this the player's own row would only
  /// appear after the next submit landed.
  Future<List<LeaderboardEntry>> _readBoard(PlayerSave save) async {
    final stored = await service.leaderboard(_boardKey);
    final current = session;
    if (current == null || !isPlayableSave(save)) return stored;
    return mergeLiveLeaderboardScore(
      stored: stored,
      boardKey: _boardKey,
      db: db,
      save: save,
      userId: current.userId,
      username: isNotBlank(save.characterName) ? save.characterName! : current.username,
      appearance: save.appearance,
      guildName: _guild?.name,
    );
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
    if (!canSeeSocialPages) {
      _messages = const <ChatMessage>[];
      notifyListeners();
      return;
    }
    if (!isSignedIn && tab == ChatTab.dm) {
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
      guestGuildId: _guestGuildId,
    );
    _messages = channel == null ? const <ChatMessage>[] : await service.listChat(channel);
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
        guestGuildId: _guestGuildId,
      );
      if (channel == null) {
        return _chatTab == ChatTab.guest ? chatNoGuestNotice : chatNoGuildNotice;
      }
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
      final result = await service.sendChat(ChatChannel.dm(dmPairKey(me, userId)), body);
      return result.ok ? 'Message sent.' : result.reason;
    });
  }

  // --- Guilds ---------------------------------------------------------------

  /// Creates a guild and reports what it cost, so the caller can spend it.
  /// Founds a guild, answering with the reason it did not happen.
  ///
  /// The reason comes back rather than only landing in [notice], so the form
  /// that was refused can say so itself instead of closing and hoping the
  /// player finds the message it left behind.
  ///
  /// A guild that was written counts as founded even if the read after it
  /// failed: the guild is real, and the failed read has its own notice.
  Future<String?> createGuild(
    CreateGuildInput input,
    PlayerSave save,
    void Function(num goldCost) onPaid,
  ) async {
    if (_busy) return 'One thing at a time — the last request is still going.';
    var founded = false;
    await run(() async {
      final result = await service.createGuild(input, save.gold);
      if (!result.ok) return result.reason;
      onPaid(result.goldCost!);
      founded = true;
      await refresh(save);
      return 'Guild created.';
    });
    if (founded) return null;
    return _notice ?? 'The guild was not created. Try again.';
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

  Future<void> joinAsGuest(String guildId, String message, PlayerSave save) {
    return run(() async {
      final result = await service.joinAsGuest(guildId, message);
      if (!result.ok) return result.reason;
      final joined = result.joined ?? false;
      await refresh(save);
      return joined ? 'Joined as a guest.' : 'Guest request sent.';
    });
  }

  Future<void> leaveGuest(PlayerSave save) {
    return run(() async {
      final result = await service.leaveGuest();
      if (!result.ok) return result.reason;
      await refresh(save);
      return 'Left guest chat.';
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
    required bool guestAutoAccept,
    required String rankIconTheme,
    required GuildEmblem emblem,
    required Map<GuildRankKey, String> rankLabels,
    required PlayerSave save,
  }) {
    return run(() async {
      final guildId = _guildId;
      if (guildId == null) return 'Join a guild first.';
      final policy = await service.setGuildJoinPolicy(guildId, joinPolicy);
      if (!policy.ok) return policy.reason;
      final guests = await service.setGuildGuestAutoAccept(guildId, guestAutoAccept);
      if (!guests.ok) return guests.reason;
      final icons = await service.setGuildRankIconTheme(guildId, rankIconTheme);
      if (!icons.ok) return icons.reason;
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
    _bountyClaims = isSignedIn ? await service.bountyClaims(hourKey) : const <BountyClaimRecord>[];
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
