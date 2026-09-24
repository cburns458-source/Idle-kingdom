import 'package:flutter/material.dart';

import '../theme.dart';

/// Tiny white wash used when a floating cell or list row is selected / own.
Color floatingSelectTint(Color base) => Color.lerp(base, Colors.white, 0.16)!;

/// Borderless tappable well: the icon floats on the outer panel; no slot stroke.
///
/// Empty cells stay invisible (transparent child). Selection is a light white
/// tint; ripple stays so taps still feel pressable.
class FloatingItemSlot extends StatelessWidget {
  const FloatingItemSlot({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.tooltip,
    this.selected = false,
    this.enabled = true,
    this.padding = const EdgeInsets.all(2),
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? tooltip;
  final bool selected;
  final bool enabled;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final chrome = UiChrome.of(context);
    final fill = selected ? floatingSelectTint(chrome.panel) : Colors.transparent;
    Widget body = Material(
      color: fill,
      child: InkWell(
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onLongPress : null,
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
