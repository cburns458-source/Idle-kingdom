import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';

import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'social_bits.dart';

/// The chat button that floats over the game, and the sheet it opens.
///
/// Chat never covers the whole screen: the game keeps running behind it, and the
/// button carries the unread count so a closed sheet still says something.
class ChatLauncher extends StatefulWidget {
  const ChatLauncher({
    super.key,
    required this.multiplayer,
    required this.locationId,
    this.citadelHub = false,
  });

  final MultiplayerController multiplayer;
  final String locationId;

  /// True anywhere in the Citadel, where Local is one room across districts.
  final bool citadelHub;

  @override
  State<ChatLauncher> createState() => _ChatLauncherState();
}

class _ChatLauncherState extends State<ChatLauncher> {
  bool _open = false;

  MultiplayerController get net => widget.multiplayer;

  Future<void> _openSheet() async {
    setState(() => _open = true);
    await net.selectChatTab(net.chatTab, widget.locationId, citadelHub: widget.citadelHub);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.parchmentDeep,
      builder: (context) =>
          ChatSheet(multiplayer: net, locationId: widget.locationId, citadelHub: widget.citadelHub),
    );
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: net,
      builder: (context, _) {
        if (!net.isSignedIn || _open) return const SizedBox.shrink();
        final badge = unreadBadgeLabel(net.unreadDms);
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              FloatingActionButton.small(
                onPressed: _openSheet,
                tooltip: badge == null ? 'Open chat' : 'Open chat, $badge unread',
                backgroundColor: Palette.parchment,
                foregroundColor: Palette.parchmentText,
                child: const Icon(Icons.chat_bubble, size: 18),
              ),
              if (badge != null)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Palette.danger,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The rooms themselves: a tab strip, the lines, and a composer.
class ChatSheet extends StatefulWidget {
  const ChatSheet({
    super.key,
    required this.multiplayer,
    required this.locationId,
    required this.citadelHub,
  });

  final MultiplayerController multiplayer;
  final String locationId;
  final bool citadelHub;

  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  final TextEditingController _body = TextEditingController();

  MultiplayerController get net => widget.multiplayer;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_body.text.trim().isEmpty) return;
    final sent = _body.text;
    await net.sendChat(sent, widget.locationId, citadelHub: widget.citadelHub);
    if (mounted && net.notice == null) _body.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: net,
      builder: (context, _) {
        final tabs = chatTabs(
          selected: net.chatTab,
          citadelHub: widget.citadelHub,
          hasGuild: net.guildId != null,
          unreadDms: net.unreadDms,
        );
        final lines = chatLines(net.messages, net.session?.userId);
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SizedBox(
            height: 420,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                  child: Row(
                    children: [
                      for (final tab in tabs) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: tab.enabled
                                ? () => net.selectChatTab(
                                    tab.tab,
                                    widget.locationId,
                                    citadelHub: widget.citadelHub,
                                  )
                                : null,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                              backgroundColor: tab.selected ? const Color(0x33D4AF37) : null,
                              side: BorderSide(color: tab.selected ? Palette.gold : Palette.edge),
                            ),
                            child: Text(
                              tab.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        if (tab.tab != tabs.last.tab) const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: lines.isEmpty
                      ? Center(child: MutedText(emptyChatMessage(net.chatTab)))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: lines.length,
                          itemBuilder: (context, index) {
                            final line = lines[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: RichText(
                                text: TextSpan(
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Palette.parchmentText,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: '${line.username} ',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: line.mine ? Palette.gold : Palette.parchmentText,
                                      ),
                                    ),
                                    TextSpan(text: line.body),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                SocialNotice(notice: net.notice),
                if (net.chatTab == ChatTab.dm)
                  const Padding(padding: EdgeInsets.all(12), child: MutedText(chatDmHint))
                else
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _body,
                            maxLength: 240,
                            decoration: const InputDecoration(
                              hintText: 'Message…',
                              counterText: '',
                            ),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(onPressed: net.busy ? null : _send, child: const Text('Send')),
                      ],
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
