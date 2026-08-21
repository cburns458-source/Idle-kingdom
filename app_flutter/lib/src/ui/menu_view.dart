import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../session/pick_local_png.dart';
import '../theme.dart';
import 'account_panel.dart';
import 'catalog_popup.dart';
import 'page_header.dart';
import 'player_sprite.dart';

const String _playerArtHeading = 'Player sprite';
const String _playerArtBlurb =
    'Use a PNG on this device only. Other players still see the default adventurer. '
    'Full-body sprites crop to the head in the HUD window.';
const String _playerArtApplied = 'Using your PNG on this device.';
const String _playerArtReset = 'Back to the default adventurer.';

/// Character identity, a local sprite override, and the save tools.
class MenuView extends StatefulWidget {
  const MenuView({super.key, required this.controller, required this.multiplayer, this.onClose});

  final GameController controller;
  final MultiplayerController multiplayer;
  final VoidCallback? onClose;

  @override
  State<MenuView> createState() => _MenuViewState();
}

enum _SettingsTab { general, account }

class _MenuViewState extends State<MenuView> {
  String? _artNotice;
  bool _artError = false;
  bool _picking = false;
  String? _toolNotice;
  late String _raceId;
  late String _skillId;
  String _itemId = 'ITEM-0025';
  _SettingsTab _tab = _SettingsTab.general;

