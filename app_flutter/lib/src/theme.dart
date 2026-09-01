import 'package:flutter/material.dart';

import 'pixel_chrome.dart';
export 'pixel_chrome.dart';

/// Parses a canonical `#RRGGBB` into a color, or null when it is not one.
Color? colorFromHexRgb(String? hex) {
  if (hex == null || hex.length != 7 || !hex.startsWith('#')) return null;
  final value = int.tryParse(hex.substring(1), radix: 16);
  if (value == null) return null;
  return Color(0xFF000000 | value);
}

/// The palette the game is drawn in: wood boards, tan panels, dull gold.
abstract final class Palette {
  static const parchmentText = Color(0xFFF4E7C8);
  static const parchment = Color(0xFF5C4027);
  static const parchmentDeep = Color(0xFF3D2A1A);

  /// Dull antique brass (borders, accents) — not bright jewelry gold.
  static const gold = Color(0xFF7A5F24);
  static const goldHighlight = Color(0xFF968040);
  static const goldShade = Color(0xFF3A2A0A);

  /// Outer board / wood chrome.
  static const wood = Color(0xFF2A1C12);
  static const softGreen = Color(0xFF8FAF7A);
  static const ink = Color(0xFF1F1610);
  static const danger = Color(0xFFC2603F);

  /// Secondary body text, the old client's `.muted`.
  static const muted = Color(0xFFCBB894);

  /// Muted copy on tan inner panels.
  static const panelMuted = Color(0xFF6B5338);

  /// Body ink on tan inner panels.
  static const panelInk = Color(0xFF2A1C12);

  /// Location and panel headings.
  static const heading = Color(0xFFE8D090);

  /// Body copy on top of location art.
  static const overlayText = Color(0xFFF2E6C8);

  /// Danger and combat warnings, the old client's `.danger-note`.
  static const warning = Color(0xFFEFB07A);

  /// Hairline gold used for panel edges.
  static const edge = Color(0x737A5F24);

  /// The behind-everything wash — dark wood base under the plank texture.
  static const shellGradient = LinearGradient(
    begin: Alignment(-0.6, -1),
    end: Alignment(0.6, 1),
    colors: [Color(0xFF1A120C), Color(0xFF2A1C12), Color(0xFF14100A)],
    stops: [0, 0.45, 1],
  );

  /// The frame the game is played inside — outer brown board.
  static const frameGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF3D2A1A), Color(0xFF2A1C12)],
  );

  /// Outer wood board (HUD, nav, shell chrome).
  static const board = wood;

  /// Tan inner fill for menus and content panels.
  static const panelTan = Color(0xFFC4A882);

  /// Opaque card fill for docks, tiles, and panels (tan inset).
  static const panel = panelTan;

  /// Recessed item-slot well on tan panels.
  static const slot = Color(0xFF3D2A1A);
}

/// Zoom that fills a portrait window with the bundled sprite's head.
const double playerPortraitHeadZoom = 1.72;

/// Fine film grain tiled over tan panel fills.
const String panelGrainAsset = 'assets/ui/panel-grain.png';

/// Horizontal wood-plank texture for outer boards and the main background.
const String woodPanelAsset = 'assets/ui/wood-panel.png';

DecorationImage panelGrainImage({double opacity = 0.12}) => DecorationImage(
  image: const AssetImage(panelGrainAsset),
  repeat: ImageRepeat.repeat,
  fit: BoxFit.none,
  alignment: Alignment.topLeft,
  filterQuality: FilterQuality.none,
  opacity: opacity,
);

DecorationImage woodPanelImage({double opacity = 1}) => DecorationImage(
  image: const AssetImage(woodPanelAsset),
  repeat: ImageRepeat.repeat,
  fit: BoxFit.none,
  alignment: Alignment.topLeft,
  filterQuality: FilterQuality.none,
  opacity: opacity,
);

/// Tan inner panel fill (menus, content plates).
BoxDecoration panelFill({
  Color color = Palette.panel,
  BorderRadius? borderRadius,
  BoxBorder? border,
}) {
  return BoxDecoration(
    color: color,
    borderRadius: borderRadius,
    border: border,
    image: panelGrainImage(),
  );
}

