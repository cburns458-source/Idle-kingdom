import 'package:flutter/material.dart';

import '../theme.dart';
import 'app_shell.dart';

const Duration _doubleTapWindow = Duration(milliseconds: 300);

const List<(GameScreen, String)> _nestItems = [
  (GameScreen.menu, 'Menu'),
  (GameScreen.log, 'Log'),
  (GameScreen.leaderboards, 'Leaderboards'),
  (GameScreen.guilds, 'Guilds'),
  (GameScreen.account, 'Account'),
];

final Set<GameScreen> _nestScreens = {for (final item in _nestItems) item.$1};

/// The chin: where you are, inventory, skills, and the nest for everything else.
class BottomNav extends StatefulWidget {
  const BottomNav({
    super.key,
    required this.screen,
    required this.locationName,
    required this.onSelect,
    required this.onOpenMap,
  });

  final GameScreen screen;
  final String locationName;
  final ValueChanged<GameScreen> onSelect;

  /// A second tap on the location name, matching the old double-tap-for-map.
  final VoidCallback onOpenMap;

  @override
  State<BottomNav> createState() => _BottomNavState();
}

class _BottomNavState extends State<BottomNav> {
  bool _nestOpen = false;
  DateTime? _lastLocationTap;

  bool get _nestActive => _nestOpen || _nestScreens.contains(widget.screen);

  void _closeNest() {
    if (_nestOpen) setState(() => _nestOpen = false);
  }

  void _select(GameScreen screen) {
    _closeNest();
    widget.onSelect(screen);
  }

  void _onLocationTap() {
    final now = DateTime.now();
    final last = _lastLocationTap;
    if (last != null && now.difference(last) <= _doubleTapWindow) {
      _lastLocationTap = null;
      _closeNest();
      widget.onOpenMap();
      return;
    }
    _lastLocationTap = now;
    _select(GameScreen.location);
  }

  void _selectNest(GameScreen screen) {
    setState(() => _nestOpen = false);
    widget.onSelect(screen);
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Palette.edge)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              children: [
                Expanded(
                  child: _NavButton(
                    label: widget.locationName,
                    selected: widget.screen == GameScreen.location,
                    tooltip: '${widget.locationName} (double-tap for world map)',
                    onTap: _onLocationTap,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _NavButton(
                    label: 'Inventory',
                    selected: widget.screen == GameScreen.inventory,
                    onTap: () => _select(GameScreen.inventory),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _NavButton(
                    label: 'Skills',
                    selected: widget.screen == GameScreen.skills,
                    onTap: () => _select(GameScreen.skills),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _NavButton(
                    selected: _nestActive,
                    tooltip: 'Open menu nest',
                    semanticsLabel: 'Open menu nest',
                    onTap: () => setState(() => _nestOpen = !_nestOpen),
                    child: const Icon(Icons.menu, size: 22),
                  ),
                ),
              ],
            ),
            if (_nestOpen)
              Positioned(
                right: 0,
                bottom: 50,
                child: _NestPopup(screen: widget.screen, onSelect: _selectNest),
              ),
          ],
        ),
      ),
    );
  }
}

class _NestPopup extends StatelessWidget {
  const _NestPopup({required this.screen, required this.onSelect});

  final GameScreen screen;
  final ValueChanged<GameScreen> onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFA302014),
      elevation: 12,
      shadowColor: const Color(0x73000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0x66D4AF37)),
      ),
      child: Semantics(
        container: true,
        label: 'More screens',
        explicitChildNodes: true,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            width: 168,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in _nestItems)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _NavButton(
                      label: item.$2,
                      selected: screen == item.$1,
                      alignStart: true,
                      onTap: () => onSelect(item.$1),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.onTap,
    this.label,
    this.child,
    this.selected = false,
    this.tooltip,
    this.semanticsLabel,
    this.alignStart = false,
  }) : assert(label != null || child != null);

  final String? label;
  final Widget? child;
  final bool selected;
  final VoidCallback onTap;
  final String? tooltip;
  final String? semanticsLabel;
  final bool alignStart;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        minimumSize: const Size.fromHeight(42),
        backgroundColor: selected ? const Color(0xD9546E3E) : const Color(0x8C281C12),
        foregroundColor: selected ? const Color(0xFFF4FFE8) : Palette.parchmentText,
        side: BorderSide(color: selected ? const Color(0x66BEDC96) : Palette.edge),
        alignment: alignStart ? Alignment.centerLeft : Alignment.center,
      ),
      child:
          child ??
          Text(
            label!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
    );
    final labeled = semanticsLabel == null
        ? button
        : Semantics(
            button: true,
            label: semanticsLabel,
            child: ExcludeSemantics(child: button),
          );
    if (tooltip == null) return labeled;
    return Tooltip(message: tooltip!, child: labeled);
  }
}
