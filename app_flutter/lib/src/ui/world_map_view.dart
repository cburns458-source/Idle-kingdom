import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../session/map_geometry.dart';
import '../session/map_walk.dart';
import '../theme.dart';
import 'game_image.dart';
import 'page_header.dart';
import 'player_sprite.dart';

/// How far below the top of a node widget its dot centre sits: the 8px of top
/// padding plus half of the 14px dot.
const double mapNodeDotCenter = 15;

/// Side of the walking sprite.
const double mapWalkerSize = 36;

/// The map: nodes over the map art, and a panel for whichever one is selected.
class WorldMapView extends StatelessWidget {
  const WorldMapView({
    super.key,
    required this.controller,
    required this.browseMapId,
    required this.selectedLocationId,
    required this.onSelect,
    required this.onBrowseMap,
    required this.onTravel,
    this.onOpenHere,
    this.onClose,
    this.hiddenLocationIds = const <String>[],
    this.walkFromId,
    this.walkToId,
    this.walkProgress,
  });

  final GameController controller;
  final String browseMapId;
  final String? selectedLocationId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onBrowseMap;
  final ValueChanged<String> onTravel;

  /// Opens the location page for the node the player is already standing on.
  final VoidCallback? onOpenHere;

  final VoidCallback? onClose;

  /// Nodes to omit — the Guild Hall until the player has joined a guild.
  final List<String> hiddenLocationIds;

  /// The node the walking sprite left, when a map walk is in flight.
  final String? walkFromId;

  /// The node the walking sprite is heading to.
  final String? walkToId;

  /// 0–1 along the walk. Null when nobody is walking.
  final double? walkProgress;

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    final nodes = locationsForMapView(
      controller.db,
      browseMapId,
      save.unlockedLocationIds,
      hiddenLocationIds,
      save.currentLocationId,
      save,
    );
    final selected = selectedLocationId == null
        ? null
        : controller.indexes.locationsById[selectedLocationId!];
    final walking = walkProgress != null && walkFromId != null && walkToId != null;
    final fromRow = walkFromId == null ? null : controller.indexes.locationsById[walkFromId!];
    final toRow = walkToId == null ? null : controller.indexes.locationsById[walkToId!];

    // The panel floats over the art rather than sitting under it, so opening it
    // never resizes the map.
    return Stack(
      fit: StackFit.expand,
      children: [
        GameImage(mapAssetPath(browseMapId), fit: BoxFit.cover),
        // Nodes are pinned to the art rather than to this widget, so they stay
        // on their landmarks whatever shape the viewport is.
        LayoutBuilder(
          builder: (context, constraints) {
            final box = constraints.biggest;
            final artAspect = artAspectRatioForMap(browseMapId);
            return Stack(
              children: [
                for (final node in nodes)
                  _PinnedToArt(
                    position: positionOnBrowseMap(node.locationId, browseMapId, node),
                    box: box,
                    aspectRatio: artAspect,
                    anchorFromTop: mapNodeDotCenter,
                    child: _MapNode(
                      location: node,
                      browseMapId: browseMapId,
                      hintPulse:
                          questHintNodeId(controller.db, save, browseMapId) == node.locationId,
                      isHere: !walking && node.locationId == save.currentLocationId,
                      isSelected: node.locationId == selectedLocationId,
                      onTap: () => onSelect(node.locationId),
                      onDoubleTap: controller.isRecovering || walking
                          ? null
                          : isSubMapGateway(node)
                          ? () => onTravel(node.locationId)
                          : node.locationId == save.currentLocationId
                          ? onOpenHere
                          : () => onTravel(node.locationId),
                    ),
                  ),
                if (walking)
                  _PinnedToArt(
                    position: lerpNodePosition(
                      positionOnBrowseMap(walkFromId!, browseMapId, fromRow),
                      positionOnBrowseMap(walkToId!, browseMapId, toRow),
                      walkProgress!,
                    ),
                    box: box,
                    aspectRatio: artAspect,
                    anchorFromTop: mapWalkerSize / 2,
                    child: _MapWalker(
                      progress: walkProgress!,
                      appearance: save.appearance,
                      raceId: save.raceId,
                      bytes: controller.localPlayerPng,
                    ),
                  ),
              ],
            );
          },
        ),
        if (onClose != null)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: PageHeader(title: 'Map', onClose: onClose!),
          ),
        if (browseMapId != mainMapId)
          Positioned(
            right: 12,
            top: onClose == null ? 12 : 56,
            child: OverlayChipButton(
              tooltip: 'Open world map',
              onPressed: () => onBrowseMap(mainMapId),
              child: GameImage(uiMapAssetPath(), width: 38, height: 38),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _SelectionPanel(
            controller: controller,
            selected: selected,
            browseMapId: browseMapId,
            isHere: selected?.locationId == save.currentLocationId,
            isPortal: selected != null && isSubMapGateway(selected),
            onTravel: onTravel,
            canTravel: !controller.isRecovering && !walking,
          ),
        ),
      ],
    );
  }
}

/// Holds [child] over the point on the map art that [position] names.
///
/// The art is drawn with [BoxFit.cover], so the widget box and the art are not
/// the same rectangle. Pinning to the art is what keeps a node on its landmark.
class _PinnedToArt extends StatelessWidget {
  const _PinnedToArt({
    required this.position,
    required this.box,
    required this.aspectRatio,
    required this.anchorFromTop,
    required this.child,
  });

  final NodePosition position;
  final Size box;
  final double aspectRatio;

