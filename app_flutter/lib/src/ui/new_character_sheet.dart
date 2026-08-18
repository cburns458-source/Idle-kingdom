import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'appearance_picker.dart';
import 'game_image.dart';

/// Name, race, and a starting look.
///
/// One scrolling sheet rather than the React client's three steps: a phone can
/// show the portrait, the sliders and the races at once, and the look is
/// changeable from the wardrobe anyway. The first name also becomes the
/// account name other players see.
class NewCharacterSheet extends StatefulWidget {
  const NewCharacterSheet({
    super.key,
    required this.controller,
    required this.multiplayer,
    this.onCreated,
  });

  final GameController controller;
  final MultiplayerController multiplayer;

  /// Writes the new character to the account as soon as it exists.
  final VoidCallback? onCreated;

  @override
  State<NewCharacterSheet> createState() => _NewCharacterSheetState();
}

class _NewCharacterSheetState extends State<NewCharacterSheet> {
  final TextEditingController _name = TextEditingController();
  String _raceId = 'RACE-0001';
  String? _error;
  bool _submitting = false;
  late PlayerAppearance _appearance;

  @override
  void initState() {
    super.initState();
    _name.text = widget.controller.save.characterName ?? '';
    _appearance = widget.controller.save.appearance;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final cleaned = normalizeCharacterName(_name.text);
    if (cleaned == null) {
      setState(() => _error = 'Enter a name to continue.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final claimed = await widget.multiplayer.claimAccountUsername(cleaned);
    if (!mounted) return;
    if (claimed != null) {
      setState(() {
        _error = claimed;
        _submitting = false;
      });
      return;
    }
    final failure = widget.controller.createCharacter(cleaned, _raceId, appearance: _appearance);
    setState(() {
      _error = failure;
      _submitting = false;
    });
    if (failure == null) widget.onCreated?.call();
  }

  @override
  Widget build(BuildContext context) {
    final races = widget.controller.db.races
        .where((race) => race.releasePhase == 'Launch')
        .toList();

    return ColoredBox(
      color: Palette.ink,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Name your character',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const MutedText(
                'Choose a name and a people. Other players will know you by this name.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                maxLength: characterNameMaxLength,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Character name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 4),
              Flexible(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final side = constraints.maxWidth < constraints.maxHeight
                              ? constraints.maxWidth
                              : constraints.maxHeight;
                          return Align(
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              width: side,
                              height: side,
                              child: GameImage(
                                playerAssetPath(_appearance),
                                fit: BoxFit.contain,
                                alignment: Alignment.topCenter,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        child: AppearancePicker(
                          db: widget.controller.db,
                          appearance: _appearance,
                          onSelect: (category, optionId) => setState(() {
                            _appearance = withAppearanceOption(_appearance, category, optionId);
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    for (final race in races)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _RaceCard(
                          race: race,
                          selected: race.raceId == _raceId,
                          onTap: () => setState(() {
                            _raceId = race.raceId;
                            _error = null;
                          }),
                        ),
                      ),
                  ],
                ),
              ),
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(error, style: const TextStyle(color: Palette.danger)),
                ),
              FilledButton(onPressed: _submitting ? null : _submit, child: const Text('Begin')),
            ],
          ),
        ),
      ),
    );
  }
}

class _RaceCard extends StatelessWidget {
  const _RaceCard({required this.race, required this.selected, required this.onTap});

  final RaceRow race;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 18,
            color: selected ? Palette.gold : Palette.edge,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(race.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (race.description case final blurb?) MutedText(blurb),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
