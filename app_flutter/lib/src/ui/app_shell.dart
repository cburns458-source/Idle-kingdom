import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/account_save_unload.dart';
import '../session/battery_saver_pref.dart';
import '../session/game_controller.dart';
import '../session/map_walk.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'auth_gate_sheet.dart';
import 'away_summary_sheet.dart';
import 'bottom_nav.dart';
import 'chat_sheet.dart';
import 'critter_overlay.dart';
import 'character_view.dart';
import 'location_view.dart';
import 'log_view.dart';
import 'menu_view.dart';
import 'npc_panel.dart';
import 'new_character_sheet.dart';
import 'skill_level_up_popup.dart';
import 'overlay_notice.dart';
import 'returning_overlay.dart';
import 'playable_frame.dart';
import 'social_alert.dart';
import 'social_view.dart';
import 'top_hud.dart';
import 'travel_overlay.dart';
import 'wardrobe_sheet.dart';
import 'world_map_view.dart';

enum GameScreen { location, map, character, log, leaderboards, guilds, account, menu }

/// Sits on the chin. Kept low on the location screen so it does not cover
/// Expand list or the activity buttons.
const double chatLauncherBottom = 62;

/// On the map, sits above the Travel strip.
const double chatLauncherBottomOnMap = 192;

const Set<GameScreen> _chinScreens = {
  GameScreen.character,
  GameScreen.log,
  GameScreen.leaderboards,
  GameScreen.guilds,
  GameScreen.account,
  GameScreen.menu,
};

enum _PageMotion { slideUp, slideDown, expandFromChip }

