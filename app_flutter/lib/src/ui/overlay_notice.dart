import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

/// How long a floating notice stays up: 2s for a short line, 5s for a long one.
Duration noticeHoldDuration(String text) {
  final t = ((text.trim().length - 20) / 100).clamp(0.0, 1.0);
  return Duration(milliseconds: (2000 + t * 3000).round());
}

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

class _OverlayNoticeState extends State<OverlayNotice> with SingleTickerProviderStateMixin {
  late final AnimationController _fade;
  Timer? _hold;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 400), value: 1);
    _arm();
  }

  @override
  void didUpdateWidget(covariant OverlayNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text == widget.text) return;
    _fade.value = 1;
    _arm();
  }

  void _arm() {
    _hold?.cancel();
    final token = ++_token;
    _hold = Timer(noticeHoldDuration(widget.text), () async {
      if (!mounted || token != _token) return;
      await _fade.reverse();
      if (mounted && token == _token) widget.onDismissed?.call();
    });
  }

  @override
  void dispose() {
    _hold?.cancel();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: FadeTransition(
        opacity: _fade,
        child: GamePanel(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            widget.text,
            textAlign: TextAlign.center,
            style: TextStyle(color: widget.tone, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
