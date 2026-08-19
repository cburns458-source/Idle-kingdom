import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'social_bits.dart';

/// Opens a player's public profile in a modal sheet.
Future<void> openPlayerProfile(
  BuildContext context, {
  required GameController controller,
  required MultiplayerController multiplayer,
  required String userId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.parchmentDeep,
    builder: (context) => PlayerProfileSheet(
      controller: controller,
      multiplayer: multiplayer,
      userId: userId,
    ),
  );
}

/// Portrait, summary, skills, and friend / ignore / DM actions for one account.
class PlayerProfileSheet extends StatefulWidget {
  const PlayerProfileSheet({
    super.key,
    required this.controller,
    required this.multiplayer,
    required this.userId,
  });

  final GameController controller;
  final MultiplayerController multiplayer;
  final String userId;

  @override
  State<PlayerProfileSheet> createState() => _PlayerProfileSheetState();
}

class _PlayerProfileSheetState extends State<PlayerProfileSheet> {
  final TextEditingController _dm = TextEditingController();
  PublicPlayerProfile? _profile;
  String? _loadError;
  bool _loading = true;

  MultiplayerController get net => widget.multiplayer;

  bool get _isSelf => net.session?.userId == widget.userId;

  String _skillName(String? skillId) {
    if (skillId == null) return 'Adventuring';
    return widget.controller.indexes.skillsById[skillId]?.displayName ?? skillId;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await net.publicProfile(widget.userId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _profile = profile;
      _loadError = profile == null ? 'That player could not be found.' : null;
    });
  }

  @override
  void dispose() {
    _dm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: net,
      builder: (context, _) {
        final profile = _profile;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              top: 12,
              bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
            ),
            child: _loading
                ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
                : profile == null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      MutedText(_loadError ?? 'That player could not be found.'),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  )
                : _buildBody(publicProfileView(profile, _skillName)),
          ),
        );
      },
    );
  }

  Widget _buildBody(PublicProfileView view) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Player profile',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
                    if (_isSelf) const MutedText('This is you.'),
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
          if (!_isSelf && net.isSignedIn) ...[
            const SizedBox(height: 10),
            ..._profileActions(view.userId),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dm,
                    maxLength: 240,
                    decoration: const InputDecoration(
                      labelText: 'Private message',
                      counterText: '',
                    ),
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
          ],
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
