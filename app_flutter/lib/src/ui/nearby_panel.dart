import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'player_profile_sheet.dart';
import 'social_bits.dart';

/// Who else is at this location.
///
/// A sheet rather than a screen, because looking at the neighbours must not
/// interrupt the primary activity.
class NearbyPanel extends StatefulWidget {
  const NearbyPanel({
    super.key,
    required this.controller,
    required this.multiplayer,
    required this.onClose,
  });

  final GameController controller;
  final MultiplayerController multiplayer;
  final VoidCallback onClose;

  @override
  State<NearbyPanel> createState() => _NearbyPanelState();
}

class _NearbyPanelState extends State<NearbyPanel> {
  MultiplayerController get net => widget.multiplayer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (net.isSignedIn) {
        unawaited(net.publishPresence(widget.controller.save));
      } else if (net.canBrowseSocial) {
        unawaited(net.refresh(widget.controller.save));
      }
    });
  }

  String _skillName(String? skillId) {
    if (skillId == null) return 'Adventuring';
    return widget.controller.indexes.skillsById[skillId]?.displayName ?? skillId;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: net,
      builder: (context, _) {
        final rows = peerRows(net.peers, _skillName, nowMs: widget.controller.session.clock());
        return Positioned.fill(
          child: ColoredBox(
            color: const Color(0xAA0C0805),
            child: GestureDetector(
              onTap: widget.onClose,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 460),
                    decoration: const BoxDecoration(
                      gradient: Palette.frameGradient,
                      border: Border(top: BorderSide(color: Palette.edge)),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: _buildPeerList(rows),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPeerList(List<PeerRowView> rows) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Nearby adventurers',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            OutlinedButton(onPressed: widget.onClose, child: const Text('Close')),
          ],
        ),
        const SizedBox(height: 8),
        if (!net.canSeeSocialPages)
          const MutedText(signInPrompt)
        else if (rows.isEmpty)
          const MutedText('No other players here right now.')
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final row = rows[index];
                final peer = net.peers[index];
                final activity = peer.currentActivityId == null
                    ? null
                    : widget.controller.indexes.activitiesById[peer.currentActivityId!];
                final activityName = activity?.contextualName ?? activity?.internalKey;
                final subtitle = <String>[row.statusLabel, ?activityName, row.subtitle].join(' · ');
                return SocialRow(
                  title: row.username,
                  subtitle: subtitle,
                  leading: SocialPortrait(appearance: peer.appearance),
                  onTap: () => openPlayerProfile(
                    context,
                    controller: widget.controller,
                    multiplayer: net,
                    userId: row.userId,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
