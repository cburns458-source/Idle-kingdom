import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'session/ui_chrome.dart';

/// Wood + gold embossed pixel chrome (photo-2 direction).
///
/// Corners are square. [step] is kept for rivet inset spacing and call-site
/// compatibility; it no longer shapes the outline.
abstract final class PixelChrome {
  /// Default border inset unit for rivets / legacy call sites.
  static const double step = 3;

  /// Tighter inset for compact chips / icon buttons.
  static const double stepTight = 2;

  /// Gold emboss face — the same mid gold as [Palette.gold].
  static const Color goldFace = Color(0xFFA7872D);

  /// Soft top-left highlight on embossed borders.
  static const Color goldHighlight = Color(0xFFBFA445);

  /// Bottom-right shade on embossed gold borders.
  static const Color goldShade = Color(0xFF5A420E);

  /// Dark wood plate under gold rims.
  static const Color wood = Color(0xFF2A1C12);

  /// Square rectangle path for [rect] ([step] ignored).
  static Path steppedPath(Rect rect, {double step = step}) {
    return Path()..addRect(rect);
  }
}

/// Outlined stair-corner shape for [Material] / [InkWell.customBorder].
class PixelSteppedBorder extends OutlinedBorder {
  const PixelSteppedBorder({this.step = PixelChrome.step, super.side});

  final double step;

  @override
  PixelSteppedBorder copyWith({BorderSide? side, double? step}) {
    return PixelSteppedBorder(side: side ?? this.side, step: step ?? this.step);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return PixelChrome.steppedPath(rect.deflate(side.strokeInset), step: step);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return PixelChrome.steppedPath(rect, step: step);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    final paint = side.toPaint()..style = PaintingStyle.stroke;
    canvas.drawRect(rect.deflate(side.strokeAlign == BorderSide.strokeAlignInside ? side.strokeWidth / 2 : 0), paint);
  }

  @override
  ShapeBorder scale(double t) => PixelSteppedBorder(side: side.scale(t), step: step * t);

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(math.max(side.strokeInset, 0));

  @override
  bool operator ==(Object other) {
    return other is PixelSteppedBorder && other.side == side && other.step == step;
  }

  @override
  int get hashCode => Object.hash(side, step);
}

/// Paints a multi-tone gold emboss stroke along a stepped path.
class _EmbossBorderPainter extends CustomPainter {
  const _EmbossBorderPainter({
    required this.step,
    required this.strokeWidth,
    required this.face,
    required this.highlight,
    required this.shade,
    this.selected = false,
  });

  final double step;
  final double strokeWidth;
  final Color face;
  final Color highlight;
  final Color shade;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rect = (Offset.zero & size).deflate(inset);

    final shadePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = shade
      ..strokeJoin = StrokeJoin.miter;

    final facePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, strokeWidth - 0.5)
      ..color = face
      ..strokeJoin = StrokeJoin.miter;

    final light = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = highlight
      ..strokeJoin = StrokeJoin.miter;

    canvas
      ..save()
      ..translate(0.8, 0.8)
      ..drawRect(rect, shadePaint)
      ..restore()
      ..drawRect(rect, facePaint);

    // Subtle top + left lift — muted so borders stay matte, not shiny.
    final highlightPath = Path()
      ..moveTo(inset, inset)
      ..lineTo(size.width - inset, inset)
      ..moveTo(inset, inset)
      ..lineTo(inset, size.height - inset);
    canvas.drawPath(highlightPath, light);
  }

  @override
  bool shouldRepaint(covariant _EmbossBorderPainter oldDelegate) {
    return oldDelegate.step != step ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.selected != selected ||
        oldDelegate.face != face ||
        oldDelegate.highlight != highlight ||
        oldDelegate.shade != shade;
  }
}

/// Optional corner rivets (photo-2 studs), drawn inside the plate.
class _RivetPainter extends CustomPainter {
  const _RivetPainter({required this.step, required this.fill, required this.shade});

  final double step;
  final Color fill;
  final Color shade;

