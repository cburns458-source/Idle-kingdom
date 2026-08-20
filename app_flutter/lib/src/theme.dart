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

/// Combat and gathering warnings.
const TextStyle warningStyle = TextStyle(
  color: Palette.warning,
  fontSize: 13,
  fontWeight: FontWeight.w600,
  height: 1.35,
  shadows: overlayShadow,
);

ThemeData buildAppTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final themed = base.copyWith(
    scaffoldBackgroundColor: Palette.ink,
    colorScheme: base.colorScheme.copyWith(
      primary: Palette.gold,
      onPrimary: Palette.ink,
      secondary: Palette.softGreen,
      surface: Palette.parchmentDeep,
      onSurface: Palette.parchmentText,
      error: Palette.danger,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: Palette.parchmentText,
      displayColor: Palette.parchmentText,
    ),
    dividerColor: Palette.edge,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.gold,
        foregroundColor: Palette.ink,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.parchmentText,
        side: const BorderSide(color: Palette.edge),
        shape: const StadiumBorder(),
      ),
    ),
  );
  return themed;
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
  });

  final String label;
  final VoidCallback? onPressed;
  final GameButtonTone tone;

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
    return Semantics(
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
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: primary ? const Color(0x73BEDC96) : const Color(0x73D4AF37),
              ),
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
                constraints: const BoxConstraints(minHeight: 44, minWidth: 90),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                alignment: Alignment.center,
                child: Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: primary ? const Color(0xFFF4FFE8) : const Color(0xFFFFF4D4),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
      decoration: BoxDecoration(
        color: Palette.panel,
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
                    fontWeight: FontWeight.w700,
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
  const GamePanel({super.key, required this.child, this.padding, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.edge),
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
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  /// The nearby chip is brown rather than the map's parchment green.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: dark ? Palette.panel : const Color(0xFFBADCA0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: dark ? const Color(0x8CD4AF5A) : const Color(0xB3B4DC96)),
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