/// Dark wood outer board (HUD strip, nav chin, shell).
BoxDecoration woodBoardFill({
  Color color = Palette.board,
  BorderRadius? borderRadius,
  BoxBorder? border,
  double textureOpacity = 1,
}) {
  return BoxDecoration(
    color: color,
    borderRadius: borderRadius,
    border: border,
    image: woodPanelImage(opacity: textureOpacity),
  );
}

/// Shell / loading / frame wash: wood planks as the dominant outer board.
BoxDecoration woodShellDecoration({Gradient? gradient}) {
  return BoxDecoration(color: Palette.board, gradient: gradient, image: woodPanelImage(opacity: 1));
}

/// The bar fills, each one a three-stop gradient as the old client drew them.
abstract final class Meters {
  static const playerHp = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFC5E08A), Color(0xFF7FAD45), Color(0xFF5E8A2F)],
    stops: [0, 0.55, 1],
  );

  static const enemyHp = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF0C090), Color(0xFFD4844A), Color(0xFFA85A2A)],
    stops: [0, 0.55, 1],
  );

  static const combatRound = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFD8ECFF), Color(0xFF7EB6E8), Color(0xFF4A8EC8)],
    stops: [0, 0.55, 1],
  );

  static const action = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFE8F6C8), Color(0xFF9BC85A), Color(0xFF6A9A35)],
    stops: [0, 0.55, 1],
  );

  static const hudHp = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF2F6B3A), Color(0xFF4F9A55), Color(0xFF8FCE6B)],
    stops: [0, 0.45, 1],
  );
}

/// Text laid over location art, which needs its own shadow to stay readable.
const List<Shadow> overlayShadow = [
  Shadow(offset: Offset(0, 1), blurRadius: 2, color: Color(0x8C000000)),
];

const String gameFontFamily = 'PixeloidSans';

/// Combat and gathering warnings.
const TextStyle warningStyle = TextStyle(
  fontFamily: gameFontFamily,
  color: Palette.warning,
  fontSize: 13,
  fontWeight: FontWeight.w400,
  height: 1.35,
  shadows: overlayShadow,
);

/// Pixeloid Sans Regular is the UI cut. Force every role onto that weight.
TextTheme _regularGameText(TextTheme theme) {
  TextStyle? regular(TextStyle? style) {
    return style?.copyWith(fontFamily: gameFontFamily, fontWeight: FontWeight.w400);
  }

  return TextTheme(
    displayLarge: regular(theme.displayLarge),
    displayMedium: regular(theme.displayMedium),
    displaySmall: regular(theme.displaySmall),
    headlineLarge: regular(theme.headlineLarge),
    headlineMedium: regular(theme.headlineMedium),
    headlineSmall: regular(theme.headlineSmall),
    titleLarge: regular(theme.titleLarge),
    titleMedium: regular(theme.titleMedium),
    titleSmall: regular(theme.titleSmall),
    bodyLarge: regular(theme.bodyLarge),
    bodyMedium: regular(theme.bodyMedium),
    bodySmall: regular(theme.bodySmall),
    labelLarge: regular(theme.labelLarge),
    labelMedium: regular(theme.labelMedium),
    labelSmall: regular(theme.labelSmall),
  );
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: gameFontFamily,
    scaffoldBackgroundColor: Palette.ink,
  );
  final textTheme = _regularGameText(
    base.textTheme.apply(
      fontFamily: gameFontFamily,
      bodyColor: Palette.parchmentText,
      displayColor: Palette.parchmentText,
    ),
  );
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: Palette.gold,
      onPrimary: Palette.ink,
      secondary: Palette.softGreen,
      surface: Palette.parchmentDeep,
      onSurface: Palette.parchmentText,
      error: Palette.danger,
    ),
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    dividerColor: Palette.edge,
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected) ? const Color(0xFFF4FFE8) : Palette.muted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? const Color(0xFF5F7A45)
            : const Color(0xFF45301F);
      }),
      trackOutlineColor: WidgetStateProperty.all(const Color(0x739A7B32)),
    ),
  );
}

/// Which of the two button faces to wear: green for doing, brown for the rest.
enum GameButtonTone { primary, secondary }

