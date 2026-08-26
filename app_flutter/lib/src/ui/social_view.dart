import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'account_panel.dart';
import 'catalog_popup.dart';
import 'guild_panel.dart';
import 'page_header.dart';
import 'player_profile_sheet.dart';
import 'social_bits.dart';

enum SocialTab { leaderboards, guilds, citadel, account }

/// One social destination from the chin nest: boards, guilds, the Citadel, or
/// the account that makes the others work.
///
/// Every section reads its rows through the shared view models, so the lists
/// here say exactly what the web client's lists say.
class SocialView extends StatefulWidget {
  const SocialView({
    super.key,
    required this.controller,
    required this.multiplayer,
    required this.section,
    this.onTravelToHall,
    this.onClose,
  });

  final GameController controller;
  final MultiplayerController multiplayer;
  final SocialTab section;
  final VoidCallback? onTravelToHall;
  final VoidCallback? onClose;

  @override
  State<SocialView> createState() => _SocialViewState();
}

class _SocialViewState extends State<SocialView> {
  MultiplayerController get net => widget.multiplayer;

  @override
  void initState() {
    super.initState();
    // Opening the screen is the moment to look: nothing polls while it is shut.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadSection();
    });
  }

  @override
  void didUpdateWidget(SocialView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) {
      _loadSection();
    }
  }

  Future<void> _loadSection() {
    if (widget.section == SocialTab.leaderboards) {
      return net.openLeaderboards(widget.controller.save);
    }
    return net.refresh(widget.controller.save);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: net, builder: (context, _) => _buildSection());
  }

  Widget _buildSection() {
    switch (widget.section) {
      case SocialTab.account:
        return _withHeader(
          'Account',
          AccountPanel(controller: widget.controller, multiplayer: net),
        );
      case SocialTab.guilds:
        if (!net.canSeeSocialPages) {
          return _withHeader(
            'Guilds',
            const SignedOutNotice(title: 'Guilds', prompt: guildSignInPrompt, showTitle: false),
          );
        }
        return GuildPanel(
          controller: widget.controller,
          multiplayer: net,
          onTravelToHall: widget.onTravelToHall,
          onClose: widget.onClose,
        );
      case SocialTab.citadel:
        if (!net.canSeeSocialPages) {
          return _withHeader(
            'Citadel',
            const SignedOutNotice(title: 'Citadel', prompt: signInPrompt, showTitle: false),
          );
        }
        return _withHeader('Citadel', _CitadelTab(multiplayer: net));
      case SocialTab.leaderboards:
        if (!net.canSeeSocialPages) {
          return _withHeader(
            'Leaderboards',
            const SignedOutNotice(title: 'Leaderboards', prompt: signInPrompt, showTitle: false),
          );
        }
        return _withHeader(
          'Leaderboards',
          _LeaderboardTab(controller: widget.controller, multiplayer: net),
        );
    }
  }

  Widget _withHeader(String title, Widget body) {
    if (widget.onClose == null) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(title: title, onClose: widget.onClose!),
        Expanded(child: body),
      ],
    );
  }
}

class _LeaderboardTab extends StatelessWidget {
  const _LeaderboardTab({required this.controller, required this.multiplayer});

  final GameController controller;
  final MultiplayerController multiplayer;

  @override
  Widget build(BuildContext context) {
    final boards = boardOptions(multiplayer.db);
    final rows = leaderboardRows(
      multiplayer.board,
      tagForGuildName: (name) => guildTagForName(
        name,
        ownName: multiplayer.guild?.name,
        ownTag: multiplayer.guild?.tag,
        listings: multiplayer.listings,
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        GameSelectField(
          label: 'Board',
          value:
              boards
                  .where((board) => board.key == multiplayer.boardKey)
                  .map((board) => board.label)
                  .firstOrNull ??
              'Board',
          onPressed: () async {
            final chosen = await showGameCatalogPopup(
              context: context,
              eyebrow: 'Board',
              title: 'Leaderboards',
              selectable: true,
              entries: [
                for (final board in boards)
                  CatalogPopupEntry(
                    title: board.label,
                    emphasized: board.key == multiplayer.boardKey,
                  ),
              ],
            );
            if (chosen == null) return;
            await multiplayer.selectBoard(boards[chosen].key, controller.save);
          },
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          MutedText(emptyBoardMessage(multiplayer.boardKey))
        else
          for (final row in rows) ...[
            SocialRow(
              highlight: row.isGuild
                  ? row.entryId == multiplayer.guildId
                  : row.entryId == multiplayer.session?.userId,
              title: row.username,
              subtitle: row.subtitle,
              leading: row.emblem == null
                  ? SocialPortrait(appearance: row.appearance, raceId: row.raceId)
                  : GuildEmblemBadge(emblem: row.emblem!),
              onTap: row.isGuild
                  ? null
                  : () => openPlayerProfile(
                      context,
                      controller: controller,
                      multiplayer: multiplayer,
                      userId: row.entryId,
                    ),
              trailing: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(row.valueLabel, style: const TextStyle(fontWeight: FontWeight.w400)),
                      if (row.secondaryLabel != null) MutedText(row.secondaryLabel!),
                    ],
                  ),
                  const SizedBox(width: 6),
                  MutedText('#${row.rank}'),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
      ],
    );
  }
}

class _CitadelTab extends StatelessWidget {
  const _CitadelTab({required this.multiplayer});

  final MultiplayerController multiplayer;

  @override
  Widget build(BuildContext context) {
    final visitors = multiplayer.citadelVisitors;
    final summary = citadelHubSummary(visitors.length);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(summary.note),
        const SizedBox(height: 4),
        MutedText('Plaza presence: ${summary.visitorCount} · Chat channel: ${summary.chatChannel}'),
        const SizedBox(height: 10),
        if (visitors.isEmpty)
          const MutedText(
            'No visitors on the Plaza right now. Travel to The Citadel to meet others.',
          )
        else
          for (final visitor in visitors) ...[
            SocialRow(
              title: visitor.username,
              subtitle: citadelVisitorSubtitle(visitor),
              leading: SocialPortrait(appearance: visitor.appearance, raceId: visitor.raceId),
            ),
            const SizedBox(height: 6),
          ],
      ],
    );
  }
}
