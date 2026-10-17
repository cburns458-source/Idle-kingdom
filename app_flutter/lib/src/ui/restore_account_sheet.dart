import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';

import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'format.dart';

/// Shown on login while a 14-day deletion grace is still open.
class RestoreAccountSheet extends StatefulWidget {
  const RestoreAccountSheet({super.key, required this.multiplayer});

  final MultiplayerController multiplayer;

  @override
  State<RestoreAccountSheet> createState() => _RestoreAccountSheetState();
}

class _RestoreAccountSheetState extends State<RestoreAccountSheet> {
  String? _error;
  bool _busy = false;

  Future<void> _restore() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final reason = await widget.multiplayer.restoreAccount();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = reason;
    });
  }

  Future<void> _leave() async {
    await widget.multiplayer.leaveCharacterCreation();
  }

  @override
  Widget build(BuildContext context) {
    final until = widget.multiplayer.deletionPurgeAt;
    return DecoratedBox(
      decoration: chromeBoardFill(context),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              restoreAccountTitle,
              style: TextStyle(fontSize: GameFont.xl, fontWeight: FontWeight.w400),
            ),
            if (until != null) ...[const SizedBox(height: 8), Text(formatLocalDay(until))],
            const SizedBox(height: 16),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(error, style: const TextStyle(color: Palette.dangerText)),
              ),
            GameButton(
              key: const Key('restore-account'),
              label: 'Restore account',
              onPressed: _busy ? null : _restore,
              waiting: _busy,
            ),
            const SizedBox(height: 8),
            GameButton(
              label: 'Sign out',
              tone: GameButtonTone.secondary,
              onPressed: _busy ? null : _leave,
            ),
          ],
        ),
      ),
    );
  }
}
