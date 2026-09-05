import 'package:flutter/material.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'app_shell.dart';
import 'bottom_nav.dart';
import 'chat_sheet.dart';

/// Left rail: the hamburger destinations, as navigation only.
class DesktopMenuRail extends StatelessWidget {
  const DesktopMenuRail({super.key, required this.screen, required this.onSelect});

  final GameScreen screen;
  final ValueChanged<GameScreen> onSelect;

  @override
  Widget build(BuildContext context) {
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
                child: GameButton(
                  label: item.$2,
                  selected: screen == item.$1,
                  onPressed: () => onSelect(screen == item.$1 ? GameScreen.location : item.$1),
                ),
              ),
          ],
        ),
      ),
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