  /// How far down [child] the coordinate should land. A node label hangs below
  /// its dot, so centring the whole widget would leave the dot sitting high.
  final double anchorFromTop;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final point = mapArtOffset(position, box, aspectRatio: aspectRatio);
    return Positioned(
      left: point.dx,
      top: point.dy - anchorFromTop,
      child: FractionalTranslation(translation: const Offset(-0.5, 0), child: child),
    );
  }
}

/// A shrunk player sprite, wobbling as it walks.
class _MapWalker extends StatelessWidget {
  const _MapWalker({required this.progress, required this.appearance, this.raceId, this.bytes});

  final double progress;
  final PlayerAppearance appearance;
  final String? raceId;
  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Travelling',
      child: Transform.rotate(
        angle: mapWalkWobbleRadians(progress),
        child: PlayerSprite(
          appearance: appearance,
          raceId: raceId,
          bytes: bytes,
          width: mapWalkerSize,
          height: mapWalkerSize,
        ),
      ),
    );
  }
}

class _MapNode extends StatefulWidget {
  const _MapNode({
    required this.location,
    required this.browseMapId,
    required this.isHere,
    required this.isSelected,
    required this.hintPulse,
    required this.onTap,
    required this.onDoubleTap,
  });

  final LocationRow location;
  final String browseMapId;
  final bool isHere;
  final bool isSelected;
  final bool hintPulse;
  final VoidCallback onTap;

  /// A second tap travels, so a place can be reached without the panel.
  final VoidCallback? onDoubleTap;

  @override
  State<_MapNode> createState() => _MapNodeState();
}

class _MapNodeState extends State<_MapNode> with SingleTickerProviderStateMixin {
  /// Timed by hand rather than with `onDoubleTap`, which would hold the first
  /// tap back for the whole double-tap window before selecting anything.
  static const Duration _window = Duration(milliseconds: 300);

  DateTime? _lastTap;
  late final AnimationController _hint;

  @override
  void initState() {
    super.initState();
    _hint = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    if (widget.hintPulse) _hint.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_MapNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hintPulse && !_hint.isAnimating) {
      _hint.repeat(reverse: true);
    } else if (!widget.hintPulse && _hint.isAnimating) {
      _hint
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _hint.dispose();
    super.dispose();
  }

  void _handleTap() {
    final now = DateTime.now();
    final last = _lastTap;
    _lastTap = now;
    if (widget.onDoubleTap case final travel?
        when last != null && now.difference(last) <= _window) {
      _lastTap = null;
      travel();
      return;
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.location;
    final isHere = widget.isHere;
    final isSelected = widget.isSelected;
    final label = mapNodeLabel(location, widget.browseMapId);
    final fill = isHere ? Palette.gold : Palette.parchmentText;
    return GestureDetector(
      onTap: _handleTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: label,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: widget.hintPulse
                  ? AnimatedBuilder(
                      animation: _hint,
                      builder: (context, _) {
                        final border = Color.lerp(
                          const Color(0xB3B42318),
                          const Color(0xFFB42318),
                          _hint.value,
                        )!;
                        return _mapDot(fill: fill, border: border, width: 2);
                      },
                    )
                  : _mapDot(
                      fill: fill,
                      border: isSelected ? Palette.gold : Palette.parchment,
                      width: isSelected || isHere ? 2 : 1,
                    ),
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: isHere ? Palette.gold : Palette.parchmentText,
              shadows: overlayShadow,
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapDot({required Color fill, required Color border, required double width}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(color: border, width: width),
        boxShadow: const [BoxShadow(offset: Offset(0, 1), color: Color(0x80000000))],
      ),
      child: const SizedBox.square(dimension: 14),
    );
  }
}

/// What is at the selected place, and the one button that takes you there.
class _SelectionPanel extends StatelessWidget {
  const _SelectionPanel({
    required this.controller,
    required this.selected,
    required this.browseMapId,
    required this.isHere,
    required this.isPortal,
    required this.onTravel,
    required this.canTravel,
  });

  final GameController controller;
  final LocationRow? selected;
  final String browseMapId;
  final bool isHere;

  /// Gateways travel into their landing, or return to the world without moving.
  final bool isPortal;
  final ValueChanged<String> onTravel;
  final bool canTravel;

  @override
  Widget build(BuildContext context) {
    final place = selected;
    final skillIds = place == null
        ? const <String>[]
        : skillIdsForLocation(controller.db, controller.save, place.locationId);
    final hasShop = place != null && locationHasShop(controller.db, place.locationId);
    final showIcons = controller.showActivityIcons && (skillIds.isNotEmpty || hasShop);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Palette.slot,
        border: Border(top: BorderSide(color: Palette.edge)),
      ),
      child: place == null
          ? const MutedText('Pick a place to see what is there. Double-tap one to go.')
          : Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mapNodeLabel(place, browseMapId),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400),
                      ),
                      if (showIcons) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final skillId in skillIds)
                              _LocationActivityIcon(
                                tooltip:
                                    controller.indexes.skillsById[skillId]?.displayName ?? 'Skill',
                                path: skillIconPath(controller.indexes.skillsById[skillId]),
                              ),
                            if (hasShop)
                              _LocationActivityIcon(tooltip: 'Shop', path: goldIconPath()),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (isHere && !isPortal)
                  const MutedText('You are here.')
                else
                  GameButton(
                    label: 'Travel',
                    onPressed: canTravel ? () => onTravel(place.locationId) : null,
                  ),
              ],
            ),
    );
  }
}

class _LocationActivityIcon extends StatelessWidget {
  const _LocationActivityIcon({required this.tooltip, required this.path});

  final String tooltip;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Tooltip(message: tooltip, child: GameImage(path, width: 22, height: 22));
  }
}
