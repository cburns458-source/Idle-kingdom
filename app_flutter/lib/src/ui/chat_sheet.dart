import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'player_profile_sheet.dart';
import 'social_bits.dart';

/// The shell chat button. The panel itself sits on the AppShell stack so it
/// can stay above the chin and rise with the keyboard.
class ChatLauncher extends StatelessWidget {
  const ChatLauncher({
    super.key,
    required this.open,
    required this.multiplayer,
    required this.onToggle,
  });

  final bool open;
  final MultiplayerController multiplayer;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: multiplayer,
      builder: (context, _) {
        final badge = unreadBadgeLabel(multiplayer.unreadDms);
        final tooltip = open
            ? 'Close chat'
            : badge == null
            ? 'Open chat'
            : 'Open chat, $badge unread';
        return Tooltip(
          message: tooltip,
          child: Material(
            color: open ? const Color(0xD9546E3E) : Palette.parchment,
            shape: CircleBorder(
              side: BorderSide(color: open ? const Color(0x66BEDC96) : Palette.edge),
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onToggle,
              child: SizedBox.square(
                dimension: 36,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.chat_bubble, size: 18, color: Palette.parchmentText),
                    if (badge != null)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Palette.danger,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badge,
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
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
    required this.controller,
    required this.multiplayer,
    required this.locationId,
    required this.citadelHub,
    required this.onClose,
  });

  final GameController controller;
  final MultiplayerController multiplayer;
  final String locationId;
  final bool citadelHub;
  final VoidCallback onClose;

  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  final TextEditingController _body = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  bool _viewingGuilds = false;

  MultiplayerController get net => widget.multiplayer;
  PlayerSave get save => widget.controller.save;

  @override
  void dispose() {
    _composerFocus.dispose();
    _body.dispose();
    super.dispose();
  }

  void _close() {
    _composerFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onClose();
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
        if (!net.canSeeSocialPages) {
          return Column(
            children: [
              _header(const []),
              const Expanded(
                child: SignedOutNotice(title: 'Chat', prompt: signInPrompt),
              ),
            ],
          );
        }
        final tabs = chatTabs(
          selected: net.chatTab,
          citadelHub: widget.citadelHub,
          hasGuild: net.guildId != null,
          hasGuest: net.guestGuildId != null,
          unreadDms: net.unreadDms,
        );
        final source = net.chatTab == ChatTab.dm ? net.messagesForSelectedDm() : net.messages;
        final lines = chatLines(
          source,
          net.session?.userId,
          filterProfanityEnabled: net.filterChatProfanity,
        );
        final showComposer =
            !_viewingGuilds && (net.chatTab != ChatTab.dm || net.selectedDmPeerId != null);
        return Column(
          children: [
            _header(tabs),
            if (net.chatTab == ChatTab.dm) _dmThreadRow(),
            if (net.chatTab == ChatTab.guild || net.chatTab == ChatTab.guest)
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  children: [
                    GameButton(
                      label: _viewingGuilds ? 'Back to chat' : chatViewGuildsLabel,
                      tone: GameButtonTone.secondary,
                      compact: true,
                      onPressed: () => setState(() => _viewingGuilds = !_viewingGuilds),
                    ),
                    if (net.guestGuild != null)
                      GameButton(
                        label: 'Leave guest',
                        tone: GameButtonTone.secondary,
                        compact: true,
                        onPressed: net.busy
                            ? null
                            : () async {
                                await net.leaveGuest(save);
                                if (mounted) setState(() => _viewingGuilds = false);
                              },
                      ),
                  ],
                ),
              ),
            Expanded(
              child: _viewingGuilds
                  ? _buildGuildBrowser()
                  : net.chatTab == ChatTab.dm && net.selectedDmPeerId == null
                  ? const Center(child: MutedText(chatDmHint))
                  : lines.isEmpty
                  ? Center(child: MutedText(emptyChatMessage(net.chatTab)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: lines.length,
                      itemBuilder: (context, index) {
                        final line = lines[index];
                        final stamp = formatChatTimestamp(line.createdAt);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: const TextStyle(
                                      fontFamily: gameFontFamily,
                                      fontSize: 13,
                                      color: Palette.parchmentText,
                                    ),
                                    children: [
                                      WidgetSpan(
                                        alignment: PlaceholderAlignment.baseline,
                                        baseline: TextBaseline.alphabetic,
                                        child: GestureDetector(
                                          onTap: line.userId.isEmpty
                                              ? null
                                              : () => openPlayerProfile(
                                                  context,
                                                  controller: widget.controller,
                                                  multiplayer: net,
                                                  userId: line.userId,
                                                ),
                                          child: Text(
                                            '${line.username}: ',
                                            style: TextStyle(
                                              fontFamily: gameFontFamily,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: line.mine
                                                  ? Palette.gold
                                                  : Palette.parchmentText,
                                            ),
                                          ),
                                        ),
                                      ),
                                      TextSpan(text: line.body),
                                    ],
                                  ),
                                ),
                              ),
                              if (stamp.isNotEmpty) ...[const SizedBox(width: 8), MutedText(stamp)],
                            ],
                          ),
                        );
                      },
                    ),
            ),
            if (showComposer)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _body,
                        focusNode: _composerFocus,
                        maxLength: 240,
                        decoration: const InputDecoration(hintText: 'Message…', counterText: ''),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GameButton(
                      label: 'Send',
                      compact: true,
                      onPressed: net.busy || !net.isSignedIn ? null : _send,
                    ),
                  ],
                ),
              )
            else if (net.chatTab == ChatTab.dm)
              const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _header(List<ChatTabView> tabs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final tab in tabs) ...[
                    GameButton(
                      label: tab.label,
                      compact: true,
                      selected: tab.selected,
                      tone: tab.selected ? GameButtonTone.primary : GameButtonTone.secondary,
                      onPressed: tab.enabled
                          ? () => net.selectChatTab(
                              tab.tab,
                              widget.locationId,
                              citadelHub: widget.citadelHub,
                            )
                          : null,
                    ),
                    if (tab.tab != tabs.last.tab) const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GameButton(
            label: 'Close',
            tone: GameButtonTone.secondary,
            compact: true,
            tooltip: 'Close chat',
            onPressed: _close,
          ),
        ],
      ),
    );
  }

  Widget _dmThreadRow() {
    final threads = net.openDmThreads;
    if (threads.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final thread in threads) ...[
              GameButton(
                label: thread.username,
                compact: true,
                selected: net.selectedDmPeerId == thread.userId,
                tone: net.selectedDmPeerId == thread.userId
                    ? GameButtonTone.primary
                    : GameButtonTone.secondary,
                onPressed: () => net.selectDmPeer(thread.userId, username: thread.username),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGuildBrowser() {
    final own = <String>{
      if (net.guildId != null) net.guildId!,
      if (net.guestGuildId != null) net.guestGuildId!,
    };
    final rows = guildBrowseRows(net.listings.where((row) => !own.contains(row.id)).toList());
    if (rows.isEmpty) {
      return const Center(child: MutedText('No other guilds to guest.'));
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        for (final row in rows) ...[
          SocialRow(
            title: row.title,
            subtitle: row.subtitle,
            leading: GuildEmblemBadge(emblem: row.emblem),
            trailing: GameButton(
              label: row.guestLabel,
              tone: GameButtonTone.secondary,
              compact: true,
              onPressed: net.busy
                  ? null
                  : () async {
                      await net.joinAsGuest(
                        row.guildId,
                        defaultApplicationMessage(save.characterName),
                        save,
                      );
                      if (mounted) {
                        setState(() => _viewingGuilds = false);
                        await net.selectChatTab(
                          ChatTab.guest,
                          widget.locationId,
                          citadelHub: widget.citadelHub,
                        );
                      }
                    },
            ),
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}
