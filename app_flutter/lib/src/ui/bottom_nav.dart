import 'package:flutter/material.dart';

import '../theme.dart';
import 'app_shell.dart';

const List<(GameScreen, String)> _nestItems = [
  (GameScreen.menu, 'Settings'),
  (GameScreen.log, 'Log'),
  (GameScreen.leaderboards, 'Leaderboards'),
  (GameScreen.guilds, 'Guilds'),
];

final Set<GameScreen> _nestScreens = {for (final item in _nestItems) item.$1};

/// The chin: where you are, character, and the nest for everything else.
class BottomNav extends StatefulWidget {
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
  State<BottomNav> createState() => _BottomNavState();
}

class _BottomNavState extends State<BottomNav> {
  final LayerLink _nestLink = LayerLink();
  OverlayEntry? _nestEntry;

  bool get _nestOpen => _nestEntry != null;
  bool get _nestActive => _nestOpen || _nestScreens.contains(widget.screen);

  @override
  void dispose() {
    _nestEntry?.remove();
    _nestEntry = null;
    super.dispose();
  }

  void _closeNest() {
    _nestEntry?.remove();
    _nestEntry = null;
    if (mounted) setState(() {});
  }

  void _toggleNest() {
    if (_nestOpen) {
      _closeNest();
      return;
    }
    final entry = OverlayEntry(builder: _buildNestOverlay);
    _nestEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    setState(() {});
  }

  Widget _buildNestOverlay(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _closeNest,
            child: const ColoredBox(color: Color(0x00000000)),
          ),
        ),
        CompositedTransformFollower(
          link: _nestLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topRight,
          followerAnchor: Alignment.bottomRight,
          offset: const Offset(0, -8),
          child: _NestPopup(
            screen: widget.screen,
            onSelect: (screen) {
              _closeNest();
              _selectTab(screen);
            },
          ),
        ),
      ],
    );
  }

  void _selectTab(GameScreen screen) {
    _closeNest();
    if (widget.screen == screen) {
      widget.onSelect(GameScreen.location);
      return;
    }
    widget.onSelect(screen);
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: chromeBoardFill(
        context,
        border: const Border(top: BorderSide(color: Palette.edge)),
      ),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(
              child: _NavSection(
                label: widget.locationName,
                selected: widget.screen == GameScreen.location,
                tooltip: widget.locationName,
                onTap: () => _selectTab(GameScreen.location),
              ),
            ),
            const VerticalDivider(width: 1, color: Palette.edge),
            Expanded(
              child: _NavSection(
                label: 'Character',
                selected: widget.screen == GameScreen.character,
                onTap: () => _selectTab(GameScreen.character),
              ),
            ),
            const VerticalDivider(width: 1, color: Palette.edge),
            Expanded(
              child: CompositedTransformTarget(
                link: _nestLink,
                child: _NavSection(
                  selected: _nestActive,
                  tooltip: 'Open menu',
                  semanticsLabel: 'Open menu',
                  onTap: _toggleNest,
                  child: const Icon(Icons.menu, size: 22),
                ),
              ),
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
      shape: PixelSteppedBorder(step: 3, side: const BorderSide(color: Color(0x669A7B32))),
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
                    child: _NavSection(
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

class _NavSection extends StatelessWidget {
  const _NavSection({
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
    final content =
        child ??
        Text(
          label!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignStart ? TextAlign.left : TextAlign.center,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
        );
    final button = Material(
      color: selected ? const Color(0xD9546E3E) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.expand(
          child: Align(
            alignment: alignStart ? Alignment.centerLeft : Alignment.center,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: content),
          ),
        ),
      ),
    );
    final sized = alignStart
        ? SizedBox(
            height: 42,
            child: Material(
              color: selected ? const Color(0xD9546E3E) : const Color(0x8C281C12),
              child: InkWell(
                onTap: onTap,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: content,
                  ),
                ),
              ),
            ),
          )
        : button;
    final labeled = semanticsLabel == null
        ? sized
        : Semantics(
            button: true,
            label: semanticsLabel,
            child: ExcludeSemantics(child: sized),
          );
    if (tooltip == null) return labeled;
    return Tooltip(message: tooltip!, child: labeled);
  }
}
