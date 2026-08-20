import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

/// How long a floating notice stays up: 2s for a short line, 5s for a long one.
Duration noticeHoldDuration(String text) {
  final t = ((text.trim().length - 20) / 100).clamp(0.0, 1.0);
  return Duration(milliseconds: (2000 + t * 3000).round());
}

const Duration noticeFadeDuration = Duration(milliseconds: 400);

/// A warning or status line that sits over the screen and fades itself away.
///
/// It is painted in a [Stack], so it never pushes the layout around.
class OverlayNotice extends StatefulWidget {
  const OverlayNotice({super.key, required this.text, required this.tone, this.onDismissed});

  final String text;
  final Color tone;
  final VoidCallback? onDismissed;

  @override
  State<OverlayNotice> createState() => _OverlayNoticeState();
}

class _OverlayNoticeState extends State<OverlayNotice> {
  Timer? _hold;
  bool _opaque = true;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(covariant OverlayNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text == widget.text) return;
    _arm();
  }

  void _arm() {
    _hold?.cancel();
    _opaque = true;
    _hold = Timer(noticeHoldDuration(widget.text), _beginFade);
  }

  void _beginFade() {
    if (!mounted || !_opaque) return;
    setState(() => _opaque = false);
    _hold = Timer(noticeFadeDuration, () {
      if (mounted) widget.onDismissed?.call();
    });
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _opaque ? 1 : 0,
        duration: noticeFadeDuration,
        child: GamePanel(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            widget.text,
            textAlign: TextAlign.center,
            style: TextStyle(color: widget.tone, fontSize: 13, fontWeight: FontWeight.w400),
          ),
        ),
      ),
    );
  }
}
