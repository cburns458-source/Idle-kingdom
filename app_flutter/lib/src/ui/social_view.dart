import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'account_panel.dart';
import 'guild_panel.dart';
import 'social_bits.dart';

enum SocialTab { leaderboards, guilds, citadel, account }

/// The social screen: boards, guilds, who is in the Citadel, and the account
/// that makes the other three work.
///
/// Every tab reads its rows through the shared view models, so the lists here
/// say exactly what the web client's lists say.
class SocialView extends StatefulWidget {
  const SocialView({super.key, required this.controller, required this.multiplayer});

  final GameController controller;
  final MultiplayerController multiplayer;

  @override
  State<SocialView> createState() => _SocialViewState();
}

class _SocialViewState extends State<SocialView> {
  SocialTab _tab = SocialTab.leaderboards;

  MultiplayerController get net => widget.multiplayer;

  @override
  void initState() {
    super.initState();
    // Opening the screen is the moment to look: nothing polls while it is shut.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) net.refresh(widget.controller.save);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: net,
      builder: (context, _) => Column(
        children: [
          _TabBar(tab: _tab, onSelect: (tab) => setState(() => _tab = tab)),
          Expanded(child: _buildTab()),
        ],
      ),
    );
  }

  Widget _buildTab() {
    switch (_tab) {
      case SocialTab.account:
        return AccountPanel(controller: widget.controller, multiplayer: net);
      case SocialTab.guilds:
        if (!net.isSignedIn) {
          return const SignedOutNotice(title: 'Guilds', prompt: guildSignInPrompt);
        }
        return GuildPanel(controller: widget.controller, multiplayer: net);
      case SocialTab.citadel:
        if (!net.isSignedIn) {
          return const SignedOutNotice(title: 'Citadel', prompt: signInPrompt);
        }
        return _CitadelTab(multiplayer: net);
      case SocialTab.leaderboards:
        if (!net.isSignedIn) {
          return const SignedOutNotice(title: 'Leaderboards', prompt: signInPrompt);
        }
        return _LeaderboardTab(multiplayer: net);
    }
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.tab, required this.onSelect});

  final SocialTab tab;
  final ValueChanged<SocialTab> onSelect;

  static const Map<SocialTab, String> _labels = <SocialTab, String>{
    SocialTab.leaderboards: 'Boards',
    SocialTab.guilds: 'Guilds',
    SocialTab.citadel: 'Citadel',
    SocialTab.account: 'Account',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          for (final entry in _labels.entries) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: () => onSelect(entry.key),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                  backgroundColor: entry.key == tab ? const Color(0x33D4AF37) : null,
                  side: BorderSide(color: entry.key == tab ? Palette.gold : Palette.edge),
                ),
                child: Text(
                  entry.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            if (entry.key != SocialTab.account) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _LeaderboardTab extends StatelessWidget {
  const _LeaderboardTab({required this.multiplayer});

  final MultiplayerController multiplayer;

  @override
  Widget build(BuildContext context) {
    final boards = boardOptions(multiplayer.db);
    final rows = leaderboardRows(multiplayer.board);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        DropdownButtonFormField<MultiplayerBoardKey>(
          initialValue: multiplayer.boardKey,
          decoration: const InputDecoration(labelText: 'Board'),
          items: boards
              .map(
                (board) => DropdownMenuItem<MultiplayerBoardKey>(
                  value: board.key,
                  child: Text(board.label),
                ),
              )
              .toList(),
          onChanged: (key) {
            if (key != null) multiplayer.selectBoard(key);
          },
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          MutedText(emptyBoardMessage(multiplayer.boardKey))
        else
          for (final row in rows) ...[
            SocialRow(
              title: row.username,
              subtitle: row.subtitle,
              leading: row.emblem == null
                  ? SocialPortrait(appearance: row.appearance)
                  : GuildEmblemBadge(emblem: row.emblem!),
              trailing: Row(
                children: [
                  Text(row.valueLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
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
              leading: SocialPortrait(appearance: visitor.appearance),
            ),
            const SizedBox(height: 6),
          ],
      ],
    );
  }
}