/// The stepped, gold-embossed pixel button the game does everything with.
class GameButton extends StatefulWidget {
  const GameButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.tone = GameButtonTone.primary,
    this.compact = false,
    this.dense = false,
    this.selected = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final GameButtonTone tone;

  /// Chat tabs, keypad keys, and other tight rows.
  final bool compact;

  /// Smaller than [compact] — header chips such as Sell items.
  final bool dense;

  /// Gold wash for the active tab or conversation.
  final bool selected;

  final String? tooltip;

  static const LinearGradient _primaryFill = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF7F9D63), Color(0xFF5F7A45)],
  );

  static const LinearGradient _primaryPressed = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF5A7044), Color(0xFF3F522E)],
  );

  static const LinearGradient _secondaryFill = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF6A4A30), Color(0xFF45301F)],
  );

  static const LinearGradient _secondaryPressed = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF4A3422), Color(0xFF2F2115)],
  );

  @override
  State<GameButton> createState() => _GameButtonState();
}

class _GameButtonState extends State<GameButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final primary = widget.tone == GameButtonTone.primary;
    final down = _pressed && widget.onPressed != null;
    final button = Semantics(
      button: true,
      enabled: widget.onPressed != null,
      label: widget.label,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: widget.onPressed == null ? 0.55 : 1,
          child: PixelInkPlate(
            onTap: widget.onPressed,
            onHighlightChanged: (value) {
              if (_pressed == value) return;
              setState(() => _pressed = value);
            },
            selected: widget.selected,
            step: widget.dense ? PixelChrome.stepTight : PixelChrome.step,
            strokeWidth: widget.selected ? 2.5 : 2,
            shadow: false,
            gradient: primary
                ? (down ? GameButton._primaryPressed : GameButton._primaryFill)
                : (down ? GameButton._secondaryPressed : GameButton._secondaryFill),
            fillColor: widget.selected ? const Color(0x339A7B32) : null,
            padding: widget.dense
                ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                : widget.compact
                ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
                : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: ConstrainedBox(
              constraints: widget.dense
                  ? const BoxConstraints(minHeight: 26)
                  : widget.compact
                  ? const BoxConstraints(minHeight: 32)
                  : const BoxConstraints(minHeight: 44, minWidth: 90),
              child: Align(
                alignment: Alignment.center,
                child: Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  maxLines: widget.compact || widget.dense ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: gameFontFamily,
                    fontSize: widget.dense
                        ? 11
                        : widget.compact
                        ? 12
                        : 13.5,
                    fontWeight: FontWeight.w400,
                    color: primary ? const Color(0xFFF4FFE8) : const Color(0xFFFFF4D4),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip == null) return button;
    return Tooltip(message: widget.tooltip!, child: button);
  }
}

/// Small gold-edged icon chip for panel closes and keypad extras.
class GameIconButton extends StatelessWidget {
  const GameIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 32,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final chip = Semantics(
      button: true,
      enabled: onPressed != null,
      label: tooltip,
      child: Opacity(
        opacity: onPressed == null ? 0.55 : 1,
        child: PixelInkPlate(
          onTap: onPressed,
          step: PixelChrome.stepTight,
          fillColor: const Color(0xFF45301F),
          strokeWidth: 1.5,
          shadow: false,
          child: SizedBox.square(
            dimension: size,
            child: Icon(icon, size: size * 0.55, color: const Color(0xFFFFF4D4)),
          ),
        ),
      ),
    );
    if (tooltip == null) return chip;
    return Tooltip(message: tooltip!, child: chip);
  }
}

/// One line in a [GameDropdown].
class GameDropdownItem<T> {
  const GameDropdownItem({required this.value, required this.label, this.enabled = true});

  final T value;
  final String label;
  final bool enabled;
}

