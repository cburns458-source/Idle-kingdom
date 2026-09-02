import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'appearance_picker.dart';
import 'item_icon.dart';
import 'player_sprite.dart';

/// The wardrobe: the character as they look, the sliders that change it, and the
/// cosmetics they own, one tab per slot.
class WardrobeSheet extends StatefulWidget {
  const WardrobeSheet({super.key, required this.controller, required this.onClose});

  final GameController controller;
  final VoidCallback onClose;

  @override
  State<WardrobeSheet> createState() => _WardrobeSheetState();
}

class _WardrobeSheetState extends State<WardrobeSheet> {
  String _slotId = '';
  String? _error;

  GameController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _slotId = wardrobeSlotTabs(controller.db).firstOrNull?.slotId ?? '';
  }

  void _equip(String slotId, String? cosmeticId) {
    final result = equipCosmetic(controller.db, controller.save, slotId, cosmeticId);
    if (!result.ok) {
      setState(() => _error = result.reason);
      return;
    }
    controller.commit(result.save!);
    setState(() => _error = null);
  }

  void _setAppearance(AppearanceCategory category, String optionId) {
    final next = setAppearanceOption(controller.db, controller.save, category, optionId);
    if (next == null) return;
    controller.commit(next);
  }

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    final tabs = wardrobeSlotTabs(controller.db);
    final slot = wardrobeSlotView(controller.db, save, _slotId);

    return ColoredBox(
      color: UiChrome.of(context).board,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Wardrobe',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w400),
                  ),
                ),
                GameButton(
                  label: 'Close',
                  tone: GameButtonTone.secondary,
                  compact: true,
                  tooltip: 'Close',
                  onPressed: widget.onClose,
                ),
              ],
            ),
            Flexible(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final race = raceDisplayName(controller.db, save.raceId);
                        final label = race == null ? 0.0 : 18.0;
                        final side = constraints.maxWidth < constraints.maxHeight - label
                            ? constraints.maxWidth
                            : constraints.maxHeight - label;
                        return Align(
                          alignment: Alignment.topCenter,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: side,
                                height: side,
                                child: PlayerSprite(
                                  appearance: save.appearance,
                                  raceId: save.raceId,
                                  bytes: controller.localPlayerPng,
                                  fit: BoxFit.contain,
                                  alignment: Alignment.topCenter,
                                ),
                              ),
                              if (race != null) MutedText(race),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: AppearancePicker(
                        db: controller.db,
                        appearance: save.appearance,
                        onSelect: _setAppearance,
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
                  if (tabs.length > 1)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final tab in tabs) ...[
                            GameButton(
                              label: tab.label,
                              compact: true,
                              selected: (slot?.slotId ?? _slotId) == tab.slotId,
                              tone: (slot?.slotId ?? _slotId) == tab.slotId
                                  ? GameButtonTone.primary
                                  : GameButtonTone.secondary,
                              onPressed: () => setState(() {
                                _slotId = tab.slotId;
                                _error = null;
                              }),
                            ),
                            const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ),
                  if (slot case final slot?) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _CosmeticTile(
                          label: 'None',
                          selected: slot.equippedCosmeticId == null,
                          onTap: () => _equip(slot.slotId, null),
                        ),
                        for (final tile in slot.tiles)
                          _CosmeticTile(
                            label: tile.name,
                            selected: tile.equipped,
                            item: controller.indexes.itemsById[tile.itemId],
                            onTap: () => _equip(slot.slotId, tile.cosmeticId),
                          ),
                      ],
                    ),
                    if (slot.tiles.isEmpty) ...[
                      const SizedBox(height: 8),
                      MutedText(slot.emptyNote),
                    ],
                  ],
                  if (_error case final error?) ...[
                    const SizedBox(height: 8),
                    Text(error, style: const TextStyle(color: Palette.danger, fontSize: 12)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CosmeticTile extends StatelessWidget {
  const _CosmeticTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.item,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ItemRow? item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.zero /* pixel step 3 */,
      child: Container(
        width: 92,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0x339A7B32) : Palette.slot,
          borderRadius: BorderRadius.zero /* pixel step 3 */,
          border: Border.all(color: selected ? Palette.gold : Palette.edge),
        ),
        child: Column(
          children: [
            if (item != null)
              ItemIcon(item: item, size: 34)
            else
              const SizedBox(height: 34, child: Center(child: Icon(Icons.block, size: 20))),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// Says a cosmetic was unlocked, and where to go and wear it.
class WardrobeUnlockPopup extends StatelessWidget {
  const WardrobeUnlockPopup({
    super.key,
    required this.notice,
    required this.item,
    required this.onClose,
  });

  final CosmeticUnlockNotice notice;
  final ItemRow? item;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xCC120C08),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: GamePanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const MutedText('New Cosmetic'),
                const Text(
                  'You found a Cosmetic!',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w400),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    ItemIcon(item: item, size: 40),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(notice.name, style: const TextStyle(fontWeight: FontWeight.w400)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text('It has been added to your Wardrobe.'),
                if (notice.hint case final hint?) ...[const SizedBox(height: 6), MutedText(hint)],
                const SizedBox(height: 14),
                GameButton(label: 'Nice!', onPressed: onClose),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
