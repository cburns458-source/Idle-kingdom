import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'game_popup.dart';
import 'item_icon.dart';

/// Pick three bait fish for a pot, or place it empty for a random haul.
Future<List<String>?> showPotBaitGridPopup({
  required BuildContext context,
  required GameController controller,
  required List<PotBaitOption> options,
  Rect? origin,
}) {
  return showGamePopup<List<String>>(
    context: context,
    origin: origin ?? popupOrigin(context),
    builder: (context) => _PotBaitGridPopup(controller: controller, options: options),
  );
}

class _PotBaitGridPopup extends StatefulWidget {
  const _PotBaitGridPopup({required this.controller, required this.options});

  final GameController controller;
  final List<PotBaitOption> options;

  @override
  State<_PotBaitGridPopup> createState() => _PotBaitGridPopupState();
}

class _PotBaitGridPopupState extends State<_PotBaitGridPopup> {
  final List<String> _picked = <String>[];

  int _pickedOf(String itemId) => _picked.where((id) => id == itemId).length;

  void _tap(PotBaitOption option) {
    if (option.owned <= 0) return;
    setState(() {
      if (_picked.length >= potBaitCount) return;
      if (_pickedOf(option.itemId) >= option.owned.round()) return;
      _picked.add(option.itemId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final chrome = UiChrome.of(context);
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
              const MutedText('Fishing pot'),
              Text(
                'Add three bait fish, or place it empty',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400, color: chrome.panelInk),
              ),
              const SizedBox(height: 10),
              if (widget.options.isEmpty)
                const MutedText('No matching bait for the catches here.')
              else
                Flexible(
                  child: GridView.extent(
                    maxCrossAxisExtent: 78,
                    mainAxisSpacing: 5,
                    crossAxisSpacing: 5,
                    childAspectRatio: 1,
                    shrinkWrap: true,
                    children: [
                      for (final option in widget.options)
                        _BaitTile(
                          option: option,
                          item: widget.controller.indexes.itemsById[option.itemId],
                          selectedCount: _pickedOf(option.itemId),
                          onTap: option.owned > 0 ? () => _tap(option) : null,
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                _picked.isEmpty
                    ? 'No bait · random unlocked catch'
                    : '${_picked.length} / $potBaitCount bait selected',
                style: TextStyle(fontSize: 14, color: chrome.panelInk),
              ),
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
                      label: _picked.isEmpty ? 'No bait' : 'Place pot',
                      onPressed: _picked.isEmpty || _picked.length == potBaitCount
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

class _BaitTile extends StatelessWidget {
  const _BaitTile({
    required this.option,
    required this.item,
    required this.selectedCount,
    required this.onTap,
  });

  final PotBaitOption option;
  final ItemRow? item;
  final int selectedCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final slot = UiChrome.of(context).slot;
    final enabled = onTap != null;
    final selected = selectedCount > 0;
    final fill = selected
        ? Color.lerp(slot, Palette.gold, 0.18)!
        : enabled
        ? slot
        : Color.lerp(slot, const Color(0xFF000000), 0.25)!;
    return Tooltip(
      message: '${option.displayName} · ${option.owned.round()} owned',
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: PixelInkPlate(
          onTap: onTap,
          step: PixelChrome.stepTight,
          fillColor: fill,
          material: PixelPlateMaterial.none,
          selected: selected,
          shadow: false,
          padding: const EdgeInsets.all(2),
          child: Stack(
            children: [
              Center(child: ItemIcon(item: item, size: 28)),
              if (selectedCount > 0)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Text(
                    '$selectedCount',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w400),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
