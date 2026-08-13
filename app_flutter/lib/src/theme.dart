import 'package:flutter/material.dart';

/// The palette the React client uses, so both look like the same game.
abstract final class Palette {
  static const parchmentText = Color(0xFFF4E7C8);
  static const parchment = Color(0xFF5C4027);
  static const parchmentDeep = Color(0xFF3D2A1A);
  static const gold = Color(0xFFD4AF37);
  static const softGreen = Color(0xFF8FAF7A);
  static const ink = Color(0xFF1F1610);
  static const danger = Color(0xFFC2603F);

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
    colors: [Color(0xF05C4027), Color(0xF83D2A1A)],
  );
}

ThemeData buildAppTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
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
        color: const Color(0x66231710),
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

/// Small muted caption, the equivalent of the CSS `.muted.tiny` pairing.
class MutedText extends StatelessWidget {
  const MutedText(this.text, {super.key, this.textAlign});

  final String text;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: textAlign,
      style: const TextStyle(fontSize: 12, color: Color(0xB3F4E7C8)),
    );
  }
}