/// One-line field that expands a local menu, not a separate catalog popup.
class GameDropdown<T> extends StatelessWidget {
  const GameDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<GameDropdownItem<T>> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = items.where((item) => item.value == value).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MutedText(label),
        const SizedBox(height: 4),
        PopupMenuButton<T>(
          tooltip: label,
          enabled: items.isNotEmpty,
          color: Palette.parchmentDeep,
          offset: const Offset(0, 8),
          constraints: const BoxConstraints(minWidth: 220, maxWidth: 360),
          onSelected: onChanged,
          itemBuilder: (context) => [
            for (final item in items)
              PopupMenuItem<T>(
                value: item.value,
                enabled: item.enabled,
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontFamily: gameFontFamily,
                    fontWeight: FontWeight.w400,
                    color: item.enabled ? Palette.parchmentText : Palette.muted,
                  ),
                ),
              ),
          ],
          child: PixelPlate(
            step: PixelChrome.stepTight,
            fillColor: const Color(0xFF45301F),
            strokeWidth: 1.5,
            shadow: false,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selected?.label ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: gameFontFamily,
                      fontWeight: FontWeight.w400,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                const Icon(Icons.expand_more, size: 20, color: Palette.gold),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One-line field that opens a catalog popup instead of a Material dropdown.
class GameSelectField extends StatelessWidget {
  const GameSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final String label;
  final String value;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MutedText(label),
        const SizedBox(height: 4),
        PixelInkPlate(
          onTap: onPressed,
          step: PixelChrome.stepTight,
          fillColor: const Color(0xFF45301F),
          strokeWidth: 1.5,
          shadow: false,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: gameFontFamily,
                    fontWeight: FontWeight.w400,
                    fontSize: 13.5,
                  ),
                ),
              ),
              const Icon(Icons.expand_more, size: 20, color: Palette.gold),
            ],
          ),
        ),
      ],
    );
  }
}

/// Parchment toggle used on Settings.
class GameSwitch extends StatelessWidget {
  const GameSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Switch(value: value, onChanged: onChanged);
  }
}

/// One line of the location list: what is here, and the one thing you do with it.
class DockRow extends StatelessWidget {
  const DockRow({
    super.key,
    required this.title,
    required this.trailing,
    this.leading,
    this.lines = const [],
  });

  final String title;

  /// Optional control before the title — the favorite star on an activity.
  final Widget? leading;

  /// Warnings, requirements, and the blurb, in the order the old client read them.
  final List<Widget> lines;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return PixelPlate(
      step: PixelChrome.step,
      fillColor: Palette.slot,
      material: PixelPlateMaterial.wood,
      strokeWidth: 1.5,
      shadow: false,
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
      child: Row(
        children: [
          if (leading case final star?) ...[star, const SizedBox(width: 6)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w400,
                    shadows: overlayShadow,
                  ),
                ),
                ...lines,
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing,
        ],
      ),
    );
  }
}

/// A pill meter with a gradient fill, the shape every bar in the game uses.
///
/// The track is always the full width it was given. Only the fill shrinks, so
/// half health reads as a half-full bar rather than a shorter one.
class PillBar extends StatelessWidget {
  const PillBar({
    super.key,
    required this.value,
    required this.gradient,
    this.height = 12,
    this.trackColor = const Color(0xB8120C08),
    this.borderColor = const Color(0x47FFECC4),
  });

  final double value;
  final Gradient gradient;
  final double height;
  final Color trackColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final fill = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return SizedBox(
      width: double.infinity,
      height: height,
      child: PixelPlate(
        step: PixelChrome.stepTight,
        fillColor: trackColor,
        strokeWidth: 1.5,
        shadow: false,
        child: ClipPath(
          clipper: _MeterFillClipper(step: PixelChrome.stepTight),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fill,
            heightFactor: 1,
            child: DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
          ),
        ),
      ),
    );
  }
}

