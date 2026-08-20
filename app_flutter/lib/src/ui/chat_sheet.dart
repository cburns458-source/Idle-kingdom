import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'player_profile_sheet.dart';
import 'social_bits.dart';

/// The shell chat button, and the panel that grows up from it.
///
/// Chat never covers the whole screen: the game keeps running behind it, and the
/// button carries the unread count so a closed panel still says something.
class ChatLauncher extends StatefulWidget {
  const ChatLauncher({
    super.key,
    required this.controller,
    required this.multiplayer,
    required this.locationId,
    this.citadelHub = false,
  });

  final GameController controller;
  final MultiplayerController multiplayer;
  final String locationId;

  /// True anywhere in the Citadel, where Local is one room across districts.
  final bool citadelHub;

  @override
  State<ChatLauncher> createState() => _ChatLauncherState();
}

class _ChatLauncherState extends State<ChatLauncher> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;

  MultiplayerController get net => widget.multiplayer;

  bool get _open => _entry != null;

  @override
  void didUpdateWidget(covariant ChatLauncher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locationId == widget.locationId && oldWidget.citadelHub == widget.citadelHub) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entry?.markNeedsBuild();
    });
  }

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    if (_open) {
      _close();
      return;
    }
    if (net.canSeeSocialPages) {
      await net.selectChatTab(net.chatTab, widget.locationId, citadelHub: widget.citadelHub);
    }
    if (!mounted || _open) return;
    final entry = OverlayEntry(builder: _buildOverlay);
    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    setState(() {});
  }

  Widget _buildOverlay(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = math.min(360.0, size.width - 16);
    final height = math.min(420.0, size.height * 0.62);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: const ColoredBox(color: Color(0x00000000)),
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topRight,
          followerAnchor: Alignment.bottomRight,
          offset: const Offset(0, -8),
          child: Material(
            color: Palette.parchmentDeep,
            elevation: 12,
            shadowColor: const Color(0x73000000),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Palette.edge),
            ),
            child: SizedBox(
              width: width,
              height: height,
              child: ChatSheet(
                controller: widget.controller,
                multiplayer: net,
                locationId: widget.locationId,
                citadelHub: widget.citadelHub,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: net,
      builder: (context, _) {
        final badge = unreadBadgeLabel(net.unreadDms);
        final tooltip = _open
            ? 'Close chat'
            : badge == null
            ? 'Open chat'
            : 'Open chat, $badge unread';
        return CompositedTransformTarget(
          link: _link,
          child: Tooltip(
            message: tooltip,
            child: Material(
              color: _open ? const Color(0xD9546E3E) : Palette.parchment,
              shape: CircleBorder(
                side: BorderSide(color: _open ? const Color(0x66BEDC96) : Palette.edge),
              ),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _toggle,
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
  });

  final GameController controller;
  final MultiplayerController multiplayer;
  final String locationId;
  final bool citadelHub;

  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  final TextEditingController _body = TextEditingController();
  bool _viewingGuilds = false;

  MultiplayerController get net => widget.multiplayer;
  PlayerSave get save => widget.controller.save;

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
        if (!net.canSeeSocialPages) {
          return const SignedOutNotice(title: 'Chat', prompt: signInPrompt);
        }
        final tabs = chatTabs(
          selected: net.chatTab,
          citadelHub: widget.citadelHub,
          hasGuild: net.guildId != null,
          hasGuest: net.guestGuildId != null,
          unreadDms: net.unreadDms,
        );
        final lines = chatLines(
          net.messages,
          net.session?.userId,
          filterProfanityEnabled: net.filterChatProfanity,
        );
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final tab in tabs) ...[
                        OutlinedButton(
                          onPressed: tab.enabled
                              ? () => net.selectChatTab(
                                  tab.tab,
                                  widget.locationId,
                                  citadelHub: widget.citadelHub,
                                )
                              : null,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            backgroundColor: tab.selected ? const Color(0x33D4AF37) : null,
                            side: BorderSide(color: tab.selected ? Palette.gold : Palette.edge),
                          ),
                          child: Text(tab.label, maxLines: 1, style: const TextStyle(fontSize: 12)),
                        ),
                        if (tab.tab != tabs.last.tab) const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ),
              if (net.chatTab == ChatTab.guild || net.chatTab == ChatTab.guest)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _viewingGuilds = !_viewingGuilds),
                        child: Text(_viewingGuilds ? 'Back to chat' : chatViewGuildsLabel),
                      ),
                      if (net.guestGuild != null)
                        TextButton(
                          onPressed: net.busy
                              ? null
                              : () async {
                                  await net.leaveGuest(save);
                                  if (mounted) setState(() => _viewingGuilds = false);
                                },
                          child: const Text('Leave guest'),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: _viewingGuilds
                    ? _buildGuildBrowser()
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
                                if (stamp.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  MutedText(stamp),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
              SocialNotice(notice: net.notice),
              if (_viewingGuilds)
                const SizedBox.shrink()
              else if (net.chatTab == ChatTab.dm)
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
                          decoration: const InputDecoration(hintText: 'Message…', counterText: ''),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: net.busy || !net.isSignedIn ? null : _send,
                        child: const Text('Send'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
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
            trailing: OutlinedButton(
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
              child: Text(row.guestLabel),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}
