import 'dart:async';

import 'package:flutter/material.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'app_shell.dart';
import 'game_image.dart';
import 'notification_bubble.dart';

const double _chinIconSize = 32;

/// Settings / Bazaar / Leaderboards / Guilds — the hamburger nest and the
/// desktop rail. Log lives on the chin. The Bazaar is here rather than at a
/// location because an offer on the book fills wherever its owner happens to be
/// standing.
const List<(GameScreen, String)> nestMenuItems = [
  (GameScreen.menu, 'Settings'),
  (GameScreen.codex, 'Codex'),
  (GameScreen.timers, 'Timers'),
  (GameScreen.bazaar, 'Bazaar'),
  (GameScreen.leaderboards, 'Leaderboards'),
  (GameScreen.guilds, 'Guilds'),
];

final Set<GameScreen> nestMenuScreens = {for (final item in nestMenuItems) item.$1};

/// Chin height. Icon tabs are tall; the location chip stays narrower.
const double chinHeight = 60;

/// The chin: bag, skills, where you are, the log, and the nest.
class BottomNav extends StatefulWidget {
  const BottomNav({
    super.key,
    required this.screen,
    required this.locationName,
    required this.onSelect,
    required this.controller,
    required this.multiplayer,
    this.nowMs,
    this.showMenu = true,
  });

  final GameScreen screen;
  final String locationName;
  final ValueChanged<GameScreen> onSelect;
  final GameController controller;
  final MultiplayerController multiplayer;
  final num Function()? nowMs;

  /// When false, the hamburger is omitted (desktop rails own those pages).
  final bool showMenu;

  @override
  State<BottomNav> createState() => _BottomNavState();
}

class _BottomNavState extends State<BottomNav> {
  final LayerLink _nestLink = LayerLink();
  OverlayEntry? _nestEntry;
  Timer? _ticker;

  bool get _nestOpen => _nestEntry != null;
  bool get _nestActive => _nestOpen || nestMenuScreens.contains(widget.screen);

  num _clock() => widget.nowMs?.call() ?? widget.controller.session.clock();

  int get _timerReady => timerReadyBadgeCount(widget.controller.save, _clock());

  int get _bazaarReady => bazaarReadyBadgeCount(widget.multiplayer.market);

  int get _menuReady => _timerReady + _bazaarReady;

  int _badgeFor(GameScreen screen) {
    return switch (screen) {
      GameScreen.timers => _timerReady,
      GameScreen.bazaar => _bazaarReady,
      _ => 0,
    };
  }

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      _nestEntry?.markNeedsBuild();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
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
    final chrome = UiChrome.of(context);
    final entry = OverlayEntry(
      builder: (overlayContext) =>
          UiChromeScope(chrome: chrome, child: _buildNestOverlay(overlayContext)),
    );
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
            badgeFor: _badgeFor,
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

  static const _divider = VerticalDivider(width: 1, color: Palette.edge);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[widget.controller, widget.multiplayer]),
      builder: (context, _) => DecoratedBox(
        decoration: chromeBarFill(
          context,
          border: const Border(top: BorderSide(color: Palette.edge)),
        ),
        child: SizedBox(
          height: chinHeight,
          child: Row(
            children: [
              Expanded(
                child: _NavSection(
                  selected: widget.screen == GameScreen.character,
                  tooltip: 'Inventory',
                  semanticsLabel: 'Inventory',
                  onTap: () => _selectTab(GameScreen.character),
                  child: GameImage(
                    uiInventoryAssetPath(),
                    width: _chinIconSize,
                    height: _chinIconSize,
                  ),
                ),
              ),
              _divider,
              Expanded(
                child: _NavSection(
                  selected: widget.screen == GameScreen.skills,
                  tooltip: 'Skills',
                  semanticsLabel: 'Skills',
                  onTap: () => _selectTab(GameScreen.skills),
                  child: GameImage(uiStatsAssetPath(), width: _chinIconSize, height: _chinIconSize),
                ),
              ),
              _divider,
              Expanded(
                child: _NavSection(
                  label: widget.locationName,
                  selected: widget.screen == GameScreen.location,
                  tooltip: widget.locationName,
                  onTap: () => _selectTab(GameScreen.location),
                ),
              ),
              _divider,
              Expanded(
                child: _NavSection(
                  selected: widget.screen == GameScreen.log,
                  tooltip: 'Log',
                  semanticsLabel: 'Log',
                  onTap: () => _selectTab(GameScreen.log),
                  child: GameImage(uiLogAssetPath(), width: _chinIconSize, height: _chinIconSize),
                ),
              ),
              if (widget.showMenu) ...[
                _divider,
                Expanded(
                  child: CompositedTransformTarget(
                    link: _nestLink,
                    child: _NavSection(
                      selected: _nestActive,
                      tooltip: 'Open menu',
                      semanticsLabel: _menuReady > 0
                          ? 'Open menu, $_menuReady waiting'
                          : 'Open menu',
                      onTap: _toggleNest,
                      child: Badged(
                        count: _menuReady,
                        child: GameImage(
                          uiMenuAssetPath(),
                          width: _chinIconSize,
                          height: _chinIconSize,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NestPopup extends StatelessWidget {
  const _NestPopup({required this.screen, required this.onSelect, required this.badgeFor});

  final GameScreen screen;
  final ValueChanged<GameScreen> onSelect;
  final int Function(GameScreen screen) badgeFor;

  @override
  Widget build(BuildContext context) {
    final chrome = UiChrome.of(context);
    return Material(
      color: chrome.board,
      elevation: 12,
      shadowColor: const Color(0x73000000),
      shape: PixelSteppedBorder(
        step: 3,
        side: BorderSide(color: chrome.embossFace.withValues(alpha: 0.7)),
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
                for (final item in nestMenuItems)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _NavSection(
                      label: item.$2,
                      selected: screen == item.$1,
                      alignStart: true,
                      badge: badgeFor(item.$1),
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
    this.badge = 0,
  }) : assert(label != null || child != null);

  final String? label;
  final Widget? child;
  final bool selected;
  final VoidCallback onTap;
  final String? tooltip;
  final String? semanticsLabel;
  final bool alignStart;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final labelText = label == null
        ? null
        : Text(
            label!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: alignStart ? TextAlign.left : TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
          );
    final content =
        child ??
        (badge > 0 && labelText != null
            ? Row(
                children: [
                  Expanded(child: labelText),
                  NotificationBubble(count: badge),
                ],
              )
            : labelText!);
    final button = Material(
      color: selected ? const Color(0xD9546E3E) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.expand(
          child: Align(
            alignment: alignStart ? Alignment.centerLeft : Alignment.center,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: content),
          ),
        ),
      ),
    );
    final sized = alignStart
        ? SizedBox(
            height: 36,
            child: DecoratedBox(
              decoration: chromeSlotFill(
                context,
                color: selected ? const Color(0xD9546E3E) : UiChrome.of(context).slot,
              ),
              child: Material(
                color: Colors.transparent,
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