  @override
  void paint(Canvas canvas, Size size) {
    const rivet = 3.0;
    final inset = step + 3;
    final centers = <Offset>[
      Offset(inset, inset),
      Offset(size.width - inset, inset),
      Offset(inset, size.height - inset),
      Offset(size.width - inset, size.height - inset),
    ];
    final fillPaint = Paint()..color = fill;
    final shadePaint = Paint()..color = shade;
    for (final c in centers) {
      canvas.drawRect(
        Rect.fromCenter(center: c.translate(0.5, 0.5), width: rivet, height: rivet),
        shadePaint,
      );
      canvas.drawRect(Rect.fromCenter(center: c, width: rivet, height: rivet), fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RivetPainter oldDelegate) {
    return oldDelegate.step != step || oldDelegate.fill != fill || oldDelegate.shade != shade;
  }
}

/// Fill material for [PixelPlate] — wood outer boards vs tan inner panels.
enum PixelPlateMaterial { auto, wood, tan, grain, none }

/// Wood plate with square corners and optional gold emboss rim.
class PixelPlate extends StatelessWidget {
  const PixelPlate({
    super.key,
    required this.child,
    this.step = PixelChrome.step,
    this.fillColor,
    this.gradient,
    this.padding,
    this.strokeWidth = 2,
    this.selected = false,
    this.rivets = false,
    this.shadow = true,
    this.clip = true,
    this.emboss = true,
    this.material = PixelPlateMaterial.auto,
  });

  final Widget child;
  final double step;
  final Color? fillColor;
  final Gradient? gradient;
  final EdgeInsetsGeometry? padding;
  final double strokeWidth;
  final bool selected;
  final bool rivets;
  final bool shadow;
  final bool clip;

  /// When false, skips the gold emboss stroke (buttons / small controls).
  final bool emboss;
  final PixelPlateMaterial material;

  DecorationImage? _texture(BuildContext context) {
    if (fillColor == null && gradient == null) return null;
    // Auto: panel texture on light fills; dark wells get the same grain as
    // buttons and slots. [none] stays a true flat fill.
    final kind = material == PixelPlateMaterial.auto
        ? ((fillColor != null && fillColor!.computeLuminance() > 0.28)
              ? PixelPlateMaterial.tan
              : PixelPlateMaterial.grain)
        : material;
    final chrome = UiChrome.of(context);
    return switch (kind) {
      PixelPlateMaterial.wood => chrome.boardFillImage(opacity: 0.45),
      PixelPlateMaterial.tan => chrome.panelPlateImage(),
      PixelPlateMaterial.grain => chrome.buttonGrainImage(),
      PixelPlateMaterial.none => null,
      PixelPlateMaterial.auto => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final chrome = UiChrome.of(context);
    final shape = PixelSteppedBorder(step: step);
    Widget content = child;
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }

    Widget plate = rivets
        ? CustomPaint(
            painter: _RivetPainter(step: step, fill: chrome.rivetFill, shade: chrome.rivetShade),
            child: content,
          )
        : content;
    if (emboss) {
      plate = CustomPaint(
        foregroundPainter: _EmbossBorderPainter(
          step: step,
          strokeWidth: strokeWidth,
          selected: selected,
          face: selected ? chrome.embossFaceSelected : chrome.embossFace,
          highlight: selected ? chrome.embossHighlightSelected : chrome.embossHighlight,
          shade: selected ? chrome.embossShadeSelected : chrome.embossShade,
        ),
        child: plate,
      );
    }

    if (clip) {
      plate = ClipRect(
        child: DecoratedBox(
          decoration: BoxDecoration(color: fillColor, gradient: gradient, image: _texture(context)),
          child: plate,
        ),
      );
    }

    if (!shadow) return plate;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape.copyWith(side: BorderSide.none),
        shadows: const [BoxShadow(offset: Offset(2, 2), color: Color(0x66000000))],
      ),
      child: plate,
    );
  }
}

/// Public stair clipper for feature screens that still paint their own plates.
class PixelSteppedClipper extends CustomClipper<Path> {
  const PixelSteppedClipper({this.step = PixelChrome.step});

  final double step;

  @override
  Path getClip(Size size) => PixelChrome.steppedPath(Offset.zero & size, step: step);

  @override
  bool shouldReclip(covariant PixelSteppedClipper oldClipper) => oldClipper.step != step;
}

class _SteppedClipper extends CustomClipper<Path> {
  const _SteppedClipper({required this.step});

  final double step;

  @override
  Path getClip(Size size) => PixelChrome.steppedPath(Offset.zero & size, step: step);

  @override
  bool shouldReclip(covariant _SteppedClipper oldClipper) => oldClipper.step != step;
}

/// Ink-friendly square plate for buttons and tappable chips (no gold emboss).
class PixelInkPlate extends StatelessWidget {
  const PixelInkPlate({
    super.key,
    required this.child,
    required this.onTap,
    this.onHighlightChanged,
    this.step = PixelChrome.step,
    this.fillColor,
    this.gradient,
    this.padding,
    this.strokeWidth = 2,
    this.selected = false,
    this.shadow = true,
    this.material = PixelPlateMaterial.auto,
  });

  final Widget child;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHighlightChanged;
  final double step;
  final Color? fillColor;
  final Gradient? gradient;
  final EdgeInsetsGeometry? padding;
  final double strokeWidth;
  final bool selected;
  final bool shadow;
  final PixelPlateMaterial material;

  @override
  Widget build(BuildContext context) {
    final border = const RoundedRectangleBorder();
    final plate = Material(
      color: Colors.transparent,
      shape: border,
      child: InkWell(
        onTap: onTap,
        onHighlightChanged: onHighlightChanged,
        customBorder: border,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: PixelPlate(
          step: step,
          fillColor: fillColor,
          gradient: gradient,
          padding: padding,
          strokeWidth: strokeWidth,
          selected: selected,
          shadow: false,
          emboss: false,
          material: material,
          child: child,
        ),
      ),
    );
    if (!shadow) return plate;
    return DecoratedBox(
      decoration: const BoxDecoration(
        boxShadow: [BoxShadow(offset: Offset(2, 2), color: Color(0x66000000))],
      ),
      child: plate,
    );
  }
}
