import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../session/map_walk.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'auth_gate_sheet.dart';
import 'away_summary_sheet.dart';
import 'bottom_nav.dart';
import 'chat_sheet.dart';
import 'critter_overlay.dart';
import 'inventory_view.dart';
import 'location_view.dart';
import 'log_view.dart';
import 'menu_view.dart';
import 'new_character_sheet.dart';
import 'overlay_notice.dart';
import 'playable_frame.dart';
import 'skills_view.dart';
import 'social_alert.dart';
import 'social_view.dart';
import 'top_hud.dart';
import 'travel_overlay.dart';
import 'wardrobe_sheet.dart';
import 'world_map_view.dart';

enum GameScreen { location, map, skills, inventory, log, leaderboards, guilds, account, menu }

/// Sits on the chin. Kept low on the location screen so it does not cover
/// Expand list or the activity buttons.
const double chatLauncherBottom = 62;

/// On the map, sits above the Travel strip.
const double chatLauncherBottomOnMap = 192;

const Set<GameScreen> _chinScreens = {
  GameScreen.skills,
  GameScreen.inventory,
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
  /// backgrounded; the next tick picks the elapsed time back up from the clock.
  Ticker? _ticker;

  final List<GameScreen> _stack = [GameScreen.location];
  late String _browseMapId = _mapIdForCurrentLocation();
  String? _selectedLocationId;
  bool _wardrobeOpen = false;
  bool _chatOpen = false;
  bool _socialAlertQueued = false;

  GameScreen get _screen => _stack.last;
  final GlobalKey _toastKey = GlobalKey();
  AnimationController? _mapWalk;
  String? _walkFromId;
  String? _walkToId;

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
    multiplayer.onAccountCleared ??= controller.resetUnsigned;
    multiplayer.addListener(_onMultiplayerChanged);
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
    if (text == null || text.isEmpty || _socialAlertQueued) return;
    _socialAlertQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
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
      await showSocialAlert(context, message);
      if (!mounted) return;
      if (multiplayer.notice == message) multiplayer.announce(null);
      _socialAlertQueued = false;
      _maybePresentSocialNotice();
    });
  }

  bool _polling = false;

  /// Presence and the game clock stay off until the player is signed in and named.
  void _syncPlayLoop() {
    if (_canPlay) {
      if (!(_ticker?.isActive ?? false)) _ticker?.start();
    } else {
      _ticker?.stop();
    }
    final shouldPoll = multiplayer.isSignedIn;
    if (shouldPoll && !_polling) {
      _polling = true;
      multiplayer.startPolling(() => controller.save);
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    multiplayer.flushAccountSave(controller.save);
    multiplayer.removeListener(_onMultiplayerChanged);
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    _mapWalk?.dispose();
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

  /// Opens the district map behind the gateway the player is standing on.
  void _browseSubMap(String mapId) {
    _cancelMapWalk();
    setState(() {
      _browseMapId = mapId;
      _selectedLocationId = null;
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

  void _arrive(String locationId) {
    _cancelMapWalk();
    if (!controller.travelTo(locationId, _browseMapId)) return;
    setState(() {
      _browseMapId = _mapIdForCurrentLocation();
      _selectedLocationId = null;
      _wardrobeOpen = false;
      _stack
        ..clear()
        ..add(GameScreen.location);
    });
  }

  void _travelTo(String locationId) {
    if (controller.isRecovering) return;
    if (!canTravelTo(
      controller.db,
      controller.save.currentLocationId,
      locationId,
      _browseMapId,
      controller.save.unlockedLocationIds,
    )) {
      return;
    }
    if (!controller.mapTravelAnimation) {
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
    if (controller.activityError case final error?) return error;
    if (controller.save.combatEnemyId != null) return null;
    return controller.message;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: Palette.shellGradient),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final frame = playableFrameSize(constraints.biggest);
            return Center(
              child: SizedBox(
                width: frame.width,
                height: frame.height,
                child: DecoratedBox(
                  decoration: const BoxDecoration(gradient: Palette.frameGradient),
                  // Material widgets (text fields, ink, tooltips) need one of these
                  // above them, and the frame's own gradient shows through it.
                  // A nested navigator keeps popups inside this 420px frame.
                  child: Material(
                    type: MaterialType.transparency,
                    clipBehavior: Clip.hardEdge,
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(size: frame),
                      child: ListenableBuilder(
                        listenable: Listenable.merge(<Listenable>[controller, multiplayer]),
                        builder: (context, _) => _buildFrame(context),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFrame(BuildContext context) {
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
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            TopHud(controller: controller, multiplayer: multiplayer, onOpenWardrobe: _openWardrobe),
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
                    onOpenGuilds: () => _selectScreen(GameScreen.guilds),
                  ),
                  if (_screen != GameScreen.location)
                    _PageLayer(
                      key: ValueKey(_screen),
                      motion: _screen == GameScreen.map
                          ? _PageMotion.expandFromChip
                          : _PageMotion.slideUp,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(gradient: Palette.frameGradient),
                        child: _coveringPage(),
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
                        tone: controller.activityError != null ? Palette.danger : Palette.gold,
                        onDismissed: controller.clearMessages,
                      ),
                    ),
                ],
              ),
            ),
            BottomNav(
              screen: _screen,
              locationName: controller.location?.displayName ?? 'Unknown',
              onSelect: _selectScreen,
            ),
          ],
        ),
        if (!multiplayer.hideChatBubble)
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
        if (_chatOpen)
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
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
        if (controller.awaySummary case final summary?)
          AwaySummarySheet(summary: summary, onDismiss: controller.dismissAwaySummary),
        if (controller.autoEquip case final proposal?)
          AutoEquipPrompt(controller: controller, proposal: proposal),
        if (controller.cosmeticUnlock case final notice?)
          WardrobeUnlockPopup(
            notice: notice,
            item: notice.itemId == null ? null : controller.indexes.itemsById[notice.itemId!],
            onClose: controller.dismissCosmeticUnlock,
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
      case GameScreen.skills:
        return SkillsView(controller: controller, onClose: _popPage);
      case GameScreen.inventory:
        return InventoryView(controller: controller, onClose: _popPage);
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
