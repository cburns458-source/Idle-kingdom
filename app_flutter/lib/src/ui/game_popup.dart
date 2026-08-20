import 'package:flutter/material.dart';

import '../theme.dart';

/// Where a floating popup settles. Footer / bottom sheets are not used.
enum GamePopupPlacement {
  /// Center of the playable frame.
  center,

  /// Centered, but in the top half (chat and social alerts).
  topHalf,
}

/// The box a control occupies, for popups that grow out of that control.
Rect? popupOrigin(BuildContext context) {
  final render = context.findRenderObject();
  if (render is! RenderBox || !render.hasSize) return null;
  return render.localToGlobal(Offset.zero) & render.size;
}

Alignment _alignmentFor(BuildContext context, Rect? origin, GamePopupPlacement placement) {
  if (origin != null) {
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    if (overlay != null && overlay.hasSize && overlay.size.width > 0 && overlay.size.height > 0) {
      final center = overlay.globalToLocal(origin.center);
      return Alignment(
        ((center.dx / overlay.size.width) - 0.5) * 2,
        ((center.dy / overlay.size.height) - 0.5) * 2,
      );
    }
  }
  return placement == GamePopupPlacement.topHalf ? const Alignment(0, -0.65) : Alignment.center;
}

/// Card popup that can grow from [origin] and never docks to the chin.
Future<T?> showGamePopup<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  GamePopupPlacement placement = GamePopupPlacement.center,
  Rect? origin,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: false,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Dismiss',
    barrierColor: const Color(0xCC120C08),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondary) {
      return SafeArea(
        child: Align(
          alignment: placement == GamePopupPlacement.topHalf
              ? const Alignment(0, -0.65)
              : Alignment.center,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 400,
                maxHeight:
                    MediaQuery.sizeOf(context).height *
                    (placement == GamePopupPlacement.topHalf ? 0.48 : 0.7),
              ),
              child: KeyedSubtree(key: const Key('game-popup'), child: builder(context)),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: origin == null ? 0.96 : 0.86, end: 1).animate(curved),
          alignment: _alignmentFor(context, origin, placement),
          child: child,
        ),
      );
    },
  );
}

/// Parchment card chrome every floating popup shares.
class GamePopupCard extends StatelessWidget {
  const GamePopupCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Palette.parchmentDeep,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding ?? const EdgeInsets.all(16), child: child),
    );
  }
}

/// Confirm / info card: gold confirm, outline cancel.
Future<bool> showGameAlert({
  required BuildContext context,
  String? title,
  required String message,
  String confirmLabel = 'OK',
  String? cancelLabel,
  GamePopupPlacement placement = GamePopupPlacement.topHalf,
  Rect? origin,
}) async {
  final result = await showGamePopup<bool>(
    context: context,
    placement: placement,
    origin: origin,
    builder: (context) {
      return GamePopupCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (title != null) const SizedBox(height: 8),
            Text(message, style: const TextStyle(height: 1.4)),
            const SizedBox(height: 14),
            Row(
              children: [
                if (cancelLabel != null) ...[
                  GameButton(
                    label: cancelLabel,
                    tone: GameButtonTone.secondary,
                    compact: true,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: GameButton(
                    label: confirmLabel,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  return result ?? false;
}
