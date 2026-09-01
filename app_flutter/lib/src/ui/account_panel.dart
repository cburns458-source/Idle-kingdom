import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'account_auth_form.dart';
import 'format.dart';
import 'player_profile_sheet.dart';
import 'social_bits.dart';

/// Signing in and signing out.
///
/// New players sign in on the entry gate before character creation; this panel
/// is for returning players to sign out and manage friends. On Settings it sits
/// as a section under the toggles.
class AccountPanel extends StatefulWidget {
  const AccountPanel({
    super.key,
    required this.controller,
    required this.multiplayer,
    this.embedded = false,
  });

  final GameController controller;
  final MultiplayerController multiplayer;

  /// True when this lives inside Settings' scroll view.
  final bool embedded;

  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<AccountPanel> {
  MultiplayerController get net => widget.multiplayer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !net.isSignedIn) return;
      net.refresh(widget.controller.save);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[widget.controller, widget.controller.progress, net]),
      builder: (context, _) => _build(),
    );
  }

  Widget _build() {
    final session = net.session;
    final children = <Widget>[
      const Text('Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
      const SizedBox(height: 12),
      _character(),
      const SizedBox(height: 12),
      if (session == null)
        AccountAuthForm(controller: widget.controller, multiplayer: net)
      else
        ..._signedIn(session),
    ];
    if (widget.embedded) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    }
    return ListView(padding: const EdgeInsets.all(12), children: children);
  }

  Widget _character() {
    final save = widget.controller.save;
    return GamePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayNameForSave(save, 'Unnamed'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
          ),
          MutedText('Race: ${raceDisplayName(widget.controller.db, save.raceId) ?? 'Unchosen'}'),
          MutedText('Play time: ${formatPlayTimeMs(save.playTimeMs)}'),
        ],
      ),
    );
  }

  List<Widget> _signedIn(MultiplayerSession session) {
    return <Widget>[
      Text(
        'Signed in as ${session.username}',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
      ),
      MutedText(session.email),
      const SizedBox(height: 12),
      GamePanel(
        child: Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Show gear on profile', style: TextStyle(fontWeight: FontWeight.w400)),
                  MutedText('Let other players open your equipped gear from your profile.'),
                ],
              ),
            ),
            GameSwitch(
              value: net.privacyPublicGear,
              onChanged: net.busy ? null : net.setPrivacyPublicGear,
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      GameButton(
        label: 'Sign out',
        tone: GameButtonTone.secondary,
        onPressed: net.busy ? null : () => net.signOut(widget.controller.save),
      ),
      const SizedBox(height: 20),
      ..._peopleSection('Friends', net.friends, empty: 'No friends yet.', showOnline: true),
      const SizedBox(height: 16),
      ..._peopleSection(
        'Friend requests',
        net.incomingFriendRequests,
        empty: 'No incoming requests.',
        showOnline: true,
        trailing: (contact) => GameButton(
          label: 'Accept',
          compact: true,
          onPressed: net.busy ? null : () => net.sendFriendRequest(contact.userId),
        ),
      ),
      if (net.outgoingFriendRequests.isNotEmpty) ...[
        const SizedBox(height: 16),
        ..._peopleSection('Sent requests', net.outgoingFriendRequests, empty: '', showOnline: true),
      ],
      const SizedBox(height: 16),
      ..._peopleSection(
        'Ignored',
        net.ignoredPlayers,
        empty: 'Nobody ignored.',
        trailing: (contact) => GameButton(
          label: 'Unignore',
          tone: GameButtonTone.secondary,
          compact: true,
          onPressed: net.busy ? null : () => net.unignorePlayer(contact.userId),
        ),
      ),
    ];
  }

  List<Widget> _peopleSection(
    String heading,
    List<SocialContact> people, {
    String empty = '',
    bool showOnline = false,
    Widget Function(SocialContact contact)? trailing,
  }) {
    final rows = showOnline
        ? friendListRows(people, presence: net.presence, nowMs: widget.controller.session.clock())
        : null;
    return <Widget>[
      Text(heading, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400)),
      const SizedBox(height: 6),
      if (people.isEmpty && empty.isNotEmpty)
        MutedText(empty)
      else if (rows != null)
        for (final row in rows) ...[
          SocialRow(
            title: row.username,
            subtitle: row.subtitle,
            leading: SocialPortrait(appearance: row.appearance, raceId: row.raceId),
            trailing: trailing?.call(
              SocialContact(
                userId: row.userId,
                username: row.username,
                appearance: row.appearance,
                raceId: row.raceId,
              ),
            ),
            onTap: () => openPlayerProfile(
              context,
              controller: widget.controller,
              multiplayer: net,
              userId: row.userId,
            ),
          ),
          const SizedBox(height: 6),
        ]
      else
        for (final contact in people) ...[
          SocialRow(
            title: contact.username,
            subtitle: contact.guildName ?? '',
            leading: SocialPortrait(appearance: contact.appearance, raceId: contact.raceId),
            trailing: trailing?.call(contact),
            onTap: () => openPlayerProfile(
              context,
              controller: widget.controller,
              multiplayer: net,
              userId: contact.userId,
            ),
          ),
          const SizedBox(height: 6),
        ],
    ];
  }
}