/// The frame the whole game lives in: HUD on top, screen in the middle, nav
/// underneath, and the overlays that can cover all three.
///
/// Portrait-first and capped in width, so a desktop browser shows the same
/// layout a phone does rather than stretching it.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller, required this.multiplayer});

  final GameController controller;

  /// The optional half: accounts, guilds, chat, and who else is around.
  final MultiplayerController multiplayer;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with TickerProviderStateMixin, WidgetsBindingObserver {
  /// Drives the game loop. Coming from the widget means it stops when the app is
  /// backgrounded. A long hide is batch-resolved under the return overlay; a
  /// short lock stays on the live tick. Battery saver swaps this for [_saverTick].
  Ticker? _ticker;

  /// Slower play loop while battery saver is on (~5Hz instead of vsync).
  Timer? _saverTick;

  static const Duration _saverTickPeriod = Duration(milliseconds: 200);

  final List<GameScreen> _stack = [GameScreen.location];
  late String _browseMapId = _mapIdForCurrentLocation();
  String? _selectedLocationId;
  bool _wardrobeOpen = false;
  bool _chatOpen = false;
  bool _socialAlertQueued = false;
  String? _socialAlertMessage;
  OverlayEntry? _socialAlertEntry;

  GameScreen get _screen => _stack.last;
  final GlobalKey _toastKey = GlobalKey();
  AnimationController? _mapWalk;
  String? _walkFromId;
  String? _walkToId;
  bool _returnHoldArmed = false;
  Timer? _returnHold;
  bool _questRewardQueued = false;

  GameController get controller => widget.controller;
  MultiplayerController get multiplayer => widget.multiplayer;

  bool get _needsAuth => !multiplayer.isSignedIn;

  bool get _needsCharacter {
    final save = controller.save;
    return save.characterName == null || save.raceId == null;
  }

  /// The game loop and HUD only run once the player is signed in and named.
  bool get _canPlay => !_needsAuth && !_needsCharacter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    listenForPageUnload(() {
      if (!mounted) return;
      multiplayer.flushAccountSave(controller.save);
    });
    multiplayer.onAccountCleared ??= controller.resetUnsigned;
    multiplayer.addListener(_onMultiplayerChanged);
    controller.onSaveCommitted = (before, after) {
      unawaited(multiplayer.announceGuildSkillMilestones(before, after, controller.db));
    };
    controller.addListener(_armReturningHold);
    controller.addListener(_flushPendingDialogs);
    controller.addListener(_syncPlayLoop);
    _armReturningHold();
    _ticker = createTicker((_) {
      if (!mounted || !_canPlay) return;
      controller.tick();
    });
    _syncPlayLoop();
    _maybePresentSocialNotice();
  }

  void _onMultiplayerChanged() {
    if (!mounted) return;
    _syncPlayLoop();
    setState(() {});
    _maybePresentSocialNotice();
  }

  /// Turns the shared multiplayer notice into a one-shot alert, then clears it.
  ///
  /// Social panels used to paint the same sticky string; a popup keeps the
  /// result on the action that caused it without leaking across every screen.
  void _maybePresentSocialNotice() {
    final text = multiplayer.notice;
    if (text == null || text.isEmpty || _socialAlertQueued || _socialAlertMessage != null) {
      return;
    }
    _socialAlertQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _socialAlertQueued = false;
        return;
      }
      // Re-read: callers like createGuild may clear a notice meant only for a form.
      final message = multiplayer.notice;
      if (message == null || message.isEmpty) {
        _socialAlertQueued = false;
        return;
      }
      _socialAlertQueued = false;
      _presentRootSocialAlert(message);
    });
  }

  void _presentRootSocialAlert(String message) {
    _removeRootSocialAlert();
    _socialAlertMessage = message;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      setState(() {});
      return;
    }
    _socialAlertEntry = OverlayEntry(
      builder: (context) => SocialAlertOverlay(message: message, onClose: _dismissSocialAlert),
    );
    overlay.insert(_socialAlertEntry!);
    setState(() {});
  }

  void _removeRootSocialAlert() {
    _socialAlertEntry?.remove();
    _socialAlertEntry = null;
  }

  void _dismissSocialAlert() {
    final message = _socialAlertMessage;
    _removeRootSocialAlert();
    setState(() => _socialAlertMessage = null);
    if (message != null && multiplayer.notice == message) multiplayer.announce(null);
    _maybePresentSocialNotice();
  }

  void _flushPendingDialogs() {
    if (_questRewardQueued) return;
    final pending = controller.takePendingQuestCompletions();
    final levelUps = controller.takePendingSkillLevelUps();
    if (pending.isEmpty && levelUps.isEmpty) return;
    _questRewardQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted) return;
        for (final completion in pending) {
          final quest = getQuest(controller.db, completion.questId);
          final npcId = quest?['NPC ID'];
          final spoken = npcId is String
              ? questTalkLine(controller.db, completion.questId, npcId, controller.save)
              : null;
          await showQuestRewards(
            context,
            questName: completion.questName,
            rewards: completion.rewards,
            spokenLine: spoken,
          );
          if (!mounted) return;
          if (completion.pendingSkillXp > 0) {
            await showSkillXpPicker(
              context,
              controller: controller,
              amount: completion.pendingSkillXp,
            );
          }
          if (!mounted) return;
        }
        for (final notice in levelUps) {
          await showSkillLevelUp(context, notice);
          if (!mounted) return;
        }
      } finally {
        _questRewardQueued = false;
        if (mounted) _flushPendingDialogs();
      }
    });
  }

  void _armReturningHold() {
    if (!controller.returningFromAway) {
      _returnHold?.cancel();
      _returnHold = null;
      _returnHoldArmed = false;
      return;
    }
    if (_returnHoldArmed) return;
    _returnHoldArmed = true;
    _returnHold?.cancel();
    _returnHold = Timer(const Duration(milliseconds: GameController.returningHoldMs), () {
      if (!mounted) return;
      controller.finishReturningFromAway();
    });
  }

  bool _polling = false;
  bool _saverPolling = false;

  /// Presence and the game clock stay off until the player is signed in and named.
  void _syncPlayLoop() {
    final saver = controller.batterySaver;
    if (_canPlay) {
      if (saver) {
        _ticker?.stop();
        _saverTick ??= Timer.periodic(_saverTickPeriod, (_) {
          if (!mounted || !_canPlay) return;
          controller.tick();
        });
      } else {
        _saverTick?.cancel();
        _saverTick = null;
        if (!(_ticker?.isActive ?? false)) _ticker?.start();
      }
    } else {
      _ticker?.stop();
      _saverTick?.cancel();
      _saverTick = null;
    }
    final shouldPoll = multiplayer.isSignedIn;
    if (shouldPoll && (!_polling || _saverPolling != saver)) {
      _polling = true;
      _saverPolling = saver;
      multiplayer.startPolling(() => controller.save, batterySaver: saver);
    } else if (!shouldPoll && _polling) {
      _polling = false;
      multiplayer.stopPolling();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      multiplayer.flushAccountSave(controller.save);
    }
    // Leave the ticker running through [inactive] (control center, a banner).
    // [paused] / [hidden] stop it so the next resume is one catch-up tick.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _ticker?.stop();
      _saverTick?.cancel();
      _saverTick = null;
    }
    if (state == AppLifecycleState.resumed) {
      _syncPlayLoop();
      unawaited(multiplayer.onForeground(controller.save));
    }
  }

  @override
  void dispose() {
    _returnHold?.cancel();
    _returnHold = null;
    WidgetsBinding.instance.removeObserver(this);
    multiplayer.flushAccountSave(controller.save);
    multiplayer.removeListener(_onMultiplayerChanged);
    controller.removeListener(_armReturningHold);
    controller.removeListener(_flushPendingDialogs);
    controller.removeListener(_syncPlayLoop);
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    _saverTick?.cancel();
    _saverTick = null;
    _mapWalk?.dispose();
    _removeRootSocialAlert();
    multiplayer.stopPolling();
    super.dispose();
  }

  void _cancelMapWalk() {
    _mapWalk?.dispose();
    _mapWalk = null;
    _walkFromId = null;
    _walkToId = null;
  }

  /// Whether Local chat should use the shared Citadel room.
  ///
  /// Every district of the Citadel sub-map is one room, so the test is the map
  /// the location belongs to rather than the location itself.
  bool get _inCitadel {
    final location = controller.location;
    if (location == null) return false;
    return resolveActiveMapId(controller.db, location) == citadelMapId;
  }

  /// The map this location actually sits on: a district when inside a sub-map,
  /// otherwise the world map. Gateways stay on the world map.
  String _mapIdForCurrentLocation() {
    final location = widget.controller.location;
    if (location == null) return mainMapId;
    return getLocationMapId(location);
  }

  void _showMap() {
    _cancelMapWalk();
    setState(() {
      _browseMapId = mainMapId;
      _selectedLocationId = controller.save.currentLocationId;
      _wardrobeOpen = false;
      if (_stack.last != GameScreen.map) _stack.add(GameScreen.map);
    });
  }

  /// Opens a district map: from a gateway, or back from a location on that map.
  void _browseSubMap(String mapId) {
    _cancelMapWalk();
    setState(() {
      _browseMapId = mapId;
      _selectedLocationId = controller.save.currentLocationId;
      _wardrobeOpen = false;
      if (_stack.last != GameScreen.map) _stack.add(GameScreen.map);
    });
  }

  void _popToLocation() {
    _cancelMapWalk();
    setState(() {
      _wardrobeOpen = false;
      _stack
        ..clear()
        ..add(GameScreen.location);
    });
  }

  /// Close pops one page. Wardrobe is a HUD overlay, so it goes first.
  void _popPage() {
    if (_wardrobeOpen) {
      setState(() => _wardrobeOpen = false);
      return;
    }
    if (_stack.length <= 1) return;
    setState(() {
      final popped = _stack.removeLast();
      if (popped == GameScreen.map) _cancelMapWalk();
    });
  }

  void _closeChat() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_chatOpen) return;
    setState(() => _chatOpen = false);
  }

  void _selectScreen(GameScreen screen) {
    if (screen == GameScreen.account) screen = GameScreen.menu;
    if (screen == GameScreen.location) {
      _popToLocation();
      return;
    }
    setState(() {
      _wardrobeOpen = false;
      if (_screen == GameScreen.map && screen != GameScreen.map) {
        _cancelMapWalk();
      }
      if (_chinScreens.contains(_screen) && _chinScreens.contains(screen)) {
        _stack[_stack.length - 1] = screen;
      } else if (_stack.last != screen) {
        _stack.add(screen);
      }
    });
  }

  void _browseMap(String mapId) {
    _cancelMapWalk();
    setState(() {
      _browseMapId = mapId;
      _selectedLocationId = null;
    });
  }

  /// After a gateway click, [planTravel] lands on the child-map node. Open that
  /// submap instead of the landing node's location page.
  String? _subMapOpenedByArrival(String requestedId) {
    final dest = controller.indexes.locationsById[requestedId];
    if (dest == null || !isSubMapGateway(dest)) return null;
    if (controller.save.currentLocationId == requestedId) return null;
    return subMapIdForGateway(controller.db, requestedId);
  }

  void _arrive(String locationId) {
    _cancelMapWalk();
    if (!controller.travelTo(locationId, _browseMapId)) return;
    final subMapId = _subMapOpenedByArrival(locationId);
    setState(() {
      _wardrobeOpen = false;
      if (subMapId != null) {
        _browseMapId = subMapId;
        _selectedLocationId = controller.save.currentLocationId;
        _stack
          ..clear()
          ..add(GameScreen.location)
          ..add(GameScreen.map);
      } else {
        _browseMapId = _mapIdForCurrentLocation();
        _selectedLocationId = null;
        _stack
          ..clear()
          ..add(GameScreen.location);
      }
    });
  }

  /// Exit: tapping this submap's gateway while browsing it opens the world map.
  /// Entry travels; [planTravel] lands on the gateway's child-map node.
  bool _openMapPortal(String locationId) {
    final dest = controller.indexes.locationsById[locationId];
    if (dest == null || !isSubMapGateway(dest)) return false;
    if (_browseMapId != mainMapId &&
        subMapIdForGateway(controller.db, locationId) == _browseMapId) {
      _cancelMapWalk();
      setState(() {
        _browseMapId = mainMapId;
        _selectedLocationId = locationId;
      });
      return true;
    }
    return false;
  }

  void _enterGateway(String locationId) {
    _arrive(locationId);
  }

  void _travelTo(String locationId) {
    if (controller.isRecovering) return;
    if (_openMapPortal(locationId)) return;
    if (locationId == controller.save.currentLocationId) {
      _arrive(locationId);
      return;
    }
    final depthsBlock = depthsTravelBlockReason(locationId, controller.save);
    if (depthsBlock != null) {
      controller.announce(depthsBlock);
      return;
    }
    if (!canTravelTo(
      controller.db,
      controller.save.currentLocationId,
      locationId,
      _browseMapId,
      controller.save.unlockedLocationIds,
      controller.save,
    )) {
      return;
    }
    if (!controller.mapTravelAnimation || controller.batterySaver) {
      _arrive(locationId);
      return;
    }

    final fromId = mapWalkStartLocationId(
      controller.db,
      controller.save.currentLocationId,
      _browseMapId,
    );
    final from = controller.indexes.locationsById[fromId];
    final to = controller.indexes.locationsById[locationId];
    final durationMs = mapWalkDurationMs(
      positionOnBrowseMap(fromId, _browseMapId, from),
      positionOnBrowseMap(locationId, _browseMapId, to),
    );

    _mapWalk?.dispose();
    _walkFromId = fromId;
    _walkToId = locationId;
    _mapWalk =
        AnimationController(
            vsync: this,
            duration: Duration(milliseconds: durationMs.round()),
          )
          ..addListener(() {
            if (mounted) setState(() {});
          })
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed && _walkToId == locationId) {
              _arrive(locationId);
            }
          })
          ..forward();
    setState(() {});
  }

  /// Opening the wardrobe is also what retires the portrait's hint.
  void _openWardrobe() {
    final save = controller.save;
    if (!save.hasSeenWardrobeIntro) {
      controller.commit(save.copyWith(hasSeenWardrobeIntro: true));
    }
    setState(() => _wardrobeOpen = true);
  }

  /// Warnings and status lines that float over the current screen.
  ///
  /// Combat round chatter stays off the toast while a fight is on screen.
  String? get _toastText {
    if (controller.productionInventoryFull) {
      return 'Inventory full — free a slot to keep crafting.';
    }
    if (controller.activityError case final error?) return error;
    if (controller.save.combatEnemyId != null) return null;
    return controller.message;
  }

  @override
  Widget build(BuildContext context) {
    // Structural / save changes only — clock ticks notify [GameController.progress]
    // so shell board textures are not rebuilt every frame.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return UiChromeScope(
          chrome: controller.chrome,
          child: Builder(
            builder: (context) {
              return RepaintBoundary(
                child: Container(
                  decoration: chromeShellDecoration(context),
                  child: SafeArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final available = constraints.biggest;
                        final frame = playableFrameSize(available);
                        final sideChat = playableFrameHasSideChat(available);
                        final game = SizedBox(
                          width: frame.width,
                          height: frame.height,
                          child: RepaintBoundary(
                            child: DecoratedBox(
                              decoration: chromeShellDecoration(
                                context,
                                gradient: UiChrome.of(context).frameGradient,
                              ),
                              // Material widgets (text fields, ink, tooltips) need one of these
                              // above them, and the frame's own gradient shows through it.
                              // A nested navigator keeps popups inside this 420px frame.
                              child: Material(
                                type: MaterialType.transparency,
                                clipBehavior: Clip.hardEdge,
                                child: MediaQuery(
                                  data: MediaQuery.of(context).copyWith(
                                    size: frame,
                                    textScaler: playableUiTextScaler(
                                      MediaQuery.textScalerOf(context),
                                    ),
                                  ),
                                  // Outer builder already listens to [controller];
                                  // only multiplayer needs a nested subscription.
                                  child: ListenableBuilder(
                                    listenable: multiplayer,
                                    builder: (context, _) => BatterySaverScope(
                                      enabled: controller.batterySaver,
                                      child: _buildFrame(context, sideChat: sideChat),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                        if (!sideChat) return Center(child: game);
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            game,
                            Expanded(
                              child: MediaQuery(
                                data: MediaQuery.of(context).copyWith(
                                  textScaler: playableUiTextScaler(
                                    MediaQuery.textScalerOf(context),
                                  ),
                                ),
                                child: ListenableBuilder(
                                  listenable: multiplayer,
                                  builder: (context, _) {
                                    final save = controller.save;
                                    return Material(
                                      key: const Key('chat-panel'),
                                      color: Palette.parchmentDeep,
                                      clipBehavior: Clip.antiAlias,
                                      child: ChatSheet(
                                        controller: controller,
                                        multiplayer: multiplayer,
                                        locationId: save.currentLocationId,
                                        citadelHub: _inCitadel,
                                        embedded: true,
                                        onClose: () {},
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildFrame(BuildContext context, {required bool sideChat}) {
    if (_needsAuth) {
      return AuthGateSheet(controller: controller, multiplayer: multiplayer);
    }
    if (_needsCharacter) {
      return NewCharacterSheet(
        controller: controller,
        multiplayer: multiplayer,
        onCreated: () => multiplayer.publishAccountSave(controller.save),
      );
    }
    final save = controller.save;
    multiplayer.syncChatSurface(
      open: _chatOpen || sideChat,
      locationId: save.currentLocationId,
      citadelHub: _inCitadel,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            if (multiplayer.cloudUnavailable)
              const Material(
                color: Palette.danger,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    'Cloud unavailable — progress is not syncing.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: playableHudTextScaler(MediaQuery.textScalerOf(context))),
              child: RepaintBoundary(
                child: TopHud(
                  controller: controller,
                  multiplayer: multiplayer,
                  onOpenWardrobe: _openWardrobe,
                  batterySaver: controller.batterySaver,
                ),
              ),
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  LocationView(
                    controller: controller,
                    multiplayer: multiplayer,
                    onOpenMap: _showMap,
                    onOpenSubMap: _browseSubMap,
                    onEnterGateway: _enterGateway,
                    onOpenGuilds: () => _selectScreen(GameScreen.guilds),
                  ),
                  if (_screen != GameScreen.location)
                    _PageLayer(
                      key: ValueKey(_screen),
                      motion: _screen == GameScreen.map
                          ? _PageMotion.expandFromChip
                          : _PageMotion.slideUp,
                      child: RepaintBoundary(
                        child: DecoratedBox(
                          decoration: chromeShellDecoration(
                            context,
                            gradient: UiChrome.of(context).frameGradient,
                          ),
                          child: _coveringPage(),
                        ),
                      ),
                    ),
                  if (_wardrobeOpen)
                    _PageLayer(
                      motion: _PageMotion.slideDown,
                      child: WardrobeSheet(
                        controller: controller,
                        onClose: () => setState(() => _wardrobeOpen = false),
                      ),
                    ),
                  if (_toastText case final text?)
                    Positioned(
                      top: 10,
                      left: 12,
                      right: 12,
                      child: OverlayNotice(
                        key: _toastKey,
                        text: text,
                        tone: controller.activityError != null || controller.productionInventoryFull
                            ? Palette.danger
                            : Palette.gold,
                        onDismissed: controller.clearMessages,
                      ),
                    ),
                  if (controller.batterySaver && _screen == GameScreen.location && !_wardrobeOpen)
                    Positioned(
                      left: 8,
                      bottom: 10,
                      child: _BatterySaverPlaque(
                        onOpenSettings: () => _selectScreen(GameScreen.menu),
                      ),
                    ),
                ],
              ),
            ),
            RepaintBoundary(
              child: BottomNav(
                screen: _screen,
                locationName: controller.location?.displayName ?? 'Unknown',
                onSelect: _selectScreen,
              ),
            ),
          ],
        ),
        if (!sideChat && !multiplayer.hideChatBubble)
          Positioned(
            right: 12,
            bottom: _screen == GameScreen.map ? chatLauncherBottomOnMap : chatLauncherBottom,
            child: ChatLauncher(
              open: _chatOpen,
              multiplayer: multiplayer,
              onToggle: () async {
                if (_chatOpen) {
                  _closeChat();
                  return;
                }
                if (multiplayer.canSeeSocialPages) {
                  await multiplayer.selectChatTab(
                    multiplayer.chatTab,
                    save.currentLocationId,
                    citadelHub: _inCitadel,
                  );
                }
                if (mounted) setState(() => _chatOpen = true);
              },
            ),
          ),
        if (!sideChat && _chatOpen)
          Positioned.fill(
            child: Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeChat,
                  child: const ColoredBox(color: Color(0x00000000)),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 50 + MediaQuery.viewInsetsOf(context).bottom,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.48,
                    ),
                    child: Material(
                      key: const Key('chat-panel'),
                      color: Palette.parchmentDeep,
                      elevation: 12,
                      shadowColor: const Color(0x73000000),
                      clipBehavior: Clip.antiAlias,
                      shape: PixelSteppedBorder(
                        step: 3,
                        side: const BorderSide(color: Palette.edge),
                      ),
                      child: ChatSheet(
                        controller: controller,
                        multiplayer: multiplayer,
                        locationId: save.currentLocationId,
                        citadelHub: _inCitadel,
                        onClose: _closeChat,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (controller.travel case final journey?)
          TravelOverlay(controller: controller, journey: journey),
        if (controller.returningFromAway)
          const ReturningOverlay()
        else if (controller.awaySummary case final summary?)
          AwaySummarySheet(summary: summary, onDismiss: controller.dismissAwaySummary),
        if (controller.autoEquip case final proposal?)
          AutoEquipPrompt(controller: controller, proposal: proposal),
        if (controller.cosmeticUnlock case final notice?)
          WardrobeUnlockPopup(
            notice: notice,
            item: notice.itemId == null ? null : controller.indexes.itemsById[notice.itemId!],
            onClose: controller.dismissCosmeticUnlock,
          ),
        if (controller.discoveryNotice case final notice?)
          SocialAlertOverlay(message: notice, onClose: controller.dismissDiscoveryNotice),
        if (_socialAlertEntry == null && _socialAlertMessage != null)
          SocialAlertOverlay(message: _socialAlertMessage!, onClose: _dismissSocialAlert),
        if (fennelIntroPending(save))
          Positioned.fill(
            child: Stack(
              children: [
                const ModalBarrier(dismissible: false, color: Color(0xB3120C08)),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GamePanel(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Fennel',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400),
                          ),
                          const SizedBox(height: 8),
                          const Text(fennelWelcome, style: TextStyle(fontSize: 15)),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: GameButton(
                              label: 'OK',
                              onPressed: () =>
                                  controller.commit(save.copyWith(hasSeenFennelIntro: true)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _coveringPage() {
    switch (_screen) {
      case GameScreen.location:
        return const SizedBox.shrink();
      case GameScreen.map:
        return WorldMapView(
          controller: controller,
          browseMapId: _browseMapId,
          selectedLocationId: _selectedLocationId,
          onSelect: (locationId) => setState(() => _selectedLocationId = locationId),
          onBrowseMap: _browseMap,
          onTravel: _travelTo,
          onOpenHere: () {
            _cancelMapWalk();
            _popPage();
          },
          onClose: _popPage,
          hiddenLocationIds: multiplayer.guildId == null
              ? const <String>[guildHallLocationId]
              : const <String>[],
          walkFromId: _walkFromId,
          walkToId: _walkToId,
          walkProgress: _mapWalk?.value,
        );
      case GameScreen.character:
        return CharacterView(controller: controller, onClose: _popPage);
      case GameScreen.log:
        return LogView(controller: controller, onClose: _popPage);
      case GameScreen.leaderboards:
        return SocialView(
          controller: controller,
          multiplayer: multiplayer,
          section: SocialTab.leaderboards,
          onClose: _popPage,
        );
      case GameScreen.guilds:
        return SocialView(
          controller: controller,
          multiplayer: multiplayer,
          section: SocialTab.guilds,
          onClose: _popPage,
          onTravelToHall: () {
            if (!controller.travelToGuildHall()) return;
            _popToLocation();
          },
        );
      case GameScreen.account:
        return MenuView(controller: controller, multiplayer: multiplayer, onClose: _popPage);
      case GameScreen.menu:
        return MenuView(controller: controller, multiplayer: multiplayer, onClose: _popPage);
    }
  }
}

class _PageLayer extends StatelessWidget {
  const _PageLayer({super.key, required this.motion, required this.child});

  final _PageMotion motion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (BatterySaverScope.of(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        final dy = switch (motion) {
          _PageMotion.slideUp => 28 * (1 - t),
          _PageMotion.slideDown => -28 * (1 - t),
          _PageMotion.expandFromChip => 0.0,
        };
        final scale = motion == _PageMotion.expandFromChip ? 0.88 + 0.12 * t : 1.0;
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.scale(
            alignment: motion == _PageMotion.expandFromChip ? Alignment.topRight : Alignment.center,
            scale: scale,
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _BatterySaverPlaque extends StatelessWidget {
  const _BatterySaverPlaque({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('battery-saver-plaque'),
      color: Palette.parchmentDeep,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Palette.gold, width: 1),
      ),
      child: InkWell(
        onTap: onOpenSettings,
        borderRadius: BorderRadius.circular(8),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt, size: 13, color: Palette.gold),
              SizedBox(width: 4),
              Text(
                'Battery saver',
                style: TextStyle(color: Palette.gold, fontSize: 11, fontWeight: FontWeight.w400),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
