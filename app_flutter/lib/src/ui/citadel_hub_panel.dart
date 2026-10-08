import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'format.dart';

/// The Citadel bounty board, opened from a location the way a shop is.
///
/// It ticks while it is on screen so the hour's rotation stays current, and
/// stops as soon as it closes.
class CitadelHubPanel extends StatefulWidget {
  const CitadelHubPanel({
    super.key,
    required this.tab,
    required this.controller,
    required this.multiplayer,
    required this.onClose,
  });

  final CitadelHubTab tab;
  final GameController controller;
  final MultiplayerController multiplayer;
  final VoidCallback onClose;

  @override
  State<CitadelHubPanel> createState() => _CitadelHubPanelState();
}

class _CitadelHubPanelState extends State<CitadelHubPanel> {
  Timer? _ticker;

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
      net.refreshBountyClaims(hourlyBountyBoard(nowMs).hourKey);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Clears last hour's counters, so the board and the save agree on the hour.
  void _syncHour() {
    final save = controller.save;
    final synced = syncBountyHour(save, nowMs);
    if (synced.bountyHourKey != save.bountyHourKey) {
      controller.commit(synced, command: 'sync_bounty_hour');
    }
  }

  Future<void> _turnIn(BountyDefinition bounty) async {
    await net.turnIn(bounty, controller.save, nowMs, controller.commit);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: net, builder: (context, _) => _buildBounties());
  }

  Widget _buildBounties() {
    final board = hourlyBountyBoard(nowMs);
    final remainingMs = (board.expiresAtMs - nowMs).clamp(0, board.expiresAtMs);
    final save = syncBountyHour(controller.save, nowMs);
    final rows = bountyRows(save, board, net.bountyClaims, net.isSignedIn, nowMs);
    return _frame(
      title: citadelHubTabLabels[widget.tab]!,
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
                    Text(
                      title,
                      style: const TextStyle(fontSize: GameFont.l, fontWeight: FontWeight.w400),
                    ),
                    MutedText(subtitle),
                  ],
                ),
              ),
              GameIconButton(icon: Icons.close, tooltip: 'Close', onPressed: widget.onClose),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
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
                Text(row.title, style: const TextStyle(fontWeight: FontWeight.w400)),
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
