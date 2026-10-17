import 'package:flutter/material.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'account_auth_form.dart';
import 'delete_account_sheet.dart';

/// Web `/delete-account` page required by Google Play.
class DeleteAccountPage extends StatelessWidget {
  const DeleteAccountPage({super.key, required this.controller, required this.multiplayer});

  final GameController controller;
  final MultiplayerController multiplayer;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: chromeBoardFill(context),
      child: SafeArea(
        child: ListenableBuilder(
          listenable: multiplayer,
          builder: (context, _) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Delete a Restoria account',
                  style: TextStyle(fontSize: GameFont.xl, fontWeight: FontWeight.w400),
                ),
                const SizedBox(height: 16),
                if (!multiplayer.isSignedIn)
                  AccountAuthForm(controller: controller, multiplayer: multiplayer)
                else
                  DeleteAccountSheet(
                    controller: controller,
                    multiplayer: multiplayer,
                    embedded: true,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// True when the Flutter web build was opened at /delete-account.
bool isDeleteAccountPath([Uri? uri]) {
  final path = (uri ?? Uri.base).path;
  return path == '/delete-account' || path.endsWith('/delete-account');
}
