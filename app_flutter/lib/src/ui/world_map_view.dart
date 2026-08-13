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

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(mapAssetPath(browseMapId), fit: BoxFit.cover),
              for (final node in nodes)
                _MapNode(
                  location: node,
                  isHere: node.locationId == save.currentLocationId,
                  isSelected: node.locationId == selectedLocationId,
                  onTap: () => onSelect(node.locationId),
                ),
            ],
          ),
        ),
        _SelectionPanel(
          controller: controller,
          browseMapId: browseMapId,
          selected: selected,
          onBrowseMap: onBrowseMap,
          onTravel: onTravel,
        ),
      ],
    );
  }
}

class _MapNode extends StatelessWidget {
  const _MapNode({
    required this.location,
    required this.isHere,
    required this.isSelected,
    required this.onTap,
  });

  final LocationRow location;
  final bool isHere;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final position = positionForLocation(location);
    return Align(
      // Percentages from the shared layout map onto the alignment square.
      alignment: Alignment(position.x / 50 - 1, position.y / 50 - 1),
      child: GestureDetector(
        onTap: onTap,
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

class _SelectionPanel extends StatelessWidget {
  const _SelectionPanel({
    required this.controller,
    required this.browseMapId,
    required this.selected,
    required this.onBrowseMap,
    required this.onTravel,
  });

  final GameController controller;
  final String browseMapId;
  final LocationRow? selected;
  final ValueChanged<String> onBrowseMap;
  final ValueChanged<String> onTravel;

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    final place = selected;
    final subMapId = place == null ? null : subMapIdForGateway(controller.db, place.locationId);
    final isHere = place?.locationId == save.currentLocationId;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Palette.edge)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (browseMapId != mainMapId)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () => onBrowseMap(mainMapId),
                child: const Text('Back to the world map'),
              ),
            ),
          if (place == null)
            const MutedText('Pick a place to see what is there.')
          else ...[
            Text(
              place.displayName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (place.description case final blurb?) MutedText(blurb),
            const SizedBox(height: 8),
            Row(
              children: [
                if (subMapId != null)
                  OutlinedButton(
                    onPressed: () => onBrowseMap(subMapId),
                    child: Text(enterSubMapLabel(controller.db, place) ?? 'Enter'),
                  ),
                if (subMapId != null) const SizedBox(width: 8),
                if (!isHere)
                  FilledButton(
                    onPressed: () => onTravel(place.locationId),
                    child: const Text('Travel'),
                  )
                else
                  const MutedText('You are here.'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
