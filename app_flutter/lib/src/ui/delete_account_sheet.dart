import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';

/// Re-auth, then type the character name, then request deletion.
class DeleteAccountSheet extends StatefulWidget {
  const DeleteAccountSheet({
    super.key,
    required this.controller,
    required this.multiplayer,
    this.embedded = false,
  });

  final GameController controller;
  final MultiplayerController multiplayer;
  final bool embedded;

  @override
  State<DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<DeleteAccountSheet> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _name = TextEditingController();
  String? _error;
  bool _reauthed = false;
  bool _busy = false;

  MultiplayerController get net => widget.multiplayer;

  @override
  void dispose() {
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _reauth() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final email = net.session?.email ?? '';
    if (email.isEmpty) {
      setState(() {
        _busy = false;
        _error = 'Sign in again to confirm.';
      });
      return;
    }
    final result = await net.service.signIn(email, _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _reauthed = result.ok;
      _error = result.ok ? null : (result.reason ?? 'Sign in again to confirm.');
    });
  }

  Future<void> _delete() async {
    if (_busy || !_reauthed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final reason = await net.requestAccountDeletion(_name.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = reason;
    });
    if (reason == null && mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          deleteAccountTitle,
          style: TextStyle(fontSize: GameFont.xl, fontWeight: FontWeight.w400),
        ),
        const SizedBox(height: 8),
        const MutedText(deleteAccountBody),
        const SizedBox(height: 16),
        if (!_reauthed) ...[
          TextField(
            key: const Key('delete-reauth-password'),
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          GameButton(label: 'Sign in again', onPressed: _busy ? null : _reauth, waiting: _busy),
        ] else ...[
          TextField(
            key: const Key('delete-character-name'),
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Type your character name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          GameButton(
            key: const Key('delete-account-confirm'),
            label: 'Delete account',
            onPressed: _busy ? null : _delete,
            waiting: _busy,
          ),
        ],
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(error, style: const TextStyle(color: Palette.danger)),
          ),
      ],
    );

    if (widget.embedded) return body;
    return DecoratedBox(
      decoration: chromeBoardFill(context),
      child: SafeArea(
        child: Padding(padding: const EdgeInsets.all(16), child: body),
      ),
    );
  }
}
