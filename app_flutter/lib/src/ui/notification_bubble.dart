import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import '../theme.dart';

/// Ready Botany / fishing pots waiting to be collected.
int timerReadyBadgeCount(PlayerSave save, num nowMs) {
  return readyLocationTimerCount(save, nowMs).round();
}

/// Finished or cancelled trades sitting in the collection box.
int bazaarReadyBadgeCount(MarketSnapshot market) => market.collect.length;

/// Pixel badge used on chat tabs, the hamburger nest, and the desktop rail.
class NotificationBubble extends StatelessWidget {
  const NotificationBubble({super.key, required this.count});

  final num count;

  @override
  Widget build(BuildContext context) {
    final badge = unreadBadgeLabel(count);
    if (badge == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: const BoxDecoration(color: Palette.danger),
      child: Text(badge, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w400)),
    );
  }
}

/// Overlays [NotificationBubble] on the top-right of [child] when [count] > 0.
class Badged extends StatelessWidget {
  const Badged({super.key, required this.count, required this.child});

  final num count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final badge = unreadBadgeLabel(count);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (badge != null) Positioned(right: -4, top: -4, child: NotificationBubble(count: count)),
      ],
    );
  }
}
