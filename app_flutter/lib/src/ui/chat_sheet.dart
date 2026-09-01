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
        final badge = unreadBadgeLabel(multiplayer.unreadTotal);
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
                            borderRadius: BorderRadius.zero /* pixel step 1 */,
                          ),
                          child: Text(
                            badge,
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w400),
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
    this.embedded = false,
  });

  final GameController controller;
  final MultiplayerController multiplayer;
  final String locationId;
  final bool citadelHub;
  final VoidCallback onClose;

  /// Side-docked chat stays open; the close control is hidden.
  final bool embedded;

  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  final TextEditingController _body = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  ChatTab? _pinnedTab;
  String? _pinnedDm;
  int _pinnedCount = -1;
  double _pinnedInset = -1;

  MultiplayerController get net => widget.multiplayer;
  PlayerSave get save => widget.controller.save;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pinToLatest(force: true);
      if (widget.embedded && net.canSeeSocialPages) {
        net.selectChatTab(net.chatTab, widget.locationId, citadelHub: widget.citadelHub);
      }
    });
  }

  @override
  void dispose() {
    _composerFocus.dispose();
    _body.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _pinToLatest({required bool force, int attempt = 0}) {
    if (!mounted || !_scroll.hasClients) return;
    final pos = _scroll.position;
    // reverse:true keeps the newest line at 0.
    if (!force && pos.pixels > 72) return;
    _scroll.jumpTo(0);
    if (force && attempt < 5) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pinToLatest(force: true, attempt: attempt + 1);
      });
    }
  }

  /// Jump to the newest line on open or tab change, and stay there as lines
  /// arrive unless the player has scrolled up.
  void _considerPin(ChatTab tab, String? dm, int count) {
    final switched = _pinnedTab != tab || _pinnedDm != dm;
    final grew = count > _pinnedCount && _pinnedCount >= 0;
    final first = _pinnedCount < 0;
    _pinnedTab = tab;
    _pinnedDm = dm;
    _pinnedCount = count;
    if (first || switched || grew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pinToLatest(force: first || switched);
      });
    }
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
          unread: net.unreadByTab,
        );
        final source = net.chatTab == ChatTab.dm ? net.messagesForSelectedDm() : net.messages;
        final lines = chatLines(
          source,
          net.session?.userId,
          filterProfanityEnabled: net.filterChatProfanity,
        );
        final showComposer = net.chatTab != ChatTab.dm || net.selectedDmPeerId != null;
        final inset = MediaQuery.viewInsetsOf(context).bottom;
        _considerPin(net.chatTab, net.selectedDmPeerId, lines.length);
        if (inset != _pinnedInset) {
          _pinnedInset = inset;
          WidgetsBinding.instance.addPostFrameCallback((_) => _pinToLatest(force: false));
        }
        return Column(
          children: [
            _header(tabs),
            if (net.chatTab == ChatTab.dm) _dmThreadRow(),
            if (net.chatTab == ChatTab.guest && net.guestGuild != null)
              Align(
                alignment: Alignment.centerLeft,
                child: GameButton(
                  label: 'Leave guest',
                  tone: GameButtonTone.secondary,
                  compact: true,
                  onPressed: net.busy
                      ? null
                      : () async {
                          await net.leaveGuest(save);
                        },
                ),
              ),
            Expanded(
              child: net.chatTab == ChatTab.dm && net.selectedDmPeerId == null
                  ? const Center(child: MutedText(chatDmHint))
                  : lines.isEmpty
                  ? Center(child: MutedText(emptyChatMessage(net.chatTab)))
                  : ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: lines.length,
                      itemBuilder: (context, index) {
                        final line = lines[lines.length - 1 - index];
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
                                      if (line.username.isNotEmpty)
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
                                                fontWeight: FontWeight.w400,
                                                color:
                                                    colorFromHexRgb(
                                                      net.publishedNameColor(line.userId),
                                                    ) ??
                                                    (line.mine
                                                        ? Palette.gold
                                                        : Palette.parchmentText),
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
                    _ChatTabButton(
                      tab: tab,
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
          if (!widget.embedded) ...[
            const SizedBox(width: 8),
            GameButton(
              label: 'Close',
              tone: GameButtonTone.secondary,
              compact: true,
              tooltip: 'Close chat',
              onPressed: _close,
            ),
          ],
        ],
      ),
    );
  }

  Widget _dmThreadRow() {
    final threads = net.openDmThreads;
    if (threads.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          alignment: WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final thread in threads)
              GameButton(
                label: thread.username,
                compact: true,
                selected: net.selectedDmPeerId == thread.userId,
                tone: net.selectedDmPeerId == thread.userId
                    ? GameButtonTone.primary
                    : GameButtonTone.secondary,
                onPressed: () => net.selectDmPeer(thread.userId, username: thread.username),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChatTabButton extends StatelessWidget {
  const _ChatTabButton({required this.tab, required this.onPressed});

  final ChatTabView tab;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final badge = tab.selected ? null : unreadBadgeLabel(tab.unread);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GameButton(
          label: tab.label,
          compact: true,
          selected: tab.selected,
          tone: tab.selected ? GameButtonTone.primary : GameButtonTone.secondary,
          onPressed: onPressed,
        ),
        if (badge != null)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Palette.danger,
                borderRadius: BorderRadius.zero /* pixel step 1 */,
              ),
              child: Text(badge, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w400)),
            ),
          ),
      ],
    );
  }
}
