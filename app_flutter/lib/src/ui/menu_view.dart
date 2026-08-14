import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../session/pick_local_png.dart';
import '../theme.dart';
import 'player_sprite.dart';
import 'save_transfer_section.dart';

const String _playerArtHeading = 'Player sprite';
const String _playerArtBlurb =
    'Use a PNG on this device only. Other players still see the default adventurer. '
    'Full-body sprites crop to the head in the HUD ring.';
const String _playerArtApplied = 'Using your PNG on this device.';
const String _playerArtReset = 'Back to the default adventurer.';

/// Character identity, a local sprite override, and the save tools.
class MenuView extends StatefulWidget {
  const MenuView({super.key, required this.controller, required this.multiplayer});

  final GameController controller;
  final MultiplayerController multiplayer;

  @override
  State<MenuView> createState() => _MenuViewState();
}

class _MenuViewState extends State<MenuView> {
  String? _artNotice;
  bool _artError = false;
  bool _picking = false;

  GameController get controller => widget.controller;

  Future<void> _usePng() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _artNotice = null;
      _artError = false;
    });
    final picked = await pickLocalPng();
    if (!mounted) return;
    setState(() => _picking = false);
    if (picked.error != null) {
      setState(() {
        _artNotice = picked.error;
        _artError = true;
      });
      return;
    }
    final bytes = picked.bytes;
    if (bytes == null) return;
    final error = controller.applyLocalPlayerPng(bytes);
    setState(() {
      _artNotice = error ?? _playerArtApplied;
      _artError = error != null;
    });
  }

  void _reset() {
    controller.resetLocalPlayerPng();
    setState(() {
      _artNotice = _playerArtReset;
      _artError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    final raceName = raceDisplayName(controller.db, save.raceId);
    final hasOverride = controller.localArt.hasOverride;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const MutedText('Settings and save tools.'),
        const SizedBox(height: 16),
        GamePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MutedText('Character'),
              const SizedBox(height: 4),
              Text(
                save.characterName ?? 'Unnamed',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              MutedText('Race: ${raceName ?? 'Unchosen'}'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GamePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                _playerArtHeading,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const MutedText(_playerArtBlurb),
              if (hasOverride) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: PlayerSprite(
                    appearance: save.appearance,
                    bytes: controller.localPlayerPng,
                    width: 72,
                    height: 72,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              GameButton(label: 'Use my PNG', onPressed: _picking ? null : _usePng),
              const SizedBox(height: 8),
              GameButton(
                label: 'Reset to default',
                tone: GameButtonTone.secondary,
                onPressed: hasOverride ? _reset : null,
              ),
              if (_artNotice case final notice?) ...[
                const SizedBox(height: 8),
                Text(
                  notice,
                  style: TextStyle(color: _artError ? Palette.warning : Palette.gold, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        ListenableBuilder(
          listenable: widget.multiplayer,
          builder: (context, _) {
            return GamePanel(
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Filter chat', style: TextStyle(fontWeight: FontWeight.w700)),
                        MutedText('Hide profanity in chat. Messages are still stored as typed.'),
                      ],
                    ),
                  ),
                  Switch(
                    value: widget.multiplayer.filterChatProfanity,
                    onChanged: widget.multiplayer.setFilterChatProfanity,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        SaveTransferSection(controller: controller),
      ],
    );
  }
}
