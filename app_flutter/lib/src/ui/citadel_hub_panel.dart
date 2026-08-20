import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'format.dart';

/// The Citadel's two boards, opened from a location the way a shop is.
///
/// Both need the clock second by second — the bounty board rotates on the hour
/// and the Bazaar is read as others post — so this ticks while it is on screen
/// and stops as soon as it closes.
class CitadelHubPanel extends StatefulWidget {
  const CitadelHubPanel({
    super.key,
    required this.tab,
    required this.controller,
    required this.multiplayer,
    required this.onClose,
    this.onOpenGuilds,
  });

  final CitadelHubTab tab;
  final GameController controller;
  final MultiplayerController multiplayer;
  final VoidCallback onClose;

  /// Offered next to a recruitment post, since that is what it is for.
  final VoidCallback? onOpenGuilds;

  @override
  State<CitadelHubPanel> createState() => _CitadelHubPanelState();
}

class _CitadelHubPanelState extends State<CitadelHubPanel> {
  Timer? _ticker;
  BazaarPostKind _kind = bazaarPostMessage;
  final TextEditingController _body = TextEditingController();

  GameController get controller => widget.controller;
  MultiplayerController get net => widget.multiplayer;
  num get nowMs => controller.session.clock();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Whatever another panel last said is not about this board.
      net.announce(null);
      _syncHour();
      if (widget.tab == CitadelHubTab.bounties) {
        net.refreshBountyClaims(hourlyBountyBoard(nowMs).hourKey);
      } else {
        net.refreshBazaar();
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _body.dispose();
    super.dispose();
  }

  /// Clears last hour's counters, so the board and the save agree on the hour.
  void _syncHour() {
    final save = controller.save;
    final synced = syncBountyHour(save, nowMs);
    if (synced.bountyHourKey != save.bountyHourKey) controller.commit(synced);
  }

  Future<void> _turnIn(BountyDefinition bounty) async {
    await net.turnIn(bounty, controller.save, nowMs, controller.commit);
  }

  Future<void> _post() async {
    final body = _body.text;
    await net.postToBazaar(_kind, body);
    if (!mounted) return;
    if (net.notice == bazaarPostedNotice) _body.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: net,
      builder: (context, _) =>
          widget.tab == CitadelHubTab.bounties ? _buildBounties() : _buildBazaar(),
    );
  }

  Widget _buildBounties() {
    final board = hourlyBountyBoard(nowMs);
    final remainingMs = (board.expiresAtMs - nowMs).clamp(0, board.expiresAtMs);
    final save = syncBountyHour(controller.save, nowMs);
    final rows = bountyRows(save, board, net.bountyClaims, net.isSignedIn, nowMs);
    return _frame(
      title: citadelHubTabLabels[CitadelHubTab.bounties]!,
      subtitle: bountyRotationLine(formatDurationMs(remainingMs)),
      children: [
        if (!net.isSignedIn) ...[const MutedText(bountySignInNotice), const SizedBox(height: 8)],
        for (final (index, row) in rows.indexed) ...[
          if (index > 0) const SizedBox(height: 8),
          _BountyCard(row: row, busy: net.busy, onTurnIn: () => _turnIn(board.bounties[index])),
        ],
      ],
    );
  }

  Widget _buildBazaar() {
    final rows = bazaarRows(net.bazaarPosts);
    return _frame(
      title: citadelHubTabLabels[CitadelHubTab.bazaar]!,
      subtitle: bazaarBlurb,
      children: [
        if (!net.isSignedIn)
          const MutedText(bazaarSignInNotice)
        else
          _Compose(
            kind: _kind,
            body: _body,
            busy: net.busy,
            onKind: (kind) => setState(() => _kind = kind),
            onPost: _post,
            onOpenGuilds: _kind == bazaarPostRecruit ? widget.onOpenGuilds : null,
          ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          const _PostCard(heading: bazaarEmptyHeading, body: bazaarEmptyBody)
        else
          for (final (index, row) in rows.indexed) ...[
            if (index > 0) const SizedBox(height: 8),
            _PostCard(heading: row.heading, body: row.body),
          ],
      ],
    );
  }

  Widget _frame({required String title, required String subtitle, required List<Widget> children}) {
    return GamePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    MutedText(subtitle),
                  ],
                ),
              ),
              GameIconButton(icon: Icons.close, tooltip: 'Close', onPressed: widget.onClose),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _BountyCard extends StatelessWidget {
  const _BountyCard({required this.row, required this.busy, required this.onTurnIn});

  final BountyRowView row;
  final bool busy;
  final VoidCallback onTurnIn;

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                MutedText(row.description),
                MutedText(row.progressLine),
                if (row.firstCompleterLine case final line?) MutedText(line),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GameButton(
            label: row.actionLabel,
            compact: true,
            onPressed: row.canTurnIn && !busy ? onTurnIn : null,
          ),
        ],
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.heading, required this.body});

  final String heading;
  final String body;

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: const TextStyle(fontWeight: FontWeight.w700)),
          MutedText(body),
        ],
      ),
    );
  }
}

/// The compose row: what kind of notice, what it says, and where it goes.
class _Compose extends StatelessWidget {
  const _Compose({
    required this.kind,
    required this.body,
    required this.busy,
    required this.onKind,
    required this.onPost,
    this.onOpenGuilds,
  });

  final BazaarPostKind kind;
  final TextEditingController body;
  final bool busy;
  final ValueChanged<BazaarPostKind> onKind;
  final VoidCallback onPost;
  final VoidCallback? onOpenGuilds;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final option in bazaarKindOptions())
              GameButton(
                label: option.label,
                compact: true,
                selected: option.kind == kind,
                tone: option.kind == kind ? GameButtonTone.primary : GameButtonTone.secondary,
                onPressed: () => onKind(option.kind),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: body,
          maxLength: bazaarBodyMaxLength,
          decoration: const InputDecoration(hintText: bazaarPlaceholder),
          onSubmitted: (_) => onPost(),
        ),
        Row(
          children: [
            Expanded(
              child: GameButton(label: 'Post', onPressed: busy ? null : onPost),
            ),
            if (onOpenGuilds case final openGuilds?) ...[
              const SizedBox(width: 8),
              GameButton(
                label: 'Open Guilds',
                tone: GameButtonTone.secondary,
                compact: true,
                onPressed: openGuilds,
              ),
            ],
          ],
        ),
      ],
    );
  }
}
