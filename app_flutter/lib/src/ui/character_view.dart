import 'package:flutter/material.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'inventory_view.dart';
import 'page_header.dart';
import 'skills_view.dart';

enum CharacterTab { inventory, equipment, skills }

/// Skills, the bag, and worn gear behind one chin tab.
class CharacterView extends StatefulWidget {
  const CharacterView({super.key, required this.controller, this.onClose});

  final GameController controller;
  final VoidCallback? onClose;

  @override
  State<CharacterView> createState() => _CharacterViewState();
}

class _CharacterViewState extends State<CharacterView> {
  CharacterTab _tab = CharacterTab.inventory;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.onClose != null)
          PageHeader(title: 'Character', onClose: widget.onClose!)
        else
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Text('Character', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w400)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Row(
            children: [
              for (final tab in CharacterTab.values) ...[
                if (tab != CharacterTab.inventory) const SizedBox(width: 6),
                Expanded(
                  child: GameButton(
                    label: switch (tab) {
                      CharacterTab.skills => 'Skills',
                      CharacterTab.inventory => 'Inventory',
                      CharacterTab.equipment => 'Equipment',
                    },
                    compact: true,
                    selected: _tab == tab,
                    tone: _tab == tab ? GameButtonTone.primary : GameButtonTone.secondary,
                    onPressed: () => setState(() => _tab = tab),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: switch (_tab) {
            CharacterTab.skills => SkillsView(controller: widget.controller, showHeader: false),
            CharacterTab.inventory => InventoryView(
              key: const ValueKey(InventoryPane.items),
              controller: widget.controller,
              pane: InventoryPane.items,
              showHeader: false,
            ),
            CharacterTab.equipment => InventoryView(
              key: const ValueKey(InventoryPane.equipment),
              controller: widget.controller,
              pane: InventoryPane.equipment,
              showHeader: false,
            ),
          },
        ),
      ],
    );
  }
}
