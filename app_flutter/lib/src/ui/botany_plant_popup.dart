import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'game_popup.dart';
import 'item_icon.dart';

/// Shop/inventory-style grid for planting seeds and saplings.
///
/// Taps add one seed (up to three, mixed types allowed). A sapling takes the
/// whole patch. Grow time is the longest selected seed.
Future<List<String>?> showBotanyPlantGridPopup({
  required BuildContext context,
  required GameController controller,
  required List<PlantableBotanyOption> options,
  Rect? origin,
}) {
  return showGamePopup<List<String>>(
    context: context,
    origin: origin ?? popupOrigin(context),
    builder: (context) => _BotanyPlantGridPopup(controller: controller, options: options),
  );
}

class _BotanyPlantGridPopup extends StatefulWidget {
  const _BotanyPlantGridPopup({required this.controller, required this.options});

  final GameController controller;
  final List<PlantableBotanyOption> options;

  @override
  State<_BotanyPlantGridPopup> createState() => _BotanyPlantGridPopupState();
}

class _BotanyPlantGridPopupState extends State<_BotanyPlantGridPopup> {
  final List<String> _picked = <String>[];

  int _pickedOf(String itemId) => _picked.where((id) => id == itemId).length;

  PlantableBotanyOption? _optionFor(String itemId) {
    for (final option in widget.options) {
      if (option.itemId == itemId) return option;
    }
    return null;
  }

  bool get _hasSapling => _picked.any((itemId) => _optionFor(itemId)?.spec.isSapling == true);

  void _tap(PlantableBotanyOption option) {
    if (!option.canPlant) return;
    setState(() {
      if (option.spec.isSapling) {
        _picked
          ..clear()
          ..add(option.itemId);
        return;
      }
      if (_hasSapling) _picked.clear();
      if (_picked.length >= 3) return;
      if (_pickedOf(option.itemId) >= option.owned.round()) return;
      _picked.add(option.itemId);
    });
  }

  num get _growSeconds {
    num grow = 0;
    for (final itemId in _picked) {
      final seconds = _optionFor(itemId)?.spec.growSeconds ?? 0;
      if (seconds > grow) grow = seconds;
    }
    return grow;
  }

  @override
  Widget build(BuildContext context) {
    final chrome = UiChrome.of(context);
    final canPlant = _picked.isNotEmpty;
    return GamePopupCard(
      child: GamePanel(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
            maxWidth: 420,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const MutedText('Botany'),
              Text(
                'Plant a seed or sapling',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400, color: chrome.panelInk),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: GridView.extent(
                  maxCrossAxisExtent: 78,
                  mainAxisSpacing: 5,
                  crossAxisSpacing: 5,
                  childAspectRatio: 1,
                  shrinkWrap: true,
                  children: [
                    for (final option in widget.options)
                      _PlantTile(
                        option: option,
                        item: widget.controller.indexes.itemsById[option.itemId],
                        selected: _pickedOf(option.itemId) > 0,
                        selectedCount: _pickedOf(option.itemId),
                        onTap: option.canPlant ? () => _tap(option) : null,
                      ),
                  ],
                ),
              ),
              if (canPlant) ...[
                const SizedBox(height: 10),
                Text(
                  _picked.length == 1
                      ? (_optionFor(_picked.first)?.displayName ?? 'Seed')
                      : '${_picked.length} seeds selected',
                  style: TextStyle(fontSize: 14, color: chrome.panelInk),
                ),
                Text(
                  'Grows in ${formatDurationSeconds(_growSeconds)} · plant ${_picked.length}',
                  style: TextStyle(color: chrome.embossFace, fontSize: 12.5),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: GameButton(label: 'Close', onPressed: () => Navigator.of(context).pop()),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GameButton(
                      label: 'Clear',
                      onPressed: _picked.isEmpty ? null : () => setState(_picked.clear),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GameButton(
                      label: 'Plant',
                      onPressed: canPlant
                          ? () => Navigator.of(context).pop(List<String>.from(_picked))
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlantTile extends StatelessWidget {
  const _PlantTile({
    required this.option,
    required this.item,
    required this.selected,
    required this.selectedCount,
    required this.onTap,
  });

  final PlantableBotanyOption option;
  final ItemRow? item;
  final bool selected;
  final int selectedCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final slot = UiChrome.of(context).slot;
    final enabled = onTap != null;
    final fill = selected
        ? Color.lerp(slot, Palette.gold, 0.18)!
        : enabled
        ? slot
        : Color.lerp(slot, const Color(0xFF000000), 0.25)!;
    return Tooltip(
      message: enabled ? option.displayName : option.reason,
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: PixelInkPlate(
          onTap: onTap,
          step: PixelChrome.stepTight,
          fillColor: fill,
          material: PixelPlateMaterial.grain,
          strokeWidth: selected ? 2.5 : 2,
          selected: selected,
          shadow: false,
          padding: const EdgeInsets.all(4),
          child: Stack(
            children: [
              Center(child: ItemIcon(item: item, size: 36)),
              if (option.owned > 1)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Text(
                    '${option.owned.round()}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: Palette.parchmentText,
                    ),
                  ),
                ),
              if (selectedCount > 0)
                Positioned(
                  left: 0,
                  top: 0,
                  child: Text(
                    '$selectedCount',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: Palette.gold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
