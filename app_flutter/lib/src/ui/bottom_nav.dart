import 'package:flutter/material.dart';

import '../content/asset_paths.dart';
import '../theme.dart';
import 'app_shell.dart';

/// The always-present nav row: where you are, the map, and the screens.
class BottomNav extends StatelessWidget {
  const BottomNav({
    super.key,
    required this.screen,
    required this.locationName,
    required this.onSelect,
  });

  final GameScreen screen;
  final String locationName;
  final ValueChanged<GameScreen> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Palette.edge)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _NavButton(
              label: locationName,
              selected: screen == GameScreen.location,
              onTap: () => onSelect(GameScreen.location),
            ),
          ),
          const SizedBox(width: 6),
          _MapButton(selected: screen == GameScreen.map, onTap: () => onSelect(GameScreen.map)),
          const SizedBox(width: 6),
          Expanded(
            child: _NavButton(
              label: 'Skills',
              selected: screen == GameScreen.skills,
              onTap: () => onSelect(GameScreen.skills),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _NavButton(
              label: 'Inventory',
              selected: screen == GameScreen.inventory,
              onTap: () => onSelect(GameScreen.inventory),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _NavButton(
              label: 'Log',
              selected: screen == GameScreen.log,
              onTap: () => onSelect(GameScreen.log),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        backgroundColor: selected ? const Color(0x33D4AF37) : null,
        side: BorderSide(color: selected ? Palette.gold : Palette.edge),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: 'Map',
      style: IconButton.styleFrom(
        backgroundColor: selected ? const Color(0x33D4AF37) : null,
        side: BorderSide(color: selected ? Palette.gold : Palette.edge),
      ),
      icon: Image.asset(uiMapAssetPath(), width: 22, height: 22),
    );
  }
}
