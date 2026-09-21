import 'dart:async';

import 'package:flutter/material.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'app_shell.dart';
import 'bottom_nav.dart';
import 'chat_sheet.dart';
import 'notification_bubble.dart';

/// Left rail: the hamburger destinations, as navigation only.
class DesktopMenuRail extends StatefulWidget {
  const DesktopMenuRail({
    super.key,
    required this.screen,
    required this.onSelect,
    required this.controller,
    required this.multiplayer,
    this.nowMs,
  });

  final GameScreen screen;
  final ValueChanged<GameScreen> onSelect;
  final GameController controller;
  final MultiplayerController multiplayer;
  final num Function()? nowMs;

  @override
  State<DesktopMenuRail> createState() => _DesktopMenuRailState();
}

class _DesktopMenuRailState extends State<DesktopMenuRail> {
  Timer? _ticker;

  num _clock() => widget.nowMs?.call() ?? widget.controller.session.clock();

  int _badgeFor(GameScreen screen) {
    return switch (screen) {
      GameScreen.timers => timerReadyBadgeCount(widget.controller.save, _clock()),
      GameScreen.bazaar => bazaarReadyBadgeCount(widget.multiplayer.market),
      _ => 0,
    };
  }

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[widget.controller, widget.multiplayer]),
      builder: (context, _) {
        return DecoratedBox(
          decoration: chromeBoardFill(
            context,
            border: const Border(right: BorderSide(color: Palette.edge)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Menu', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w400)),
                const SizedBox(height: 4),
                const MutedText('Settings, log, Codex, and social pages.'),
                const SizedBox(height: 16),
                for (final item in nestMenuItems)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Badged(
                      count: _badgeFor(item.$1),
                      child: GameButton(
                        label: item.$2,
                        selected: widget.screen == item.$1,
                        onPressed: () => widget.onSelect(
                          widget.screen == item.$1 ? GameScreen.location : item.$1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Right rail: persistent chat, no close control.
class DesktopChatRail extends StatelessWidget {
  const DesktopChatRail({
    super.key,
    required this.controller,
    required this.multiplayer,
    required this.locationId,
    required this.citadelHub,
  });

  final GameController controller;
  final MultiplayerController multiplayer;
  final String locationId;
  final bool citadelHub;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('chat-panel'),
      color: UiChrome.of(context).board,
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: chromeBoardFill(context, textureOpacity: 0.4),
        child: ChatSheet(
          controller: controller,
          multiplayer: multiplayer,
          locationId: locationId,
          citadelHub: citadelHub,
          embedded: true,
          onClose: () {},
        ),
      ),
    );
  }
}
