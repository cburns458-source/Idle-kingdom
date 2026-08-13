import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'away_summary_sheet.dart';
import 'bottom_nav.dart';
import 'inventory_view.dart';
import 'location_view.dart';
import 'new_character_sheet.dart';
import 'skills_view.dart';
import 'top_hud.dart';
import 'travel_overlay.dart';
import 'world_map_view.dart';

enum GameScreen { location, map, skills, inventory }

/// The frame the whole game lives in: HUD on top, screen in the middle, nav
/// underneath, and the overlays that can cover all three.
///
/// Portrait-first and capped in width, so a desktop browser shows the same
/// layout a phone does rather than stretching it.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final GameController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with SingleTickerProviderStateMixin {
  /// Drives the game loop. Coming from the widget means it stops when the app is
  /// backgrounded; the next tick picks the elapsed time back up from the clock.
  Ticker? _ticker;

  GameScreen _screen = GameScreen.location;
  late String _browseMapId = _mapIdForCurrentLocation();
  String? _selectedLocationId;

  GameController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => controller.tick())..start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  String _mapIdForCurrentLocation() {
    final location = widget.controller.location;
    if (location == null) return mainMapId;
    return resolveActiveMapId(widget.controller.db, location);
  }

  void _showMap() {
    setState(() {
      _browseMapId = _mapIdForCurrentLocation();
      _selectedLocationId = controller.save.currentLocationId;
      _screen = GameScreen.map;
    });
  }

  void _travelTo(String locationId) {
    if (!controller.travelTo(locationId, _browseMapId)) return;
    setState(() {
      _browseMapId = _mapIdForCurrentLocation();
      _selectedLocationId = null;
      _screen = GameScreen.location;
    });
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
            TopHud(controller: controller),
            Expanded(child: _buildScreen()),
            BottomNav(
              screen: _screen,
              locationName: controller.location?.displayName ?? 'Unknown',
              onSelect: (screen) {
                if (screen == GameScreen.map) {
                  _showMap();
                  return;
                }
                setState(() => _screen = screen);
              },
            ),
          ],
        ),
        if (controller.travel case final journey?)
          TravelOverlay(controller: controller, journey: journey),
        if (controller.awaySummary case final summary?)
          AwaySummarySheet(summary: summary, onDismiss: controller.dismissAwaySummary),
        if (save.characterName == null || save.raceId == null)
          NewCharacterSheet(controller: controller),
      ],
    );
  }

  Widget _buildScreen() {
    switch (_screen) {
      case GameScreen.location:
        return LocationView(controller: controller, onOpenMap: _showMap);
      case GameScreen.map:
        return WorldMapView(
          controller: controller,
          browseMapId: _browseMapId,
          selectedLocationId: _selectedLocationId,
          onSelect: (locationId) => setState(() => _selectedLocationId = locationId),
          onBrowseMap: (mapId) => setState(() {
            _browseMapId = mapId;
            _selectedLocationId = null;
          }),
          onTravel: _travelTo,
        );
      case GameScreen.skills:
        return SkillsView(controller: controller);
      case GameScreen.inventory:
        return InventoryView(controller: controller);
    }
  }
}
