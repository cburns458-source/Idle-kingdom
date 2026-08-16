import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../session/map_walk.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'away_summary_sheet.dart';
import 'bottom_nav.dart';
import 'chat_sheet.dart';
import 'critter_overlay.dart';
import 'inventory_view.dart';
import 'location_view.dart';
import 'log_view.dart';
import 'menu_view.dart';
import 'nearby_panel.dart';
import 'new_character_sheet.dart';
import 'overlay_notice.dart';
import 'skills_view.dart';
import 'social_view.dart';
import 'top_hud.dart';
import 'travel_overlay.dart';
import 'wardrobe_sheet.dart';
import 'world_map_view.dart';

enum GameScreen { location, map, skills, inventory, log, leaderboards, guilds, account, menu }

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

class _AppShellState extends State<AppShell> with TickerProviderStateMixin {
  /// Drives the game loop. Coming from the widget means it stops when the app is
  /// backgrounded; the next tick picks the elapsed time back up from the clock.
  Ticker? _ticker;

  GameScreen _screen = GameScreen.location;
  late String _browseMapId = _mapIdForCurrentLocation();
  String? _selectedLocationId;
  bool _wardrobeOpen = false;
  bool _nearbyOpen = false;
  final GlobalKey _toastKey = GlobalKey();
  AnimationController? _mapWalk;
  String? _walkFromId;
  String? _walkToId;

  GameController get controller => widget.controller;
  MultiplayerController get multiplayer => widget.multiplayer;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (!mounted) return;
      controller.tick();
    })..start();
    // Presence and the unread count only matter for a signed-in player; the
    // timers check that themselves, so starting them once here is enough.
    multiplayer.startPolling(() => controller.save);
  }

  @override
  void dispose() {
    _ticker?.dispose();
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
      _screen = GameScreen.map;
    });
  }

  /// Opens the district map behind the gateway the player is standing on.
  void _browseSubMap(String mapId) {
    _cancelMapWalk();
    setState(() {
      _browseMapId = mapId;
      _selectedLocationId = null;
      _screen = GameScreen.map;
    });
  }

  void _selectScreen(GameScreen screen) {
    if (_screen == GameScreen.map && screen != GameScreen.map) {
      _cancelMapWalk();
    }
    setState(() => _screen = screen);
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
      _screen = GameScreen.location;
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: DecoratedBox(
              decoration: const BoxDecoration(gradient: Palette.frameGradient),
              // Material widgets (text fields, ink, tooltips) need one of these
              // above them, and the frame's own gradient shows through it.
              child: Material(
                type: MaterialType.transparency,
                clipBehavior: Clip.none,
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) => _buildFrame(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFrame(BuildContext context) {
    final save = controller.save;
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            TopHud(controller: controller, onOpenWardrobe: _openWardrobe),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  _buildScreen(),
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
        Positioned(
          right: 12,
          bottom: 62,
          child: ChatLauncher(
            controller: controller,
            multiplayer: multiplayer,
            locationId: save.currentLocationId,
            citadelHub: _inCitadel,
          ),
        ),
        if (_nearbyOpen)
          NearbyPanel(
            controller: controller,
            multiplayer: multiplayer,
            onClose: () => setState(() => _nearbyOpen = false),
          ),
        if (_wardrobeOpen)
          WardrobeSheet(
            controller: controller,
            onClose: () => setState(() => _wardrobeOpen = false),
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
        if (save.characterName == null || save.raceId == null)
          NewCharacterSheet(controller: controller),
      ],
    );
  }

  Widget _buildScreen() {
    switch (_screen) {
      case GameScreen.location:
        return LocationView(
          controller: controller,
          multiplayer: multiplayer,
          onOpenMap: _showMap,
          onOpenSubMap: _browseSubMap,
          onOpenNearby: () => setState(() => _nearbyOpen = true),
          onOpenGuilds: () => setState(() => _screen = GameScreen.guilds),
        );
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
            setState(() => _screen = GameScreen.location);
          },
          hiddenLocationIds: multiplayer.guildId == null
              ? const <String>[guildHallLocationId]
              : const <String>[],
          walkFromId: _walkFromId,
          walkToId: _walkToId,
          walkProgress: _mapWalk?.value,
        );
      case GameScreen.skills:
        return SkillsView(controller: controller);
      case GameScreen.inventory:
        return InventoryView(controller: controller);
      case GameScreen.log:
        return LogView(controller: controller);
      case GameScreen.leaderboards:
        return SocialView(
          controller: controller,
          multiplayer: multiplayer,
          section: SocialTab.leaderboards,
        );
      case GameScreen.guilds:
        return SocialView(
          controller: controller,
          multiplayer: multiplayer,
          section: SocialTab.guilds,
          onTravelToHall: () {
            if (!controller.travelToGuildHall()) return;
            setState(() => _screen = GameScreen.location);
          },
        );
      case GameScreen.account:
        return SocialView(
          controller: controller,
          multiplayer: multiplayer,
          section: SocialTab.account,
        );
      case GameScreen.menu:
        return MenuView(controller: controller, multiplayer: multiplayer);
    }
  }
}