  GameController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _raceId = controller.save.raceId ?? races(controller.db).first.raceId;
    _skillId = controller.db.skills.first.skillId;
  }

  void _runTool(String? Function() action) {
    setState(() => _toolNotice = action());
  }

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
    final hasOverride = controller.localArt.hasOverride;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.onClose != null)
            PageHeader(title: 'Settings', onClose: widget.onClose!)
          else
            const Text('Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w400)),
          if (widget.onClose == null) const SizedBox(height: 4),
          const MutedText('Settings and save tools.'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GameButton(
                  label: 'General',
                  compact: true,
                  selected: _tab == _SettingsTab.general,
                  tone: _tab == _SettingsTab.general
                      ? GameButtonTone.primary
                      : GameButtonTone.secondary,
                  onPressed: () => setState(() => _tab = _SettingsTab.general),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: GameButton(
                  label: 'Account',
                  compact: true,
                  selected: _tab == _SettingsTab.account,
                  tone: _tab == _SettingsTab.account
                      ? GameButtonTone.primary
                      : GameButtonTone.secondary,
                  onPressed: () => setState(() => _tab = _SettingsTab.account),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_tab == _SettingsTab.account)
            AccountPanel(controller: controller, multiplayer: widget.multiplayer, embedded: true)
          else ...[
            GamePanel(
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Map travel animation', style: TextStyle(fontWeight: FontWeight.w400)),
                        MutedText('Walk a small sprite to the destination before arriving.'),
                      ],
                    ),
                  ),
                  GameSwitch(
                    value: controller.mapTravelAnimation,
                    onChanged: controller.setMapTravelAnimation,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: widget.multiplayer,
              builder: (context, _) {
                return Column(
                  children: [
                    GamePanel(
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Filter chat', style: TextStyle(fontWeight: FontWeight.w400)),
                                MutedText(
                                  'Hide profanity in chat. Messages are still stored as typed.',
                                ),
                              ],
                            ),
                          ),
                          GameSwitch(
                            value: widget.multiplayer.filterChatProfanity,
                            onChanged: widget.multiplayer.setFilterChatProfanity,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    GamePanel(
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Guild tag on HUD',
                                  style: TextStyle(fontWeight: FontWeight.w400),
                                ),
                                MutedText('Show your guild tag, like [DEV], before your name.'),
                              ],
                            ),
                          ),
                          GameSwitch(
                            value: widget.multiplayer.showHudGuildTag,
                            onChanged: widget.multiplayer.setShowHudGuildTag,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    GamePanel(
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Show title on HUD',
                                  style: TextStyle(fontWeight: FontWeight.w400),
                                ),
                                MutedText(
                                  'Show your equipped title, like The Undying, after your name.',
                                ),
                              ],
                            ),
                          ),
                          GameSwitch(
                            value: controller.showTitleOnHud,
                            onChanged: controller.setShowTitleOnHud,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    GamePanel(
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Hide chat bubble',
                                  style: TextStyle(fontWeight: FontWeight.w400),
                                ),
                                MutedText('Hide the chat button in the corner of the game.'),
                              ],
                            ),
                          ),
                          GameSwitch(
                            value: widget.multiplayer.hideChatBubble,
                            onChanged: widget.multiplayer.setHideChatBubble,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: widget.multiplayer,
              builder: (context, _) {
                return Column(
                  children: [
                    _chatPrivacyRow(
                      title: 'Private messages',
                      detail: 'Who may send you a private message.',
                      value: widget.multiplayer.privacyDirectMessages,
                      onChanged: widget.multiplayer.setPrivacyDirectMessages,
                    ),
                    const SizedBox(height: 16),
                    _chatPrivacyRow(
                      title: 'Local chat',
                      detail: 'Who may see you in local chat, and whose lines you see.',
                      value: widget.multiplayer.privacyLocalChat,
                      onChanged: widget.multiplayer.setPrivacyLocalChat,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            _buildTestingTools(),
            const SizedBox(height: 16),
            _buildPlayerSprite(save, hasOverride),
          ],
        ],
      ),
    );
  }

  Widget _chatPrivacyRow({
    required String title,
    required String detail,
    required String value,
    required Future<void> Function(String value) onChanged,
  }) {
    return GamePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w400)),
          MutedText(detail),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final option in chatPrivacyValues)
                GameButton(
                  label: chatPrivacyLabel(option),
                  compact: true,
                  selected: value == option,
                  tone: value == option ? GameButtonTone.primary : GameButtonTone.secondary,
                  onPressed: widget.multiplayer.busy || !widget.multiplayer.isSignedIn
                      ? null
                      : () => onChanged(option),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerSprite(PlayerSave save, bool hasOverride) {
    return GamePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            _playerArtHeading,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
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
    );
  }

  Widget _buildTestingTools() {
    final raceRows = races(controller.db);
    final skillRows = [...controller.db.skills]
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final itemRows = [...controller.db.items]
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final selectedSkill = getSkillProgress(controller.save, _skillId);
    return GamePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Testing tools', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400)),
          const MutedText('Local debug grants. They are not a live economy.'),
          const SizedBox(height: 10),
          GameButton(
            label: 'Spawn critter',
            onPressed: () => _runTool(controller.debugSpawnCritter),
          ),
          const SizedBox(height: 12),
          GameSelectField(
            label: 'Race',
            value:
                raceRows
                    .where((row) => row.raceId == _raceId)
                    .map((row) => row.displayName)
                    .firstOrNull ??
                'Choose',
            onPressed: () async {
              final chosen = await showGameCatalogPopup(
                context: context,
                eyebrow: 'Race',
                title: 'Change race',
                selectable: true,
                entries: [
                  for (final row in raceRows)
                    CatalogPopupEntry(title: row.displayName, emphasized: row.raceId == _raceId),
                ],
              );
              if (chosen == null || !mounted) return;
              setState(() => _raceId = raceRows[chosen].raceId);
            },
          ),
          const SizedBox(height: 8),
          GameButton(
            label: 'Change race',
            onPressed: () => _runTool(() => controller.debugChangeRace(_raceId)),
          ),
          const SizedBox(height: 12),
          Autocomplete<ItemRow>(
            displayStringForOption: (item) => item.displayName,
            optionsBuilder: (text) {
              final query = text.text.trim().toLowerCase();
              if (query.isEmpty) return itemRows.take(40);
              return itemRows.where((item) => item.displayName.toLowerCase().contains(query));
            },
            onSelected: (item) => setState(() => _itemId = item.itemId),
            fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
              return TextField(
                controller: textController,
                focusNode: focusNode,
                decoration: const InputDecoration(labelText: 'Item', hintText: 'Search…'),
                onSubmitted: (_) => onFieldSubmitted(),
              );
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final qty in const [1, 10, 100])
                GameButton(
                  label: 'Add $qty',
                  onPressed: () => _runTool(() => controller.debugGrantItem(_itemId, qty)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          GameSelectField(
            label: 'Skill · Lv ${selectedSkill.level}',
            value:
                skillRows
                    .where((row) => row.skillId == _skillId)
                    .map((row) => row.displayName)
                    .firstOrNull ??
                'Choose',
            onPressed: () async {
              final chosen = await showGameCatalogPopup(
                context: context,
                eyebrow: 'Skill',
                title: 'Testing tools',
                selectable: true,
                entries: [
                  for (final row in skillRows)
                    CatalogPopupEntry(title: row.displayName, emphasized: row.skillId == _skillId),
                ],
              );
              if (chosen == null || !mounted) return;
              setState(() => _skillId = skillRows[chosen].skillId);
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              GameButton(
                label: 'Add 1 level',
                onPressed: () => _runTool(() => controller.debugAddSkillLevels(_skillId, 1)),
              ),
              GameButton(
                label: 'Add 10 levels',
                onPressed: () => _runTool(() => controller.debugAddSkillLevels(_skillId, 10)),
              ),
              GameButton(
                label: 'Remove 1 level',
                tone: GameButtonTone.secondary,
                onPressed: () => _runTool(() => controller.debugRemoveSkillLevels(_skillId, 1)),
              ),
              GameButton(
                label: 'Reset all skills',
                tone: GameButtonTone.secondary,
                onPressed: () => _runTool(controller.debugResetAllSkills),
              ),
            ],
          ),
          if (_toolNotice case final notice?) ...[
            const SizedBox(height: 8),
            Text(notice, style: const TextStyle(color: Palette.gold, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
