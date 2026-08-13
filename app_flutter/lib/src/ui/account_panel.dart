import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'social_bits.dart';

/// Signing in, syncing, and signing out.
///
/// Multiplayer is optional everywhere: a player who never fills this in still
/// has a complete game, which is what the mode line says out loud.
class AccountPanel extends StatefulWidget {
  const AccountPanel({super.key, required this.controller, required this.multiplayer});

  final GameController controller;
  final MultiplayerController multiplayer;

  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<AccountPanel> {
  late final TextEditingController _email = TextEditingController();
  late final TextEditingController _username = TextEditingController(
    text: widget.controller.save.characterName ?? '',
  );
  late final TextEditingController _password = TextEditingController();

  MultiplayerController get net => widget.multiplayer;

  @override
  void initState() {
    super.initState();
    // The magic-link button is only offered once there is an address to send to,
    // so the form repaints as the field fills.
    _email.addListener(_onEmailChanged);
  }

  void _onEmailChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _email.removeListener(_onEmailChanged);
    _email.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

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
        if (session == null) ..._signInForm() else ..._signedIn(session),
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
        onPressed: net.busy ? null : () => net.pushSave(widget.controller.save),
        child: const Text('Sync cloud save'),
      ),
      const SizedBox(height: 6),
      OutlinedButton(
        onPressed: net.busy
            ? null
            : () => net.pullSave((save) => widget.controller.commit(save)),
        child: const Text('Load cloud save'),
      ),
      const SizedBox(height: 6),
      OutlinedButton(
        onPressed: net.busy ? null : () => net.signOut(widget.controller.save),
        child: const Text('Sign out'),
      ),
    ];
  }

  List<Widget> _signInForm() {
    return <Widget>[
      TextField(
        controller: _email,
        decoration: const InputDecoration(labelText: 'Email'),
        keyboardType: TextInputType.emailAddress,
        autofillHints: const <String>[AutofillHints.email],
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _username,
        decoration: const InputDecoration(labelText: 'Username'),
        autofillHints: const <String>[AutofillHints.newUsername],
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _password,
        decoration: const InputDecoration(labelText: 'Password'),
        obscureText: true,
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: net.busy
            ? null
            : () => net.signIn(_email.text, _password.text, widget.controller.save),
        child: const Text('Sign in'),
      ),
      const SizedBox(height: 6),
      OutlinedButton(
        onPressed: net.busy
            ? null
            : () => net.signUp(
                _email.text,
                _username.text.isEmpty ? 'Adventurer' : _username.text,
                _password.text,
                widget.controller.save,
              ),
        child: const Text('Create account'),
      ),
      // Only a hosted backend can send mail, so a local build never offers it.
      if (net.mode == MultiplayerMode.supabase) ...<Widget>[
        const SizedBox(height: 6),
        OutlinedButton(
          onPressed: net.busy || _email.text.isEmpty
              ? null
              : () => net.sendMagicLink(_email.text),
          child: const Text('Email magic link'),
        ),
      ],
    ];
  }
}
