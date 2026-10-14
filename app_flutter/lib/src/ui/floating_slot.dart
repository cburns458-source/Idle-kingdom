import 'package:flutter/material.dart';

import '../theme.dart';

/// Tiny white wash used when a floating cell or list row is selected / own.
Color floatingSelectTint(Color base) => Color.lerp(base, Colors.white, 0.16)!;

/// One large dark slot well — same chrome as the old per-item tiles, wrapping a
/// whole bag / shop / catalog grid so icons float inside one recessed board.
class FloatingItemWell extends StatelessWidget {
  const FloatingItemWell({super.key, required this.child, this.padding = const EdgeInsets.all(6)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return PixelPlate(
      step: PixelChrome.stepTight,
      fillColor: UiChrome.of(context).slot,
      material: PixelPlateMaterial.grain,
      strokeWidth: 2,
      shadow: false,
      padding: padding,
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Palette.parchmentText),
        child: IconTheme.merge(
          data: const IconThemeData(color: Palette.parchmentText),
          child: child,
        ),
      ),
    );
  }
}

/// Borderless tappable cell: the icon floats on [FloatingItemWell]; no slot stroke.
///
/// Empty cells stay invisible (transparent child). Selection is a light white
/// tint; ripple stays so taps still feel pressable.
class FloatingItemSlot extends StatelessWidget {
  const FloatingItemSlot({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.tooltip,
    this.selected = false,
    this.enabled = true,
    this.padding = const EdgeInsets.all(2),
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final String? tooltip;
  final bool selected;
  final bool enabled;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final chrome = UiChrome.of(context);
    // White wash on the dark slot board, not the tan outer panel.
    final fill = selected ? floatingSelectTint(chrome.slot) : Colors.transparent;
    Widget body = Material(
      color: fill,
      child: InkWell(
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onLongPress : null,
        onSecondaryTap: enabled ? onSecondaryTap : null,
        splashColor: Colors.white24,
        highlightColor: Colors.white12,
        child: Padding(padding: padding, child: child),
      ),
    );
    if (!enabled) {
      body = Opacity(opacity: 0.45, child: body);
    }
    if (tooltip == null) return body;
    return Tooltip(message: tooltip!, child: body);
  }
}

/// Spacing-only separators between floating social / catalog rows.
const floatingRowGap = SizedBox(height: 6);

/// Smallest cell a finger can land on reliably.
const double minItemTapExtent = 48;

/// Columns for a grid of square cells about [tile] wide, separated by [gap].
///
/// Picks the count whose cells come nearest to [tile] among those that keep
/// every cell at least [minTile] wide. A max-extent grid delegate would instead
/// let cells shrink to whatever the width happens to divide into.
int denseGridColumns(
  double width, {
  required double tile,
  required double gap,
  double minTile = minItemTapExtent,
}) {
  if (!width.isFinite || width <= 0) return 1;
  final most = ((width + gap) / (minTile + gap)).floor();
  var best = 1;
  var bestDistance = double.infinity;
  for (var count = 1; count <= most; count += 1) {
    final cell = (width - (count - 1) * gap) / count;
    final distance = (cell - tile).abs();
    if (distance < bestDistance) {
      best = count;
      bestDistance = distance;
    }
  }
  return best;
}
