import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'account_auth_form.dart';
import 'social_bits.dart';

/// Blocks the game until the player signs in with email.
///
/// Character creation comes after this sheet, once [MultiplayerController.isSignedIn]
/// is true.
class AuthGateSheet extends StatelessWidget {
  const AuthGateSheet({super.key, required this.controller, required this.multiplayer});

  final GameController controller;
  final MultiplayerController multiplayer;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Palette.ink,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              const Text(
                'Sign in to play',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              MutedText(authGateIntro(multiplayer.mode)),
              const SizedBox(height: 16),
              AccountAuthForm(controller: controller, multiplayer: multiplayer),
              SocialNotice(notice: multiplayer.notice),
            ],
          ),
        ),
      ),
    );
  }
}
