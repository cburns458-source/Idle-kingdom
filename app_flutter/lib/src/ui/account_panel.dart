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
  late final TextEditingController _motto;

  @override
  void initState() {
    super.initState();
    _motto = TextEditingController(text: widget.controller.save.motto ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !net.isSignedIn) return;
      net.refresh(widget.controller.save);
    });
  }

  @override
  void dispose() {
    _motto.dispose();
    super.dispose();
  }

  Future<void> _saveMotto() async {
    final cleaned = normalizeMotto(_motto.text);
    widget.controller.commit(widget.controller.save.copyWith(motto: cleaned));
    _motto.text = cleaned ?? '';
    if (net.isSignedIn) {
      await net.flushAccountSave(widget.controller.save);
      await net.publishRanking(widget.controller.save, ignoreDebounce: true);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        widget.controller,
        widget.controller.progress,
        net,
      ]),
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
          const SizedBox(height: 10),
          TextField(
            controller: _motto,
            maxLength: mottoMaxLength,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Motto',
              hintText: 'Shown under your portrait',
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: GameButton(
              label: 'Save',
              compact: true,
              onPressed: net.busy ? null : _saveMotto,
            ),
          ),
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
      _PeopleFold(
        heading: 'Friends',
        empty: 'No friends yet.',
        people: net.friends,
        showOnline: true,
        nowMs: widget.controller.session.clock(),
        presence: net.presence,
        onOpen: (contact) => openPlayerProfile(
          context,
          controller: widget.controller,
          multiplayer: net,
          userId: contact.userId,
        ),
      ),
      const SizedBox(height: 10),
      _PeopleFold(
        heading: 'Friend requests',
        empty: 'No incoming requests.',
        people: net.incomingFriendRequests,
        showOnline: true,
        nowMs: widget.controller.session.clock(),
        presence: net.presence,
        trailing: (contact) => GameTextButton(
          label: 'Accept',
          onPressed: net.busy ? null : () => net.sendFriendRequest(contact.userId),
        ),
        onOpen: (contact) => openPlayerProfile(
          context,
          controller: widget.controller,
          multiplayer: net,
          userId: contact.userId,
        ),
      ),
      if (net.outgoingFriendRequests.isNotEmpty) ...[
        const SizedBox(height: 10),
        _PeopleFold(
          heading: 'Sent requests',
          people: net.outgoingFriendRequests,
          showOnline: true,
          nowMs: widget.controller.session.clock(),
          presence: net.presence,
          onOpen: (contact) => openPlayerProfile(
            context,
            controller: widget.controller,
            multiplayer: net,
            userId: contact.userId,
          ),
        ),
      ],
      const SizedBox(height: 10),
      _PeopleFold(
        heading: 'Ignored',
        empty: 'Nobody ignored.',
        people: net.ignoredPlayers,
        trailing: (contact) => GameTextButton(
          label: 'Unignore',
          onPressed: net.busy ? null : () => net.unignorePlayer(contact.userId),
        ),
        onOpen: (contact) => openPlayerProfile(
          context,
          controller: widget.controller,
          multiplayer: net,
          userId: contact.userId,
        ),
      ),
    ];
  }
}

class _PeopleFold extends StatefulWidget {
  const _PeopleFold({
    required this.heading,
    required this.people,
    required this.onOpen,
    this.empty = '',
    this.showOnline = false,
    this.nowMs = 0,
    this.presence = const <ActivityPresence>[],
    this.trailing,
  });

  final String heading;
  final String empty;
  final List<SocialContact> people;
  final bool showOnline;
  final num nowMs;
  final List<ActivityPresence> presence;
  final Widget Function(SocialContact contact)? trailing;
  final ValueChanged<SocialContact> onOpen;

  @override
  State<_PeopleFold> createState() => _PeopleFoldState();
}

class _PeopleFoldState extends State<_PeopleFold> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.heading,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
                  ),
                ),
                if (widget.people.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: MutedText('${widget.people.length}'),
                  ),
                Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: UiChrome.of(context).panelInk,
                ),
              ],
            ),
          ),
        ),
        if (_open) ..._rows(),
      ],
    );
  }

  List<Widget> _rows() {
    if (widget.people.isEmpty && widget.empty.isNotEmpty) {
      return <Widget>[MutedText(widget.empty)];
    }
    if (widget.showOnline) {
      final rows = friendListRows(widget.people, presence: widget.presence, nowMs: widget.nowMs);
      return <Widget>[
        for (final row in rows) ...[
          SocialRow(
            title: row.username,
            subtitle: row.subtitle,
            leading: SocialPortrait(appearance: row.appearance, raceId: row.raceId),
            trailing: widget.trailing?.call(
              SocialContact(
                userId: row.userId,
                username: row.username,
                appearance: row.appearance,
                raceId: row.raceId,
              ),
            ),
            onTap: () => widget.onOpen(
              SocialContact(
                userId: row.userId,
                username: row.username,
                appearance: row.appearance,
                raceId: row.raceId,
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ];
    }
    return <Widget>[
      for (final contact in widget.people) ...[
        SocialRow(
          title: contact.username,
          subtitle: contact.guildName ?? '',
          leading: SocialPortrait(appearance: contact.appearance, raceId: contact.raceId),
          trailing: widget.trailing?.call(contact),
          onTap: () => widget.onOpen(contact),
        ),
        const SizedBox(height: 6),
      ],
    ];
  }
}
