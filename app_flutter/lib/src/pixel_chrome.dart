import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'session/ui_chrome.dart';

/// Wood + gold embossed pixel chrome (photo-2 direction).
///
/// Stepped corners replace soft [BorderRadius] curves. Layout sizes stay the
/// same — only the outline geometry and border treatment change.
abstract final class PixelChrome {
  /// Default stair size for buttons and panels.
  static const double step = 3;

  /// Tighter stair for compact chips / icon buttons.
  static const double stepTight = 2;

  /// Gold emboss face — antique brass, not bright jewelry gold.
  static const Color goldFace = Color(0xFF7A5F24);

  /// Soft top-left highlight on embossed borders (kept dull).
  static const Color goldHighlight = Color(0xFF968040);

  /// Bottom-right shade on embossed gold borders.
  static const Color goldShade = Color(0xFF3A2A0A);

  /// Dark wood plate under gold rims.
  static const Color wood = Color(0xFF2A1C12);

  /// Builds a stair-corner rectangle path inset to [rect].
  static Path steppedPath(Rect rect, {double step = step}) {
    final maxStep = math.min(rect.width, rect.height) / 3;
    final s = step.clamp(1.0, maxStep);
    final l = rect.left;
    final t = rect.top;
    final r = rect.right;
    final b = rect.bottom;
    return Path()
      ..moveTo(l + s, t)
      ..lineTo(r - s, t)
      ..lineTo(r - s, t + s)
      ..lineTo(r, t + s)
      ..lineTo(r, b - s)
      ..lineTo(r - s, b - s)
      ..lineTo(r - s, b)
      ..lineTo(l + s, b)
      ..lineTo(l + s, b - s)
      ..lineTo(l, b - s)
      ..lineTo(l, t + s)
      ..lineTo(l + s, t + s)
      ..close();
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
    final path = getOuterPath(rect, textDirection: textDirection);
    canvas.drawPath(path, side.toPaint()..style = PaintingStyle.stroke);
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
    this.selected = false,
  });

  final double step;
  final double strokeWidth;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rect = Offset.zero & size;
    final path = PixelChrome.steppedPath(rect.deflate(inset), step: step);

    final shade = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = selected ? PixelChrome.goldShade : const Color(0xFF3A2A0C)
      ..strokeJoin = StrokeJoin.miter;

    final face = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, strokeWidth - 0.5)
      ..color = selected ? const Color(0xFF967A32) : PixelChrome.goldFace
      ..strokeJoin = StrokeJoin.miter;

    final light = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = selected ? PixelChrome.goldHighlight : const Color(0xFF7A6434)
      ..strokeJoin = StrokeJoin.miter;

    canvas
      ..save()
      ..translate(0.8, 0.8)
      ..drawPath(path, shade)
      ..restore()
      ..drawPath(path, face);

    // Subtle top + left lift — muted so borders stay matte, not shiny.
    final s = step.clamp(1.0, math.min(size.width, size.height) / 3);
    final highlight = Path()
      ..moveTo(inset + s, inset)
      ..lineTo(size.width - inset - s, inset)
      ..moveTo(inset, inset + s)
      ..lineTo(inset, size.height - inset - s);
    canvas.drawPath(highlight, light);
  }

  @override
  bool shouldRepaint(covariant _EmbossBorderPainter oldDelegate) {
    return oldDelegate.step != step ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.selected != selected;
  }
}

/// Optional corner rivets (photo-2 studs), drawn inside the plate.
class _RivetPainter extends CustomPainter {
  const _RivetPainter({required this.step});

  final double step;

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
    final fill = Paint()..color = const Color(0xFF8A6B28);
    final shade = Paint()..color = const Color(0xFF3F2E0C);
    for (final c in centers) {
      canvas.drawRect(
        Rect.fromCenter(center: c.translate(0.5, 0.5), width: rivet, height: rivet),
        shade,
      );
      canvas.drawRect(Rect.fromCenter(center: c, width: rivet, height: rivet), fill);
    }
  }

  @override
  bool shouldRepaint(covariant _RivetPainter oldDelegate) => oldDelegate.step != step;
}

/// Fill material for [PixelPlate] — wood outer boards vs tan inner panels.
enum PixelPlateMaterial { auto, wood, tan, none }

/// Wood plate with stepped corners and gold emboss rim. Keeps child layout size.
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
  final PixelPlateMaterial material;

  DecorationImage? _texture(BuildContext context) {
    if (fillColor == null && gradient == null) return null;
    // Auto: panel texture on light fills only. Dark fills stay solid so board
    // texture is reserved for shell / HUD boards, not every button and slot.
    final kind = material == PixelPlateMaterial.auto
        ? ((fillColor != null && fillColor!.computeLuminance() > 0.28)
              ? PixelPlateMaterial.tan
              : PixelPlateMaterial.none)
        : material;
    final chrome = UiChrome.of(context);
    return switch (kind) {
      PixelPlateMaterial.wood => DecorationImage(
        image: AssetImage(chrome.boardTextureAsset),
        repeat: ImageRepeat.repeat,
        fit: BoxFit.none,
        alignment: Alignment.topLeft,
        filterQuality: FilterQuality.none,
        opacity: 0.45,
      ),
      PixelPlateMaterial.tan => DecorationImage(
        image: AssetImage(chrome.panelTextureAsset),
        repeat: ImageRepeat.repeat,
        fit: BoxFit.none,
        alignment: Alignment.topLeft,
        filterQuality: FilterQuality.none,
        opacity: 0.32,
      ),
      PixelPlateMaterial.none => null,
      PixelPlateMaterial.auto => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final shape = PixelSteppedBorder(step: step);
    Widget content = child;
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }

    Widget plate = CustomPaint(
      foregroundPainter: _EmbossBorderPainter(
        step: step,
        strokeWidth: strokeWidth,
        selected: selected,
      ),
      child: rivets
          ? CustomPaint(
              painter: _RivetPainter(step: step),
              child: content,
            )
          : content,
    );

    if (clip) {
      plate = ClipPath(
        clipper: _SteppedClipper(step: step),
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

/// Ink-friendly stepped plate for buttons and tappable chips.
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
    // Hit-test shape only. A stroked OutlinedBorder on Material insets the
    // child and grows intrinsic width, which breaks tight button rows.
    final border = PixelSteppedBorder(step: step);
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
          material: material,
          child: child,
        ),
      ),
    );
    if (!shadow) return plate;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: PixelSteppedBorder(step: step),
        shadows: const [BoxShadow(offset: Offset(2, 2), color: Color(0x66000000))],
      ),
      child: plate,
    );
  }
}
