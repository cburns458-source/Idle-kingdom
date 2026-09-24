import 'package:flutter/material.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'app_shell.dart';
import 'bottom_nav.dart';
import 'chat_sheet.dart';
import 'game_popup.dart';
import 'notification_bubble.dart';
import 'playable_frame.dart';
import 'tracker_view.dart';

/// Left rail: the hamburger destinations, as navigation only.
///
/// When [expand] is true the board fills leftover width while the buttons stay
/// [desktopMenuRailWidth] and hug the playable column.
class DesktopMenuRail extends StatelessWidget {
  const DesktopMenuRail({
    super.key,
    required this.screen,
    required this.onSelect,
    required this.controller,
    required this.multiplayer,
    this.nowMs,
    this.expand = false,
  });

  final GameScreen screen;
  final ValueChanged<GameScreen> onSelect;
  final GameController controller;
  final MultiplayerController multiplayer;
  final num Function()? nowMs;

  /// Stretch the board across leftover left width; keep buttons narrow.
  final bool expand;

  num _clock() => nowMs?.call() ?? controller.session.clock();

  int _badgeFor(GameScreen screen) {
    return switch (screen) {
      GameScreen.timers => timerReadyBadgeCount(controller.save, _clock()),
      GameScreen.bazaar => bazaarReadyBadgeCount(multiplayer.market),
      _ => 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[controller.secondsProgress, multiplayer]),
      builder: (context, _) {
        final body = Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
          child: SizedBox(
            width: desktopMenuRailWidth - 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Menu', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400)),
                const SizedBox(height: 2),
                const MutedText('Codex, Timers, and social pages.'),
                const SizedBox(height: 12),
                for (final item in nestMenuItems)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Badged(
                      count: _badgeFor(item.$1),
                      child: GameButton(
                        label: item.$2,
                        compact: true,
                        selected: screen == item.$1,
                        onPressed: () =>
                            onSelect(screen == item.$1 ? GameScreen.location : item.$1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
        return DecoratedBox(
          decoration: chromeBoardFill(
            context,
            border: const Border(right: BorderSide(color: Palette.edge)),
          ),
          child: expand
              ? Align(alignment: Alignment.topRight, child: body)
              : SizedBox(width: desktopMenuRailWidth, child: body),
        );
      },
    );
  }
}

/// XP / Loot tracker docked in the left desktop rail beside the menu.
class DesktopTrackerRail extends StatelessWidget {
  const DesktopTrackerRail({
    super.key,
    required this.controller,
    required this.kind,
    required this.onClose,
  });

  final GameController controller;
  final TrackerKind kind;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return GamePopupCard(
      padding: EdgeInsets.zero,
      child: TrackerView(controller: controller, kind: kind, onClose: onClose),
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