/// The bordered, slightly translucent card every panel in the game uses.
class GamePanel extends StatelessWidget {
  const GamePanel({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.highlight = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  /// Gold, thicker edge for the viewer's own leaderboard row.
  final bool highlight;

  Widget _inked(Widget plateChild) {
    // Tan inner panels read with dark ink; overlays keep their own colors.
    return DefaultTextStyle.merge(
      style: const TextStyle(color: Palette.panelInk, fontFamily: gameFontFamily),
      child: IconTheme.merge(
        data: const IconThemeData(color: Palette.panelInk),
        child: plateChild,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (onTap != null) {
      return PixelInkPlate(
        onTap: onTap,
        step: PixelChrome.step,
        fillColor: Palette.panel,
        material: PixelPlateMaterial.tan,
        strokeWidth: highlight ? 2.5 : 2,
        selected: highlight,
        shadow: false,
        padding: padding ?? const EdgeInsets.all(12),
        child: _inked(child),
      );
    }
    return PixelPlate(
      step: PixelChrome.step,
      fillColor: Palette.panel,
      material: PixelPlateMaterial.tan,
      strokeWidth: highlight ? 2.5 : 2,
      selected: highlight,
      rivets: highlight,
      shadow: false,
      padding: padding ?? const EdgeInsets.all(12),
      child: _inked(child),
    );
  }
}

/// A thin rounded bar: action progress, HP, skill xp, travel.
///
/// Both layers are `Positioned.fill` because a bare `ColoredBox` in a `Stack`
/// has no child to size to, and would collapse to nothing.
class MeterBar extends StatelessWidget {
  const MeterBar({super.key, required this.value, required this.color, this.height = 8});

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: PixelPlate(
        step: 1,
        fillColor: const Color(0x99120C08),
        strokeWidth: 1,
        shadow: false,
        child: ClipPath(
          clipper: _MeterFillClipper(step: 1),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.isNaN ? 0 : value.clamp(0, 1),
            child: ColoredBox(color: color),
          ),
        ),
      ),
    );
  }
}

/// The map / nearby chips that sit on location art and the map overlay.
class OverlayChipButton extends StatelessWidget {
  const OverlayChipButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.dark = false,
    this.highlight = false,
    this.highlightColor,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  /// The nearby chip is brown rather than the map's parchment green.
  final bool dark;

  /// Gold when strangers are here, green when a friend or guildmate is.
  final bool highlight;

  /// Overrides [highlight] when the nearby chip should be green instead of gold.
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    final rim = highlightColor ?? (highlight ? Palette.gold : null);
    final side = BorderSide(
      color: rim ?? (dark ? const Color(0x8C9A7B32) : const Color(0xB3B4DC96)),
      width: rim != null ? 2 : 1,
    );
    return Tooltip(
      message: tooltip,
      child: Material(
        color: dark ? Palette.slot : const Color(0xFFBADCA0),
        elevation: 6,
        shadowColor: const Color(0x47000000),
        shape: PixelSteppedBorder(step: PixelChrome.step, side: side),
        child: InkWell(
          onTap: onPressed,
          customBorder: PixelSteppedBorder(step: PixelChrome.step),
          child: SizedBox(width: 60, height: 60, child: Center(child: child)),
        ),
      ),
    );
  }
}

/// Slow red rim for a quest travel hint.
class QuestHintPulse extends StatefulWidget {
  const QuestHintPulse({
    super.key,
    required this.enabled,
    required this.child,
    this.circle = false,
  });

  final bool enabled;
  final Widget child;
  final bool circle;

  @override
  State<QuestHintPulse> createState() => _QuestHintPulseState();
}

class _QuestHintPulseState extends State<QuestHintPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    if (widget.enabled) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(QuestHintPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.enabled && _controller.isAnimating) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final tint = Color.lerp(
          const Color(0x00B42318),
          const Color(0xE6B42318),
          _controller.value,
        )!;
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: widget.circle ? null : BorderRadius.zero,
            border: Border.all(color: tint, width: 2),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Clips meter fills to the same stair outline as [PixelPlate].
class _MeterFillClipper extends CustomClipper<Path> {
  const _MeterFillClipper({required this.step});

  final double step;

  @override
  Path getClip(Size size) => PixelChrome.steppedPath(Offset.zero & size, step: step);

  @override
  bool shouldReclip(covariant _MeterFillClipper oldClipper) => oldClipper.step != step;
}

/// Small muted caption, the equivalent of the CSS `.muted.tiny` pairing.
class MutedText extends StatelessWidget {
  const MutedText(this.text, {super.key, this.textAlign, this.color});

  final String text;
  final TextAlign? textAlign;

  /// Override when the surface is [Palette.muted] itself (wardrobe).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final inherited = DefaultTextStyle.of(context).style.color;
    final onTan = inherited != null && inherited.computeLuminance() < 0.45;
    return Text(
      text,
      textAlign: textAlign,
      style: TextStyle(
        fontSize: 12.5,
        color: color ?? (onTan ? Palette.panelMuted : Palette.muted),
        height: 1.35,
      ),
    );
  }
}
