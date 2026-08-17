import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'account_auth_form.dart';
import 'social_bits.dart';

/// Signing in and signing out.
///
/// New players sign in on the entry gate before character creation; this panel
/// is for returning players to sign out and manage friends.
class AccountPanel extends StatefulWidget {
  const AccountPanel({super.key, required this.controller, required this.multiplayer});

  final GameController controller;
  final MultiplayerController multiplayer;

  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<AccountPanel> {
  MultiplayerController get net => widget.multiplayer;

  @override
  Widget build(BuildContext context) {
    final session = net.session;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        MutedText(multiplayerModeLine(net.mode)),
        const SizedBox(height: 12),
        if (session == null)
          AccountAuthForm(
            controller: widget.controller,
            multiplayer: net,
            usernameSeed: widget.controller.save.characterName ?? '',
          )
        else
          ..._signedIn(session),
        SocialNotice(notice: net.notice),
      ],
    );
  }

  List<Widget> _signedIn(MultiplayerSession session) {
    return <Widget>[
      Text(
        'Signed in as ${session.username}',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      MutedText(session.email),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: net.busy ? null : () => net.signOut(widget.controller.save),
        child: const Text('Sign out'),
      ),
      const SizedBox(height: 20),
      ..._peopleSection('Friends', net.friends, empty: 'No friends yet.'),
      if (net.incomingFriendRequests.isNotEmpty) ...[
        const SizedBox(height: 16),
        ..._peopleSection(
          'Friend requests',
          net.incomingFriendRequests,
          trailing: (contact) => OutlinedButton(
            onPressed: net.busy ? null : () => net.sendFriendRequest(contact.userId),
            child: const Text('Accept'),
          ),
        ),
      ],
      if (net.outgoingFriendRequests.isNotEmpty) ...[
        const SizedBox(height: 16),
        ..._peopleSection('Sent requests', net.outgoingFriendRequests, empty: ''),
      ],
      const SizedBox(height: 16),
      ..._peopleSection(
        'Ignored',
        net.ignoredPlayers,
        empty: 'Nobody ignored.',
        trailing: (contact) => OutlinedButton(
          onPressed: net.busy ? null : () => net.unignorePlayer(contact.userId),
          child: const Text('Unignore'),
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
      Text(heading, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
