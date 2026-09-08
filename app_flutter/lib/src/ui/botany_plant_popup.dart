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
/// Grow time is shown only after a selection, as a confirm hint — not on every
/// cell.
Future<PlantableBotanyOption?> showBotanyPlantGridPopup({
  required BuildContext context,
  required GameController controller,
  required List<PlantableBotanyOption> options,
  Rect? origin,
}) {
  return showGamePopup<PlantableBotanyOption>(
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
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final chrome = UiChrome.of(context);
    final selected = _selected == null ? null : widget.options[_selected!];
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
                    for (var i = 0; i < widget.options.length; i++)
                      _PlantTile(
                        option: widget.options[i],
                        item: widget.controller.indexes.itemsById[widget.options[i].itemId],
                        selected: _selected == i,
                        onTap: widget.options[i].canPlant
                            ? () => setState(() => _selected = i)
                            : null,
                      ),
                  ],
                ),
              ),
              if (selected != null) ...[
                const SizedBox(height: 10),
                Text(selected.displayName, style: TextStyle(fontSize: 14, color: chrome.panelInk)),
                Text(
                  'Grows in ${formatDurationSeconds(selected.spec.growSeconds)} · '
                  'plant ${selected.plantQuantity.round()}',
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
                      label: 'Plant',
                      onPressed: selected == null || !selected.canPlant
                          ? null
                          : () => Navigator.of(context).pop(selected),
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
    required this.onTap,
  });

  final PlantableBotanyOption option;
  final ItemRow? item;
  final bool selected;
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
          material: PixelPlateMaterial.none,
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
            ],
          ),
        ),
      ),
    );
  }
}
