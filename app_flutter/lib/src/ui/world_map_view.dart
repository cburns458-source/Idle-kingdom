import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../theme.dart';

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
  });

  final GameController controller;
  final String browseMapId;
  final String? selectedLocationId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onBrowseMap;
  final ValueChanged<String> onTravel;

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    final nodes = locationsForMapView(controller.db, browseMapId, save.unlockedLocationIds);
    final selected = selectedLocationId == null
        ? null
        : controller.indexes.locationsById[selectedLocationId!];

    // The panel floats over the art rather than sitting under it, so opening it
    // never resizes the map.
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          mapAssetPath(browseMapId),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.none,
        ),
        for (final node in nodes)
          _MapNode(
            location: node,
            isHere: node.locationId == save.currentLocationId,
            isSelected: node.locationId == selectedLocationId,
            onTap: () => onSelect(node.locationId),
            onDoubleTap: node.locationId == save.currentLocationId
                ? null
                : () => onTravel(node.locationId),
          ),
        if (browseMapId != mainMapId)
          Positioned(
            left: 12,
            top: 12,
            child: GameButton(
              label: 'Back to the world map',
              tone: GameButtonTone.secondary,
              onPressed: () => onBrowseMap(mainMapId),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _SelectionPanel(
            selected: selected,
            isHere: selected?.locationId == save.currentLocationId,
            onTravel: onTravel,
          ),
        ),
      ],
    );
  }
}

class _MapNode extends StatefulWidget {
  const _MapNode({
    required this.location,
    required this.isHere,
    required this.isSelected,
    required this.onTap,
    required this.onDoubleTap,
  });

  final LocationRow location;
  final bool isHere;
  final bool isSelected;
  final VoidCallback onTap;

  /// A second tap travels, so a place can be reached without the panel.
  final VoidCallback? onDoubleTap;

  @override
  State<_MapNode> createState() => _MapNodeState();
}

class _MapNodeState extends State<_MapNode> {
  /// Timed by hand rather than with `onDoubleTap`, which would hold the first
  /// tap back for the whole double-tap window before selecting anything.
  static const Duration _window = Duration(milliseconds: 300);

  DateTime? _lastTap;

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
    final position = positionForLocation(location);
    return Align(
      // Percentages from the shared layout map onto the alignment square.
      alignment: Alignment(position.x / 50 - 1, position.y / 50 - 1),
      child: GestureDetector(
        onTap: _handleTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isHere ? const Color(0xDD3D2A1A) : const Color(0xAA1F1610),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isSelected || isHere ? Palette.gold : Palette.edge,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Text(
            location.displayName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isHere ? FontWeight.w700 : FontWeight.w400,
              color: isHere ? Palette.gold : Palette.parchmentText,
            ),
          ),
        ),
      ),
    );
  }
}

/// What is at the selected place, and the one button that takes you there.
///
/// Entering a sub-map is not offered here: that belongs to the gateway's own
/// location page, once the player has actually travelled to it.
class _SelectionPanel extends StatelessWidget {
  const _SelectionPanel({required this.selected, required this.isHere, required this.onTravel});

  final LocationRow? selected;
  final bool isHere;
  final ValueChanged<String> onTravel;

  @override
  Widget build(BuildContext context) {
    final place = selected;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xF02A1C12),
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
                        place.displayName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      if (place.description case final blurb?) MutedText(blurb),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (isHere)
                  const MutedText('You are here.')
                else
                  GameButton(label: 'Travel', onPressed: () => onTravel(place.locationId)),
              ],
            ),
    );
  }
}
