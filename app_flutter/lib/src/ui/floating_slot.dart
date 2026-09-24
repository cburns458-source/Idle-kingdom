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
