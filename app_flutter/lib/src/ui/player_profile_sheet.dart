import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'game_image.dart';
import 'game_popup.dart';
import 'item_icon.dart';
import 'player_gear_sheet.dart';
import 'social_bits.dart';

/// Opens a player's public profile as a centered card.
Future<void> openPlayerProfile(
  BuildContext context, {
  required GameController controller,
  required MultiplayerController multiplayer,
  required String userId,
}) {
  return showGamePopup<void>(
    context: context,
    origin: popupOrigin(context),
    builder: (context) =>
        PlayerProfileSheet(controller: controller, multiplayer: multiplayer, userId: userId),
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
    final profile = await net.publicProfile(widget.userId, db: widget.controller.db);
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
        return GamePopupCard(
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
                    GameButton(
                      label: 'Close',
                      tone: GameButtonTone.secondary,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                )
              : _buildBody(publicProfileView(_displayProfile(profile), _skillName)),
        );
      },
    );
  }

  PublicPlayerProfile _displayProfile(PublicPlayerProfile profile) {
    if (_isSelf) {
      final save = widget.controller.save;
      return PublicPlayerProfile(
        userId: profile.userId,
        username: profile.username,
        appearance: save.appearance,
        raceId: save.raceId,
        guildName: profile.guildName,
        publicSkills: profile.publicSkills,
        achievementsUnlocked: profile.achievementsUnlocked,
        totalLevel: totalLevel(save),
        logCompletionPercent: logCompletion(widget.controller.db, save).overall.percent,
        publicEquipment: publicEquipmentFromSave(save),
      );
    }
    return profile;
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
                ),
              ),
              GameButton(
                label: 'Close',
                tone: GameButtonTone.secondary,
                compact: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GamePanel(
            framed: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SocialPortrait(
                  appearance: view.appearance,
                  raceId: view.raceId,
                  size: 156,
                  height: 156,
                  fullArt: true,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              view.username,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                                color: Palette.panelInk,
                              ),
                            ),
                          ),
                          if (_isSelf || _profile?.publicEquipment != null)
                            IconButton(
                              tooltip: 'Gear',
                              color: Palette.panelInk,
                              onPressed: () => openPlayerGear(
                                context,
                                controller: widget.controller,
                                username: view.username,
                                equipment: _isSelf
                                    ? publicEquipmentFromSave(widget.controller.save)
                                    : _profile?.publicEquipment,
                              ),
                              icon: const SlotGlyph(slotId: 'SLOT-0004', size: 28),
                            ),
                        ],
                      ),
                      MutedText(view.summaryLine),
                      if (_isSelf) const MutedText('This is you.'),
                      const SizedBox(height: 8),
                      _skillIconGrid(_profile!),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
                GameButton(
                  label: 'Private',
                  compact: true,
                  onPressed: net.busy
                      ? null
                      : () async {
                          await net.sendDirectMessage(
                            view.userId,
                            _dm.text,
                            username: view.username,
                          );
                          if (mounted) _dm.clear();
                        },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _skillIconGrid(PublicPlayerProfile profile) {
    final levels = <String, num>{for (final line in profile.publicSkills) line.skillId: line.level};
    if (_isSelf) {
      for (final skill in widget.controller.save.skills) {
        levels[skill.skillId] = getSkillProgress(widget.controller.save, skill.skillId).level;
      }
    } else if (profile.publicSkills.isEmpty) {
      return MutedText(profile.totalLevel >= 1 ? 'Skills hidden' : 'Not submitted');
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final skill in widget.controller.db.skills)
          Tooltip(
            message: skill.displayName,
            child: SizedBox(
              width: 36,
              child: Column(
                children: [
                  GameImage(skillIconPath(skill), width: 28, height: 28),
                  Text(
                    levels[skill.skillId] == null ? '—' : '${levels[skill.skillId]}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                      color: Palette.panelInk,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _profileActions(String userId) {
    if (net.isIgnored(userId)) {
      return <Widget>[
        GameButton(
          label: 'Unignore',
          tone: GameButtonTone.secondary,
          compact: true,
          onPressed: net.busy ? null : () => net.unignorePlayer(userId),
        ),
      ];
    }
    return <Widget>[
      if (net.isFriend(userId))
        GameButton(
          label: 'Remove friend',
          tone: GameButtonTone.secondary,
          compact: true,
          onPressed: net.busy ? null : () => net.removeFriend(userId),
        )
      else if (net.hasOutgoingRequestTo(userId))
        const MutedText('Friend request sent.')
      else
        GameButton(
          label: net.hasIncomingRequestFrom(userId) ? 'Accept friend' : 'Friend request',
          tone: GameButtonTone.secondary,
          compact: true,
          onPressed: net.busy ? null : () => net.sendFriendRequest(userId),
        ),
      const SizedBox(height: 8),
      GameButton(
        label: 'Ignore',
        tone: GameButtonTone.secondary,
        compact: true,
        onPressed: net.busy ? null : () => net.ignorePlayer(userId),
      ),
    ];
  }
}
