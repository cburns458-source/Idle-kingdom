import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'floating_slot.dart';
import 'format.dart';
import 'game_popup.dart';
import 'item_icon.dart';

class BotanyPlantChoice {
  const BotanyPlantChoice({required this.seedItemIds, this.usedCompost = false});

  final List<String> seedItemIds;
  final bool usedCompost;
}

/// Shop/inventory-style grid for planting seeds and saplings.
///
/// Taps add one seed (up to three, mixed types allowed). A sapling takes the
/// whole patch. Grow time is the longest selected seed.
Future<BotanyPlantChoice?> showBotanyPlantGridPopup({
  required BuildContext context,
  required GameController controller,
  required List<PlantableBotanyOption> options,
  Rect? origin,
}) {
  return showGamePopup<BotanyPlantChoice>(
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
  bool _useCompost = false;

  int _pickedOf(String itemId) => _picked.where((id) => id == itemId).length;

  PlantableBotanyOption? _optionFor(String itemId) {
    for (final option in widget.options) {
      if (option.itemId == itemId) return option;
    }
    return null;
  }

  bool get _hasSapling => _picked.any((itemId) => _optionFor(itemId)?.spec.isSapling == true);

  bool get _hasKelp => _picked.any((itemId) => _optionFor(itemId)?.spec.shallowsOnly == true);

  List<BotanySeedSpec> get _pickedSpecs => [
    for (final itemId in _picked)
      if (_optionFor(itemId) case final option?) option.spec,
  ];

  num get _compostCost => compostCostForSpecs(_pickedSpecs);

  num get _compostOwned => inventoryCompostCount(widget.controller.save);

  bool get _compostAllowed => _picked.isNotEmpty && !_hasKelp;

  void _tap(PlantableBotanyOption option) {
    if (!option.canPlant) return;
    setState(() {
      if (option.spec.isSapling) {
        _picked
          ..clear()
          ..add(option.itemId);
      } else {
        if (_hasSapling) _picked.clear();
        if (_picked.length < 3 && _pickedOf(option.itemId) < option.owned.round()) {
          _picked.add(option.itemId);
        }
      }
      if (_hasKelp) _useCompost = false;
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

  void _plant() {
    if (_picked.isEmpty) return;
    if (_useCompost && _hasKelp) {
      widget.controller.report('Compost cannot be used on kelp.');
      return;
    }
    if (_useCompost && _compostOwned < _compostCost) {
      final need = _compostCost.round();
      widget.controller.report(
        need == 1
            ? 'You need 1 compost for this planting.'
            : 'You need $need compost for this planting.',
      );
      return;
    }
    Navigator.of(context)
        .pop(BotanyPlantChoice(seedItemIds: List<String>.from(_picked), usedCompost: _useCompost));
  }

  @override
  Widget build(BuildContext context) {
    final chrome = UiChrome.of(context);
    final canPlant = _picked.isNotEmpty;
    final compostCost = _compostCost.round();
    final compostOwned = _compostOwned.round();
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
                style: TextStyle(
                  fontSize: gamePopupTitleSize,
                  fontWeight: FontWeight.w400,
                  color: chrome.panelInk,
                ),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _hasKelp
                            ? 'Compost cannot be used on kelp.'
                            : 'Use compost ($compostCost) · have $compostOwned',
                        style: TextStyle(fontSize: 13, color: chrome.panelInk),
                      ),
                    ),
                    GameSwitch(
                      value: _useCompost,
                      onChanged: _compostAllowed
                          ? (value) => setState(() => _useCompost = value)
                          : null,
                    ),
                  ],
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
                      onPressed: _picked.isEmpty
                          ? null
                          : () => setState(() {
                              _picked.clear();
                              _useCompost = false;
                            }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GameButton(label: 'Plant', onPressed: canPlant ? _plant : null),
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
    final enabled = onTap != null;
    return FloatingItemSlot(
      tooltip: enabled ? option.displayName : option.reason,
      selected: selected,
      enabled: enabled,
      padding: const EdgeInsets.all(4),
      onTap: onTap,
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
                  color: Palette.panelInk,
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
    );
  }
}
