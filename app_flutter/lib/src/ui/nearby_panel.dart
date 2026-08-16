import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
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
  final TextEditingController _dm = TextEditingController();
  PublicPlayerProfile? _profile;

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

  @override
  void dispose() {
    _dm.dispose();
    super.dispose();
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
        final rows = peerRows(net.peers, _skillName);
        final profile = _profile;
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
                    child: profile == null
                        ? _buildPeerList(rows)
                        : _buildProfile(publicProfileView(profile, _skillName)),
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
                return SocialRow(
                  title: row.username,
                  subtitle: activityName == null ? row.subtitle : '$activityName · ${row.subtitle}',
                  leading: SocialPortrait(appearance: peer.appearance),
                  onTap: () async {
                    final profile = await net.publicProfile(row.userId);
                    if (mounted) setState(() => _profile = profile);
                  },
                );
              },
            ),
          ),
        SocialNotice(notice: net.notice),
      ],
    );
  }

  Widget _buildProfile(PublicProfileView view) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => setState(() => _profile = null),
                  child: const Text('Back to nearby'),
                ),
              ),
              OutlinedButton(onPressed: widget.onClose, child: const Text('Close')),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              SocialPortrait(appearance: view.appearance, size: 52),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      view.username,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    MutedText(view.summaryLine),
                  ],
                ),
              ),
            ],
          ),
          if (!view.skillsHidden) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: view.skillLines.map((line) => MutedText(line)).toList(),
            ),
          ],
          const SizedBox(height: 10),
          ..._profileActions(view.userId),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dm,
                  maxLength: 240,
                  decoration: const InputDecoration(labelText: 'Private message', counterText: ''),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: net.busy
                    ? null
                    : () async {
                        await net.sendDirectMessage(view.userId, _dm.text);
                        if (mounted) _dm.clear();
                      },
                child: const Text('Private'),
              ),
            ],
          ),
          SocialNotice(notice: net.notice),
        ],
      ),
    );
  }

  List<Widget> _profileActions(String userId) {
    if (net.isIgnored(userId)) {
      return <Widget>[
        OutlinedButton(
          onPressed: net.busy ? null : () => net.unignorePlayer(userId),
          child: const Text('Unignore'),
        ),
      ];
    }
    return <Widget>[
      if (net.isFriend(userId))
        OutlinedButton(
          onPressed: net.busy ? null : () => net.removeFriend(userId),
          child: const Text('Remove friend'),
        )
      else if (net.hasOutgoingRequestTo(userId))
        const MutedText('Friend request sent.')
      else
        OutlinedButton(
          onPressed: net.busy ? null : () => net.sendFriendRequest(userId),
          child: Text(net.hasIncomingRequestFrom(userId) ? 'Accept friend' : 'Friend request'),
        ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: net.busy ? null : () => net.ignorePlayer(userId),
        child: const Text('Ignore'),
      ),
    ];
  }
}
