import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../session/battery_saver_pref.dart';
import '../theme.dart';
import 'bottom_nav.dart';
import 'top_hud.dart';

/// Where a floating popup settles. Footer / bottom sheets are not used.
enum GamePopupPlacement {
  /// Center of the playable frame.
  center,

  /// Same as [center]; kept so older call sites still compile.
  topHalf,

  /// Flush to the left half of the playable frame (XP / Loot trackers).
  leftHalf,
}

/// Shared card size for every floating popup.
const double gamePopupMaxWidth = 320;
const double gamePopupMaxHeight = 360;
const double gamePopupTitleSize = 11;
const double gamePopupBodySize = 10;

/// Gap under the HUD and above the chin when a popup grows to fit.
const double gamePopupHudChinGap = 20;

/// Tallest a popup may grow: frame height minus HUD, chin, and [gamePopupHudChinGap] each.
double gamePopupCeilingHeight(BuildContext context) {
  final h = MediaQuery.sizeOf(context).height;
  final hud = HudPortrait.size + 2;
  return math.max(gamePopupMaxHeight, h - hud - chinHeight - gamePopupHudChinGap * 2);
}

/// The box a control occupies, for popups that grow out of that control.
Rect? popupOrigin(BuildContext context) {
  final render = context.findRenderObject();
  if (render is! RenderBox || !render.hasSize) return null;
  return render.localToGlobal(Offset.zero) & render.size;
}

Alignment _alignmentFor(BuildContext context, Rect? origin, GamePopupPlacement placement) {
  if (placement == GamePopupPlacement.leftHalf) {
    return Alignment.centerLeft;
  }
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
  Color? barrierColor,
  UiChrome? chrome,
  double? maxWidth,
  double? maxHeight,
}) {
  final reduceMotion = BatterySaverScope.of(context);
  final resolvedChrome = chrome ?? UiChrome.of(context);
  final size = MediaQuery.sizeOf(context);
  final ceiling = gamePopupCeilingHeight(context);
  final resolvedMaxWidth = maxWidth ??
      (placement == GamePopupPlacement.leftHalf ? size.width / 2 : gamePopupMaxWidth);
  // Ceiling is HUD+20 … chin−20; short cards still shrink to their content.
  final resolvedMaxHeight = maxHeight ?? ceiling;
  final verticalPad =
      placement == GamePopupPlacement.leftHalf ? gamePopupHudChinGap : 12.0;
  final horizontalPad = placement == GamePopupPlacement.leftHalf ? 0.0 : 16.0;
  final align = placement == GamePopupPlacement.leftHalf ? Alignment.centerLeft : Alignment.center;

  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: false,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Dismiss',
    barrierColor: barrierColor ?? const Color(0xCC120C08),
    transitionDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, animation, secondary) {
      return UiChromeScope(
        chrome: resolvedChrome,
        child: SafeArea(
          child: Align(
            alignment: align,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPad, vertical: verticalPad),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: resolvedMaxWidth,
                  maxHeight: resolvedMaxHeight,
                  minWidth: placement == GamePopupPlacement.leftHalf ? resolvedMaxWidth : 0,
                  minHeight: placement == GamePopupPlacement.leftHalf ? resolvedMaxHeight : 0,
                ),
                child: SizedBox(
                  width: placement == GamePopupPlacement.leftHalf ? resolvedMaxWidth : null,
                  height: placement == GamePopupPlacement.leftHalf ? resolvedMaxHeight : null,
                  child: Material(
                    type: MaterialType.transparency,
                    child: KeyedSubtree(key: const Key('game-popup'), child: builder(dialogContext)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondary, child) {
      if (reduceMotion) return child;
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

/// Board-card chrome every floating popup shares.
///
/// Uses the active [UiChrome] pack (wood planks or stone courses). Light
/// parchment copy on the board; nest [GamePanel] for inner info plates.
class GamePopupCard extends StatelessWidget {
  const GamePopupCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final chrome = UiChrome.of(context);
    return Material(
      color: chrome.board,
      shape: PixelSteppedBorder(step: 3),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: chromeBoardFill(context, textureOpacity: 0.4),
        child: DefaultTextStyle.merge(
          style: const TextStyle(
            color: Palette.parchmentText,
            fontFamily: gameFontFamily,
            fontSize: gamePopupBodySize,
          ),
          child: IconTheme.merge(
            data: const IconThemeData(color: Palette.parchmentText),
            child: Padding(padding: padding ?? const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
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
              Text(
                title,
                style: const TextStyle(fontSize: gamePopupTitleSize, fontWeight: FontWeight.w400),
              ),
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

/// Choice from the hostile-location travel confirm.
enum HostileTravelChoice { cancel, travel, dontAskAgain }

/// Confirm before travelling into a danger-warning location.
Future<HostileTravelChoice> showHostileTravelWarning({
  required BuildContext context,
  required String message,
  Rect? origin,
}) async {
  final result = await showGamePopup<HostileTravelChoice>(
    context: context,
    placement: GamePopupPlacement.center,
    origin: origin,
    barrierDismissible: true,
    builder: (context) {
      return GamePopupCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message, style: const TextStyle(height: 1.4)),
            const SizedBox(height: 14),
            Row(
              children: [
                GameButton(
                  label: 'Cancel',
                  tone: GameButtonTone.secondary,
                  compact: true,
                  onPressed: () => Navigator.of(context).pop(HostileTravelChoice.cancel),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GameButton(
                    label: 'Travel',
                    onPressed: () => Navigator.of(context).pop(HostileTravelChoice.travel),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GameButton(
              label: "Don't ask again",
              tone: GameButtonTone.secondary,
              onPressed: () => Navigator.of(context).pop(HostileTravelChoice.dontAskAgain),
            ),
          ],
        ),
      );
    },
  );
  return result ?? HostileTravelChoice.cancel;
}
