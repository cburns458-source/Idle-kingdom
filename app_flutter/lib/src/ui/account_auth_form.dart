import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';

/// Email sign-in and sign-up fields shared by the entry gate and Account tab.
class AccountAuthForm extends StatefulWidget {
  const AccountAuthForm({
    super.key,
    required this.controller,
    required this.multiplayer,
    this.usernameSeed = '',
  });

  final GameController controller;
  final MultiplayerController multiplayer;

  /// Prefills the username field when the sheet opens.
  final String usernameSeed;

  @override
  State<AccountAuthForm> createState() => _AccountAuthFormState();
}

class _AccountAuthFormState extends State<AccountAuthForm> {
  late final TextEditingController _email = TextEditingController();
  late final TextEditingController _username = TextEditingController(text: widget.usernameSeed);
  late final TextEditingController _password = TextEditingController();

  MultiplayerController get net => widget.multiplayer;

  @override
  void initState() {
    super.initState();
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
    return ListenableBuilder(
      listenable: net,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('auth-email'),
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const <String>[AutofillHints.email],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('auth-username'),
              controller: _username,
              decoration: const InputDecoration(labelText: 'Username'),
              autofillHints: const <String>[AutofillHints.newUsername],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('auth-password'),
              controller: _password,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: net.busy
                  ? null
                  : () => net.signIn(
                      _email.text,
                      _password.text,
                      widget.controller.save,
                      adopt: widget.controller.adoptAccountSave,
                    ),
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
                      adopt: widget.controller.adoptAccountSave,
                    ),
              child: const Text('Create account'),
            ),
            if (net.mode == MultiplayerMode.supabase) ...<Widget>[
              const SizedBox(height: 6),
              OutlinedButton(
                onPressed: net.busy || _email.text.isEmpty
                    ? null
                    : () => net.sendMagicLink(_email.text),
                child: const Text('Email magic link'),
              ),
            ],
          ],
        );
      },
    );
  }
}
