import 'package:flutter/material.dart';
import 'package:pixel_ui/pixel_ui.dart';

import '../theme.dart';

/// pixel_ui styles in the game's parchment colours, for the location dock only.

const PixelShapeStyle pixelPanelStyle = PixelShapeStyle(
  corners: PixelCorners.sm,
  fillColor: Color(0xCC231710),
  borderColor: Palette.gold,
  borderWidth: 1,
);

const PixelShapeStyle pixelButtonStyle = PixelShapeStyle(
  corners: PixelCorners.xs,
  fillColor: Palette.gold,
  borderColor: Color(0xFF8A6A18),
  borderWidth: 1,
  shadow: PixelShadow(offset: Offset(1, 1), color: Color(0xFF1A1208)),
);

const PixelShapeStyle pixelButtonPressedStyle = PixelShapeStyle(
  corners: PixelCorners.xs,
  fillColor: Color(0xFFC49A2A),
  borderColor: Color(0xFF8A6A18),
  borderWidth: 1,
);

const PixelShapeStyle pixelStopButtonStyle = PixelShapeStyle(
  corners: PixelCorners.xs,
  fillColor: Color(0xFF5C4027),
  borderColor: Palette.gold,
  borderWidth: 1,
);

/// A parchment [PixelBox] that stretches to the incoming width.
class PixelFill extends StatelessWidget {
  const PixelFill({super.key, required this.child, this.padding, this.height = 64});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0;
        return PixelBox(
          logicalWidth: 160,
          logicalHeight: 28,
          width: width,
          height: height,
          style: pixelPanelStyle,
          padding: padding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          alignment: Alignment.centerLeft,
          child: child,
        );
      },
    );
  }
}

/// Start / Recipes / Shop — the gold pixel chip.
class PixelActionButton extends StatelessWidget {
  const PixelActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.stop = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool stop;

  @override
  Widget build(BuildContext context) {
    return PixelButton(
      logicalWidth: 26,
      logicalHeight: 10,
      width: 92,
      height: 36,
      normalStyle: stop ? pixelStopButtonStyle : pixelButtonStyle,
      pressedStyle: pixelButtonPressedStyle,
      onPressed: onPressed,
      semanticsLabel: label,
      child: Text(
        label,
        style: PixelText.mulmaru(fontSize: 11, color: stop ? Palette.parchmentText : Palette.ink),
      ),
    );
  }
}

/// A pixel-bordered meter. The fill is still a fraction of the inner track.
class PixelMeterBar extends StatelessWidget {
  const PixelMeterBar({super.key, required this.value, required this.color, this.height = 10});

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 200.0;
        return PixelBox(
          logicalWidth: 80,
          logicalHeight: 6,
          width: width,
          height: height,
          style: const PixelShapeStyle(
            corners: PixelCorners.xs,
            fillColor: Color(0xE0120C08),
            borderColor: Color(0x73FFECC4),
            borderWidth: 1,
          ),
          padding: const EdgeInsets.all(2),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.isNaN ? 0 : value.clamp(0, 1),
            heightFactor: 1,
            child: ColoredBox(color: color),
          ),
        );
      },
    );
  }
}

TextStyle pixelCaption({Color color = Palette.parchmentText, double fontSize = 12}) {
  return PixelText.mulmaru(fontSize: fontSize, color: color, shadowColor: const Color(0xCC000000));
}
