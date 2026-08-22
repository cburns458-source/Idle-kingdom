import 'package:flutter/material.dart';

/// The palette the game is drawn in: parchment, gold, and soft green.
abstract final class Palette {
  static const parchmentText = Color(0xFFF4E7C8);
  static const parchment = Color(0xFF5C4027);
  static const parchmentDeep = Color(0xFF3D2A1A);
  static const gold = Color(0xFFD4AF37);
  static const softGreen = Color(0xFF8FAF7A);
  static const ink = Color(0xFF1F1610);
  static const danger = Color(0xFFC2603F);

  /// Secondary body text, the old client's `.muted`.
  static const muted = Color(0xFFCBB894);

  /// Location and panel headings.
  static const heading = Color(0xFFFFE7A8);

  /// Body copy on top of location art.
  static const overlayText = Color(0xFFF2E6C8);

  /// Danger and combat warnings, the old client's `.danger-note`.
  static const warning = Color(0xFFEFB07A);

  /// Hairline gold used for panel edges.
  static const edge = Color(0x73D4AF37);

  /// The behind-everything wash, matching `.app-shell`.
  static const shellGradient = LinearGradient(
    begin: Alignment(-0.6, -1),
    end: Alignment(0.6, 1),
    colors: [Color(0xFF2A1B12), Color(0xFF4A3422), Color(0xFF1F1610)],
    stops: [0, 0.45, 1],
  );

  /// The frame the game is played inside, matching `.portrait-frame`.
  static const frameGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF5C4027), Color(0xFF3D2A1A)],
  );

  /// Opaque card fill for docks, tiles, and panels.
  static const panel = parchmentDeep;
}

/// Fine film grain tiled over panel fills, the HUD, and the chin.
const String panelGrainAsset = 'assets/ui/panel-grain.png';

DecorationImage panelGrainImage() => const DecorationImage(
  image: AssetImage(panelGrainAsset),
  repeat: ImageRepeat.repeat,
  fit: BoxFit.none,
  alignment: Alignment.topLeft,
  filterQuality: FilterQuality.none,
  opacity: 0.03,
);

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
      trackOutlineColor: WidgetStateProperty.all(const Color(0x73D4AF37)),
    ),
  );
}

/// Which of the two button faces to wear: green for doing, brown for the rest.
enum GameButtonTone { primary, secondary }

/// The rounded, gold-edged button the game does everything with.
class GameButton extends StatefulWidget {
  const GameButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.tone = GameButtonTone.primary,
    this.compact = false,
    this.selected = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final GameButtonTone tone;

  /// Chat tabs, keypad keys, and other tight rows.
  final bool compact;

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
    final borderColor = widget.selected
        ? Palette.gold
        : (primary ? const Color(0x73BEDC96) : const Color(0x73D4AF37));
    final button = Semantics(
      button: true,
      enabled: widget.onPressed != null,
      label: widget.label,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: widget.onPressed == null ? 0.55 : 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: primary
                  ? (down ? GameButton._primaryPressed : GameButton._primaryFill)
                  : (down ? GameButton._secondaryPressed : GameButton._secondaryFill),
              color: widget.selected ? const Color(0x33D4AF37) : null,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
              boxShadow: const [BoxShadow(offset: Offset(0, 2), color: Color(0x40000000))],
            ),
            child: InkWell(
              onTap: widget.onPressed,
              onHighlightChanged: (value) {
                if (_pressed == value) return;
                setState(() => _pressed = value);
              },
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                constraints: widget.compact
                    ? const BoxConstraints(minHeight: 32)
                    : const BoxConstraints(minHeight: 44, minWidth: 90),
                padding: widget.compact
                    ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
                    : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                alignment: Alignment.center,
                child: Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  maxLines: widget.compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: gameFontFamily,
                    fontSize: widget.compact ? 12 : 13.5,
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
        child: Material(
          color: const Color(0xFF45301F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0x73D4AF37)),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(10),
            child: SizedBox.square(
              dimension: size,
              child: Icon(icon, size: size * 0.55, color: const Color(0xFFFFF4D4)),
            ),
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
          child: Material(
            color: const Color(0xFF45301F),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0x73D4AF37)),
            ),
            child: Padding(
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
        Material(
          color: const Color(0xFF45301F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0x73D4AF37)),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
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
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
      decoration: panelFill(
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0x2EE8DCB4)),
      ),
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: trackColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
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

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      padding: padding ?? const EdgeInsets.all(12),
      decoration: panelFill(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight ? Palette.gold : Palette.edge,
          width: highlight ? 2 : 1,
        ),
      ),
      child: child,
    );
    if (onTap == null) return panel;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14), child: panel);
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Color(0x99120C08))),
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.isNaN ? 0 : value.clamp(0, 1),
                child: ColoredBox(color: color),
              ),
            ),
          ],
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
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  /// The nearby chip is brown rather than the map's parchment green.
  final bool dark;

  /// Gold rim when other players are standing here.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: dark ? Palette.panel : const Color(0xFFBADCA0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: highlight
                ? Palette.gold
                : dark
                ? const Color(0x8CD4AF5A)
                : const Color(0xB3B4DC96),
            width: highlight ? 2 : 1,
          ),
        ),
        shadowColor: const Color(0x47000000),
        elevation: 6,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(width: 60, height: 60, child: Center(child: child)),
        ),
      ),
    );
  }
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
    return Text(
      text,
      textAlign: textAlign,
      style: TextStyle(fontSize: 12.5, color: color ?? Palette.muted, height: 1.35),
    );
  }
}
