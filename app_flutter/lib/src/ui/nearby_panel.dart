import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'game_popup.dart';
import 'player_profile_sheet.dart';
import 'social_bits.dart';

/// Who else is at this location, as a card grown from the nearby chip.
Future<void> showNearbyPopup(
  BuildContext context, {
  required GameController controller,
  required MultiplayerController multiplayer,
  Rect? origin,
}) {
  return showGamePopup<void>(
    context: context,
    origin: origin,
    builder: (context) => NearbyPanel(
      controller: controller,
      multiplayer: multiplayer,
      onClose: () => Navigator.of(context).pop(),
    ),
  );
}

/// Who else is at this location.
///
/// A floating card rather than a screen, because looking at the neighbours must
/// not interrupt the primary activity.
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

  /// `[TAG]Name` when we know their guild tag; otherwise just the name.
  String _peerTitle(ActivityPresence peer) {
    final name = peer.username;
    final tag = guildTagForName(
      peer.guildName,
      ownName: net.guild?.name,
      ownTag: net.guild?.tag,
      listings: net.listings,
    );
    if (tag == null || tag.isEmpty) return name;
    return '[$tag]$name';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: net,
      builder: (context, _) {
        final rows = peerRows(net.peers, _skillName, nowMs: widget.controller.session.clock());
        return GamePopupCard(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 280, minHeight: 160),
            child: _buildPeerList(rows),
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
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
              ),
            ),
            GameButton(
              label: 'Close',
              tone: GameButtonTone.secondary,
              compact: true,
              onPressed: widget.onClose,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (!net.canSeeSocialPages)
          const MutedText(signInPrompt)
        else if (rows.isEmpty)
          const MutedText('No other players here right now.')
        else
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.38),
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
                final subtitle = <String>[row.statusLabel, ?activityName].join(' · ');
                final allied = net.isAlliedUser(row.userId);
                return SocialRow(
                  title: _peerTitle(peer),
                  subtitle: subtitle,
                  leading: SocialPortrait(
                    appearance: peer.appearance,
                    borderColor: allied ? Palette.softGreen : null,
                  ),
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
