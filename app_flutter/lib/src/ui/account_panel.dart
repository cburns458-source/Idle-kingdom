import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'account_auth_form.dart';
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
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: net, builder: (context, _) => _build());
  }

  Widget _build() {
    final session = net.session;
    final children = <Widget>[
      const Text('Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
      const SizedBox(height: 4),
      MutedText(multiplayerModeLine(net.mode)),
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
      GameButton(
        label: 'Sign out',
        tone: GameButtonTone.secondary,
        onPressed: net.busy ? null : () => net.signOut(widget.controller.save),
      ),
      const SizedBox(height: 20),
      ..._peopleSection('Friends', net.friends, empty: 'No friends yet.'),
      const SizedBox(height: 16),
      ..._peopleSection(
        'Friend requests',
        net.incomingFriendRequests,
        empty: 'No incoming requests.',
        trailing: (contact) => GameButton(
          label: 'Accept',
          compact: true,
          onPressed: net.busy ? null : () => net.sendFriendRequest(contact.userId),
        ),
      ),
      if (net.outgoingFriendRequests.isNotEmpty) ...[
        const SizedBox(height: 16),
        ..._peopleSection('Sent requests', net.outgoingFriendRequests, empty: ''),
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
    Widget Function(SocialContact contact)? trailing,
  }) {
    return <Widget>[
      Text(heading, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400)),
      const SizedBox(height: 6),
      if (people.isEmpty && empty.isNotEmpty)
        MutedText(empty)
      else
        for (final contact in people) ...[
          SocialRow(
            title: contact.username,
            subtitle: contact.guildName ?? '',
            leading: SocialPortrait(appearance: contact.appearance),
            trailing: trailing?.call(contact),
          ),
          const SizedBox(height: 6),
        ],
    ];
  }
}
