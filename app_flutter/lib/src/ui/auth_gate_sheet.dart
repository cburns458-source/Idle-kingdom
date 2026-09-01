import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'account_auth_form.dart';

/// Blocks the game until the player signs in with email.
///
/// During the closed test, a shared passkey is asked first. Character creation
/// comes after this sheet, once [MultiplayerController.isSignedIn] is true.
class AuthGateSheet extends StatelessWidget {
  const AuthGateSheet({super.key, required this.controller, required this.multiplayer});

  final GameController controller;
  final MultiplayerController multiplayer;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: woodBoardFill(),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListenableBuilder(
            listenable: multiplayer,
            builder: (context, _) {
              return ListView(
                children: [
                  if (!multiplayer.hasTesterAccess)
                    _TesterPasskeyForm(multiplayer: multiplayer)
                  else ...[
                    GamePanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Sign in to play',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w400),
                          ),
                          const SizedBox(height: 4),
                          MutedText(authGateIntro(multiplayer.mode)),
                          const SizedBox(height: 16),
                          AccountAuthForm(controller: controller, multiplayer: multiplayer),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TesterPasskeyForm extends StatefulWidget {
  const _TesterPasskeyForm({required this.multiplayer});

  final MultiplayerController multiplayer;

  @override
  State<_TesterPasskeyForm> createState() => _TesterPasskeyFormState();
}

class _TesterPasskeyFormState extends State<_TesterPasskeyForm> {
  final TextEditingController _passkey = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _passkey.dispose();
    super.dispose();
  }

  void _submit() {
    final ok = widget.multiplayer.unlockTesterAccess(_passkey.text);
    if (ok) return;
    setState(() => _error = 'That passkey is not right.');
  }

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Test launch', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w400)),
          const SizedBox(height: 4),
          const MutedText('Enter the tester passkey to create an account or sign in.'),
          const SizedBox(height: 16),
          TextField(
            key: const Key('tester-passkey'),
            controller: _passkey,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(labelText: 'Passkey'),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 8),
            Text(error, style: const TextStyle(color: Palette.danger)),
          ],
          const SizedBox(height: 12),
          GameButton(label: 'Continue', onPressed: _submit),
        ],
      ),
    );
  }
}
