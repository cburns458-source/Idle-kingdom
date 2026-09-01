import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'tester_access.dart';

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
    this.cloudUnavailable = false,
  });

  /// The wall clock, for the read cursor a DM tab writes.
  final num Function() clock;

  final LoadedDatabase database;
  final MultiplayerService service;

  /// True when this build was given a hosted backend that could not be reached.
  final bool cloudUnavailable;

  /// Where the DM read cursors live, next to the save and the backend document.
  final SaveStorage storage;

  static const String chatFilterStorageKey = 'idle-kingdoms.client.filter-chat-profanity';

  static const String browseSocialStorageKey = 'idle-kingdoms.client.browse-social-unsigned';

  static const String hudGuildTagStorageKey = 'idle-kingdoms.client.hud-show-guild-tag';

  static const String hideChatBubbleStorageKey = 'idle-kingdoms.client.hide-chat-bubble';

  bool get filterChatProfanity => storage.getItem(chatFilterStorageKey) != '0';

  void setFilterChatProfanity(bool value) {
    storage.setItem(chatFilterStorageKey, value ? '1' : '0');
    notifyListeners();
  }

  /// When on, the HUD prefixes the character name with `[TAG]`.
  bool get showHudGuildTag => storage.getItem(hudGuildTagStorageKey) == '1';

  void setShowHudGuildTag(bool value) {
    storage.setItem(hudGuildTagStorageKey, value ? '1' : '0');
    notifyListeners();
  }

  /// When on, the corner chat button is hidden.
  bool get hideChatBubble => storage.getItem(hideChatBubbleStorageKey) == '1';

  void setHideChatBubble(bool value) {
    storage.setItem(hideChatBubbleStorageKey, value ? '1' : '0');
    notifyListeners();
  }

  String _nameColorDraftKey() {
    final userId = session?.userId;
    return userId == null ? nameColorStorageKey('signed-out') : nameColorStorageKey(userId);
  }

  /// Draft hex kept on this device until the next scheduled ranking submit.
  String get nameColorDraft => storage.getItem(_nameColorDraftKey()) ?? '';

  void setNameColorDraft(String raw) {
    storage.setItem(_nameColorDraftKey(), raw.trim());
    notifyListeners();
  }

  /// Published chat name color for [userId], or null when they have none.
  String? publishedNameColor(String userId) => _publishedNameColors[userId];

  /// When on, new lines on [tab] raise a bubble on the chat icon and tab.
  bool chatNotifyEnabled(ChatTab tab) => storage.getItem(chatNotifyStorageKey(tab)) != '0';

  void setChatNotifyEnabled(ChatTab tab, bool value) {
    storage.setItem(chatNotifyStorageKey(tab), value ? '1' : '0');
    if (!value) {
      _unread[tab] = 0;
      if (tab == ChatTab.local) _localUnread.clear();
    }
    notifyListeners();
  }

  Future<void> setPrivacyDirectMessages(String value) {
    return run(() async {
      _ownProfile = await service.setChatPrivacy(directMessages: value);
      return null;
    });
  }

  Future<void> setPrivacyLocalChat(String value) {
    return run(() async {
      _ownProfile = await service.setChatPrivacy(localChat: value);
      return null;
    });
  }

  Future<void> setPrivacyPublicGear(bool value) {
    return run(() async {
      _ownProfile = await service.setPrivacyPublicGear(value);
      return null;
    });
  }

  /// True when this device may see sign-in. An empty [testerPasskey] leaves
  /// the gate off.
  bool get hasTesterAccess => !testerPasskeyRequired(storage.getItem(testerAccessStorageKey));

  /// Accepts the shared tester key and remembers it on this device.
  bool unlockTesterAccess(String raw) {
    if (!matchesTesterPasskey(raw)) return false;
    storage.setItem(testerAccessStorageKey, testerPasskey);
    notifyListeners();
    return true;
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

  /// Presence cadence while battery saver is on.
  static const Duration batterySaverPresenceInterval = Duration(seconds: 45);

  /// Poll cadence while battery saver is on.
  static const Duration batterySaverPollInterval = Duration(seconds: 12);

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
  MultiplayerProfile? _ownProfile;
  List<ChatMessage> _messages = const <ChatMessage>[];
  List<BountyClaimRecord> _bountyClaims = const <BountyClaimRecord>[];
  List<BazaarPost> _bazaarPosts = const <BazaarPost>[];
  ChatTab _chatTab = ChatTab.global;
  String? _selectedDmPeerId;
  final List<String> _openDmPeerIds = <String>[];
  final Map<String, String> _dmPeerNames = <String, String>{};
  int _unreadDms = 0;
  final Map<ChatTab, int> _unread = <ChatTab, int>{};
  final Map<String, int> _localUnread = <String, int>{};
  final Map<String, String> _publishedNameColors = <String, String>{};
  bool _chatOpen = false;
  bool _citadelHub = false;
  String _chatLocationId = '';
  String? _notice;
  bool _busy = false;
  bool _suppressUploads = false;
  PlayerSave? _pendingAccountSave;
  Timer? _accountSaveTimer;
  Timer? _hourTimer;

  /// A named save this device still holds from before accounts owned the save.
  /// Used once if the account has no playable row yet, then forgotten.
  PlayerSave? pendingLeftover;

  /// Why the account row did not load on resume, when it was not simply empty.
  String? _cloudLoadProblem;

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
  String get privacyDirectMessages => _ownProfile?.privacyDirectMessages ?? chatPrivacyPublic;
  String get privacyLocalChat => _ownProfile?.privacyLocalChat ?? chatPrivacyPublic;
  bool get privacyPublicGear => _ownProfile?.privacyPublicGear ?? true;
  List<ChatMessage> get messages => _messages;

  /// Who claimed each of this hour's bounties first, as far as the last read saw.
  List<BountyClaimRecord> get bountyClaims => _bountyClaims;
  List<BazaarPost> get bazaarPosts => _bazaarPosts;
  ChatTab get chatTab => _chatTab;
  int get unreadDms => _unreadDms;

  /// Unread lines waiting on one tab, after notification toggles.
  ///
  /// Local is the room for the location the player is in. A new empty place
  /// does not inherit a bubble from the last one.
  int unreadFor(ChatTab tab) {
    if (tab == ChatTab.local) {
      if (!chatNotifyEnabled(tab)) return 0;
      final key = _currentLocalChannelKey();
      if (key != null) return _localUnread[key] ?? 0;
    }
    return _unread[tab] ?? (tab == ChatTab.dm ? _unreadDms : 0);
  }

  /// Sum of enabled-channel bubbles for the corner chat icon.
  int get unreadTotal => chatTabOrder.fold<int>(0, (sum, tab) => sum + unreadFor(tab));

  Map<ChatTab, num> get unreadByTab => <ChatTab, num>{
    for (final tab in chatTabOrder) tab: unreadFor(tab),
  };
  String? get selectedDmPeerId => _selectedDmPeerId;

  /// Open private threads, newest first, including ones started from a profile.
  List<({String userId, String username})> get openDmThreads {
    final seen = <String>{};
    final out = <({String userId, String username})>[];
    void add(String id, [String? name]) {
      if (id.isEmpty || !seen.add(id)) return;
      out.add((userId: id, username: _dmPeerNames[id] ?? name ?? 'Adventurer'));
    }

    for (final id in _openDmPeerIds) {
      add(id);
    }
    final me = session?.userId;
    if (me != null) {
      for (final message in _messages) {
        final peer = _dmPeerIdFromMessage(message, me);
        if (peer == null) continue;
        if (message.userId != me) _dmPeerNames[peer] = message.username;
        add(peer, message.userId == me ? null : message.username);
      }
    }
    return out;
  }

  List<ChatMessage> messagesForSelectedDm() {
    final me = session?.userId;
    final peer = _selectedDmPeerId;
    if (me == null || peer == null) return const <ChatMessage>[];
    final key = chatChannelKey(ChatChannel.dm(dmPairKey(me, peer)));
    return _messages.where((message) => message.channelKey == key).toList();
  }

  /// What the last action said, success or refusal, until something else speaks.
  String? get notice => _notice;

  /// True while a call is in flight, so buttons can stop taking presses.
  bool get busy => _busy;

  /// Set when a signed-in resume could not load the account save.
  String? get accountLoadProblem => _cloudLoadProblem;

  /// True when creating a fresh character would ignore a cloud row that failed to load.
  bool get mustRestoreCloudSaveBeforeCreate => isSignedIn && _cloudLoadProblem != null;

  @override
  void dispose() {
    _alive = false;
    _accountSaveTimer?.cancel();
    stopPolling();
    super.dispose();
  }

  bool _alive = true;

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
    required void Function(PlayerSave save, {num? nowMs}) adopt,
  }) {
    return run(() async {
      final result = await service.signUp(email, username, password);
      if (!result.ok) return result.reason;
      await service.claimPlaySession();
      final playable = await _adoptAccountSave(localHint, adopt);
      if (playable == null && _cloudLoadProblem != null) {
        _notice = _cloudLoadProblem;
      }
      String? claimReason;
      final leftoverName = playable?.characterName?.trim() ?? '';
      if (leftoverName.isNotEmpty) {
        final claimed = await service.claimAccountUsername(leftoverName);
        if (!claimed.ok) claimReason = claimed.reason;
      }
      await refresh(playable ?? localHint);
      if (playable != null) await publishRanking(playable);
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
    required void Function(PlayerSave save, {num? nowMs}) adopt,
  }) {
    return run(() async {
      final result = await service.signIn(email, password);
      if (!result.ok) return result.reason;
      await service.claimPlaySession();
      final playable = await _adoptAccountSave(localHint, adopt);
      if (playable == null && _cloudLoadProblem != null) {
        _notice = _cloudLoadProblem;
      }
      await refresh(playable ?? localHint);
      if (playable != null) await publishRanking(playable);
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
    required void Function(PlayerSave save, {num? nowMs}) adopt,
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
      if (playable == null && _cloudLoadProblem != null) {
        _notice = _cloudLoadProblem;
      }
      await refresh(playable ?? localHint);
      if (playable != null) await publishRanking(playable);
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
    _ownProfile = null;
    _messages = const <ChatMessage>[];
    _selectedDmPeerId = null;
    _openDmPeerIds.clear();
    _dmPeerNames.clear();
    _bountyClaims = const <BountyClaimRecord>[];
    _bazaarPosts = const <BazaarPost>[];
    _unreadDms = 0;
    _unread.clear();
    _localUnread.clear();
    _publishedNameColors.clear();
    _chatOpen = false;
  }

  // --- Account saves --------------------------------------------------------

  static bool hasNamedCharacter(PlayerSave? save) {
    if (save == null) return false;
    return save.characterName?.trim().isNotEmpty ?? false;
  }

  static bool isPlayableSave(PlayerSave? save) {
    if (save == null) return false;
    return hasNamedCharacter(save) && save.raceId != null;
  }

  PlayerSave? _bestLeftover(PlayerSave localHint) {
    if (isPlayableSave(pendingLeftover)) return pendingLeftover;
    if (hasNamedCharacter(pendingLeftover)) return pendingLeftover;
    if (isPlayableSave(localHint)) return localHint;
    if (hasNamedCharacter(localHint)) return localHint;
    return null;
  }

  /// Loads the account row, or promotes a leftover named save onto the account.
  Future<PlayerSave?> _adoptAccountSave(
    PlayerSave localHint,
    void Function(PlayerSave save, {num? nowMs}) adopt,
  ) async {
    _cloudLoadProblem = null;
    final nowMs = await service.authoritativeNowMs();
    final pulled = await service.pullSave();
    if (pulled.ok && hasNamedCharacter(pulled.save)) {
      adopt(pulled.save!, nowMs: nowMs);
      pendingLeftover = null;
      onAccountSaveReady?.call();
      return pulled.save;
    }
    if (!pulled.ok &&
        pulled.reason != null &&
        pulled.reason != 'No cloud save for this account yet.') {
      _cloudLoadProblem = pulled.reason;
    }
    final leftover = _bestLeftover(localHint);
    if (leftover != null) {
      if (!identical(leftover, localHint)) adopt(leftover, nowMs: nowMs);
      if (isPlayableSave(leftover)) {
        await service.pushSave(db, leftover, force: true);
      }
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
  }

  /// Publishes a just-created character immediately.
  Future<void> publishAccountSave(PlayerSave save) async {
    if (!isPlayableSave(save)) return;
    final cloud = await service.pullSave();
    if (cloud.ok && hasNamedCharacter(cloud.save)) {
      final existing = cloud.save!;
      if (existing.gold > save.gold + 10 ||
          (existing.raceId != null && existing.raceId != save.raceId)) {
        _notice = 'This account already has a saved character. Reload the page to restore it.';
        notifyListeners();
        return;
      }
    }
    await flushAccountSave(save);
    await publishRanking(save);
  }

  void _clearAccountLocally() {
    _suppressUploads = true;
    _accountSaveTimer?.cancel();
    _accountSaveTimer = null;
    _pendingAccountSave = null;
    pendingLeftover = null;
    _cloudLoadProblem = null;
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
    await _refreshUnread(save);
    await _loadSocialLists();
    notifyListeners();
  }

  /// Starts the timers that keep presence alive and the counts current.
  ///
  /// [saveOf] is read on every tick rather than captured, because the player
  /// moves and changes clothes while the timers run.
  void startPolling(PlayerSave Function() saveOf, {bool batterySaver = false}) {
    _presenceTimer?.cancel();
    _pollTimer?.cancel();
    final presence = batterySaver ? batterySaverPresenceInterval : presenceInterval;
    final poll = batterySaver ? batterySaverPollInterval : pollInterval;
    _presenceTimer = Timer.periodic(presence, (_) => publishPresence(saveOf()));
    _pollTimer = Timer.periodic(poll, (_) => _poll(saveOf()));
    _scheduleHourlyPublish(saveOf);
    publishPresence(saveOf());
  }

  /// Stops both timers, for whoever started them going off screen.
  void stopPolling() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _hourTimer?.cancel();
    _hourTimer = null;
  }

  void _scheduleHourlyPublish(PlayerSave Function() saveOf) {
    _hourTimer?.cancel();
    final wait = msUntilNextUtcHour(clock()).round();
    _hourTimer = Timer(Duration(milliseconds: wait < 500 ? 500 : wait), () {
      unawaited(_onUtcHour(saveOf));
    });
  }

  Future<void> _onUtcHour(PlayerSave Function() saveOf) async {
    if (!isSignedIn) return;
    await publishForUtcHour(saveOf());
    _scheduleHourlyPublish(saveOf);
  }

  Future<void> _poll(PlayerSave save) async {
    if (!isSignedIn) return;
    if (await _wasKicked()) return;
    await _refreshUnread(save);
    if (_chatTab == ChatTab.dm) {
      _messages = await service.listDirectMessages();
      _ingestDmPeers(_messages);
      if (_selectedDmPeerId == null && _openDmPeerIds.isNotEmpty) {
        _selectedDmPeerId = _openDmPeerIds.first;
      }
    }
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

  Future<PublicPlayerProfile?> publicProfile(String userId, {GameDatabase? db}) =>
      service.publicProfile(userId, db: db);

  bool isFriend(String userId) => _friends.any((row) => row.userId == userId);

  /// A friend or a member of the player's own guild.
  bool isAlliedUser(String userId) =>
      isFriend(userId) || _members.any((member) => member.userId == userId);

  /// True when someone standing here is a friend or guildmate.
  bool get nearbyHasAllies => _peers.any((peer) => isAlliedUser(peer.userId));

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
    final me = session?.userId;
    _ownProfile = me == null ? null : await service.profile(me);
    final ownColor = normalizeNameColorHex(_ownProfile?.nameColor);
    if (me != null && ownColor != null) {
      _publishedNameColors[me] = ownColor;
      // A new device has no draft. Seed from the published color so the next
      // scheduled submit does not wipe what this account already shows in chat.
      if (storage.getItem(_nameColorDraftKey()) == null) {
        storage.setItem(_nameColorDraftKey(), ownColor);
      }
    }
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

  void _storeRankingSubmitAt(num nowMs) {
    final userId = session?.userId;
    if (userId == null) return;
    storage.setItem(rankingUpdateStorageKey(userId), nowMs.toString());
  }

  /// Publishes the live save to the boards and public gear.
  ///
  /// Login, opening the app, and each UTC hour call this. A second call in the
  /// same couple of seconds is ignored so sign-in and restore do not double-fire.
  Future<void> publishRanking(PlayerSave save, {bool ignoreDebounce = false}) async {
    if (!isSignedIn || !isPlayableSave(save)) return;
    final now = clock();
    if (!ignoreDebounce && !shouldPublishOnOpen(lastRankingSubmitAt, now)) return;
    final result = await service.submitLeaderboard(
      db,
      save,
      nameColor: normalizeNameColorHex(nameColorDraft),
      publishNameColor: true,
    );
    if (!result.ok) return;
    final userId = session?.userId;
    final published = normalizeNameColorHex(nameColorDraft);
    if (userId != null) {
      if (published != null) {
        _publishedNameColors[userId] = published;
      } else {
        _publishedNameColors.remove(userId);
      }
      _ownProfile = _ownProfile?.copyWith(nameColor: published, clearNameColor: published == null);
    }
    _storeRankingSubmitAt(now);
    _board = await _readBoard(save);
    notifyListeners();
  }

  /// Publishes when the UTC hour has rolled over since the last publish.
  Future<void> publishForUtcHour(PlayerSave save) async {
    if (!shouldPublishForUtcHour(lastRankingSubmitAt, clock())) return;
    await publishRanking(save, ignoreDebounce: true);
  }

  /// Called when the app or tab comes back: refresh the session, then publish.
  Future<void> onForeground(PlayerSave save) async {
    if (!isSignedIn) return;
    final refused = await service.refreshSession();
    if (refused != null) {
      _notice = refused;
      notifyListeners();
      return;
    }
    await publishRanking(save);
  }

  /// Opens the boards. Publish already happened on login or opening the app.
  Future<void> openLeaderboards(PlayerSave save) async {
    await refresh(save);
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
      raceId: save.raceId,
      guildName: _guild?.name,
      guildTag: _guild?.tag,
    );
  }

  // --- Chat -----------------------------------------------------------------

  /// Keeps unread polling pointed at the open drawer and the room the player is in.
  void syncChatSurface({required bool open, required String locationId, required bool citadelHub}) {
    _chatOpen = open;
    _chatLocationId = locationId;
    _citadelHub = citadelHub;
  }

  Future<void> _refreshUnread(PlayerSave save) async {
    if (!isSignedIn) {
      _unreadDms = 0;
      _unread.clear();
      _localUnread.clear();
      return;
    }
    final locationId = _chatLocationId.isEmpty ? save.currentLocationId : _chatLocationId;
    for (final tab in chatTabOrder) {
      final count = await _unreadCountFor(tab, locationId);
      _unread[tab] = count;
      if (tab == ChatTab.local) {
        final key = _localChannelKey(locationId);
        if (key != null) _localUnread[key] = count;
      }
    }
    _unreadDms = _unread[ChatTab.dm] ?? 0;
  }

  Future<int> _unreadCountFor(ChatTab tab, String locationId) async {
    if (!chatNotifyEnabled(tab)) return 0;
    if (_chatOpen && _chatTab == tab) {
      _markTabRead(tab, locationId);
      return 0;
    }
    if (tab == ChatTab.dm) {
      return service.countUnreadDirectMessages(_dmCursor());
    }
    final channel = chatChannelForTab(
      tab,
      locationId: locationId,
      citadelHub: _citadelHub,
      guildId: _guildId,
      guestGuildId: _guestGuildId,
    );
    if (channel == null) return 0;
    final cursor = _channelCursor(channel);
    if (cursor == null) {
      _storeChannelCursor(channel);
      return 0;
    }
    return service.countUnreadChat(channel, cursor);
  }

  void _markTabRead(ChatTab tab, String locationId) {
    if (tab == ChatTab.dm) {
      _markDmsRead();
      _unread[ChatTab.dm] = 0;
      return;
    }
    final channel = chatChannelForTab(
      tab,
      locationId: locationId,
      citadelHub: _citadelHub,
      guildId: _guildId,
      guestGuildId: _guestGuildId,
    );
    if (channel == null) return;
    _storeChannelCursor(channel);
    _unread[tab] = 0;
    if (tab == ChatTab.local) _localUnread[chatChannelKey(channel)] = 0;
  }

  String? _localChannelKey(String locationId) {
    final channel = chatChannelForTab(
      ChatTab.local,
      locationId: locationId,
      citadelHub: _citadelHub,
      guildId: null,
    );
    return channel == null ? null : chatChannelKey(channel);
  }

  String? _currentLocalChannelKey() =>
      _chatLocationId.isEmpty ? null : _localChannelKey(_chatLocationId);

  String? _channelCursor(ChatChannel channel) {
    final userId = session?.userId;
    if (userId == null) return null;
    return storage.getItem(chatReadCursorKey(userId, chatChannelKey(channel)));
  }

  void _storeChannelCursor(ChatChannel channel) {
    final userId = session?.userId;
    if (userId == null) return;
    storage.setItem(chatReadCursorKey(userId, chatChannelKey(channel)), isoFromMs(clock()));
  }

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

  Future<void> _ingestNameColors(Iterable<ChatMessage> messages) async {
    final missing = messages
        .map((message) => message.userId)
        .where((userId) => userId.isNotEmpty && !_publishedNameColors.containsKey(userId))
        .toSet();
    if (missing.isEmpty) return;
    final found = await service.publishedNameColors(missing);
    for (final userId in missing) {
      final color = found[userId];
      if (color != null) _publishedNameColors[userId] = color;
    }
  }

  /// Loads name colors after lines are already shown.
  Future<void> _ingestNameColorsLater(Iterable<ChatMessage> messages) async {
    final before = Map<String, String>.of(_publishedNameColors);
    await _ingestNameColors(messages);
    if (_alive && !_mapEquals(before, _publishedNameColors)) {
      notifyListeners();
    }
  }

  bool _mapEquals(Map<String, String> a, Map<String, String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  /// Opens a chat tab and loads what it holds.
  ///
  /// Lines notify as soon as the list returns; name colors fill in afterward so
  /// opening chat is not blocked on one profile fetch per author.
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
      _ingestDmPeers(_messages);
      if (_selectedDmPeerId == null && _openDmPeerIds.isNotEmpty) {
        _selectedDmPeerId = _openDmPeerIds.first;
      }
      _markTabRead(ChatTab.dm, locationId);
      notifyListeners();
      unawaited(_ingestNameColorsLater(_messages));
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
    _markTabRead(tab, locationId);
    notifyListeners();
    unawaited(_ingestNameColorsLater(_messages));
  }

  /// Posts skill milestone lines to guild chat when thresholds are crossed.
  Future<void> announceGuildSkillMilestones(
    PlayerSave before,
    PlayerSave after,
    GameDatabase db,
  ) async {
    final guild = _guild;
    final guildId = _guildId;
    if (!isSignedIn || guild == null || guildId == null) return;
    final settings = guild.skillMilestoneSettings;
    if (!settings.enabled) return;
    final milestones = guildSkillMilestonesBetweenSaves(
      beforeSkills: [
        for (final skill in before.skills)
          (skillId: skill.skillId, level: skill.level, xp: skill.xp),
      ],
      afterSkills: [
        for (final skill in after.skills)
          (skillId: skill.skillId, level: skill.level, xp: skill.xp),
      ],
      skillName: (skillId) {
        for (final skill in db.skills) {
          if (skill.skillId == skillId) return skill.displayName;
        }
        return skillId;
      },
      settings: settings,
    );
    if (milestones.isEmpty) return;
    final characterName = after.characterName?.trim();
    final name = (characterName != null && characterName.isNotEmpty)
        ? characterName
        : (session?.username ?? 'Adventurer');
    final body = milestones.map((row) => formatGuildSkillMilestone(name, row)).join('\n');
    final result = await service.sendChat(ChatChannel.guild(guildId), body);
    if (!result.ok) return;
    if (_chatTab == ChatTab.guild) {
      _messages = await service.listChat(ChatChannel.guild(guildId));
      notifyListeners();
      unawaited(_ingestNameColorsLater(_messages));
    }
  }

  /// Sends [body] to the open tab, then shows the room again.
  Future<void> sendChat(String body, String locationId, {bool citadelHub = false}) {
    if (_chatTab == ChatTab.dm) {
      final peer = _selectedDmPeerId;
      if (peer == null) {
        return run(() async => 'Pick a conversation.');
      }
      return sendDirectMessage(peer, body, announceSent: false);
    }
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
      unawaited(_ingestNameColorsLater(_messages));
      return null;
    });
  }

  void rememberDmPeer(String userId, String username) {
    if (userId.isEmpty) return;
    if (username.isNotEmpty) _dmPeerNames[userId] = username;
    _openDmPeerIds.remove(userId);
    _openDmPeerIds.insert(0, userId);
    notifyListeners();
  }

  void selectDmPeer(String userId, {String? username}) {
    _selectedDmPeerId = userId;
    rememberDmPeer(userId, username ?? _dmPeerNames[userId] ?? 'Adventurer');
  }

  String? _dmPeerIdFromMessage(ChatMessage message, String me) {
    if (!message.channelKey.startsWith('dm:')) {
      return message.userId == me ? null : message.userId;
    }
    final parts = message.channelKey.substring(3).split(':');
    if (parts.length < 2) return message.userId == me ? null : message.userId;
    if (parts[0] == me) return parts[1];
    if (parts[1] == me) return parts[0];
    return message.userId == me ? null : message.userId;
  }

  void _ingestDmPeers(List<ChatMessage> messages) {
    final me = session?.userId;
    if (me == null) return;
    for (final message in messages) {
      final peer = _dmPeerIdFromMessage(message, me);
      if (peer == null) continue;
      if (message.userId != me) _dmPeerNames[peer] = message.username;
      if (!_openDmPeerIds.contains(peer)) _openDmPeerIds.add(peer);
    }
  }

  /// Answers a peer where they can read it, without leaving the panel.
  Future<void> sendDirectMessage(
    String userId,
    String body, {
    String? username,
    bool announceSent = true,
  }) {
    return run(() async {
      final me = session?.userId;
      if (me == null) return 'Sign in to chat.';
      final result = await service.sendChat(ChatChannel.dm(dmPairKey(me, userId)), body);
      if (!result.ok) return result.reason;
      _chatTab = ChatTab.dm;
      selectDmPeer(userId, username: username ?? _dmPeerNames[userId] ?? 'Adventurer');
      _messages = await service.listDirectMessages();
      if (_messages.isEmpty) {
        final sent = result.message;
        if (sent != null) _messages = <ChatMessage>[sent];
      }
      _ingestDmPeers(_messages);
      _markDmsRead();
      return announceSent ? 'Message sent.' : null;
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
    // Refusal stays on the create sheet; do not also fire the global alert.
    final reason = _notice ?? 'The guild was not created. Try again.';
    _notice = null;
    return reason;
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

  Future<void> removeMember(String userId, PlayerSave save) {
    return run(() async {
      final guildId = _guildId;
      if (guildId == null) return 'Join a guild first.';
      final result = await service.removeGuildMember(guildId, userId);
      if (!result.ok) return result.reason;
      await refresh(save);
      return 'Removed from the guild.';
    });
  }

  Future<void> removeGuest(String userId, PlayerSave save) {
    return run(() async {
      final guildId = _guildId;
      if (guildId == null) return 'Join a guild first.';
      final result = await service.removeGuildGuest(guildId, userId);
      if (!result.ok) return result.reason;
      await refresh(save);
      return 'Removed guest.';
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

  /// Saves the guild settings sheet fields, stopping at the first no.
  Future<void> saveGuildSettings({
    required GuildJoinPolicy joinPolicy,
    required bool guestAutoAccept,
    required String rankIconTheme,
    required GuildEmblem emblem,
    required Map<GuildRankKey, String> rankLabels,
    required GuildSkillMilestoneSettings skillMilestoneSettings,
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
      final milestones = await service.setGuildSkillMilestoneSettings(
        guildId,
        skillMilestoneSettings,
      );
      if (!milestones.ok) return milestones.reason;
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
