import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../theme.dart';

/// The bag: one tile per stack, with how full it is.
class InventoryView extends StatelessWidget {
  const InventoryView({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    final used = save.inventory.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Inventory',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              MutedText('$used / $inventorySlotLimit slots'),
            ],
          ),
        ),
        Expanded(
          child: used == 0
              ? const Center(child: MutedText('Your bag is empty.'))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 96,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: used,
                  itemBuilder: (context, index) {
                    final stack = save.inventory[index];
                    final item = controller.indexes.itemsById[stack.itemId];
                    return GamePanel(
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(itemIconPath(stack.itemId), width: 34, height: 34),
                          const SizedBox(height: 4),
                          Text(
                            '${stack.quantity}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                          Flexible(
                            child: Text(
                              item?.raw['Display Name'] as String? ?? stack.itemId,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10, color: Color(0xB3F4E7C8)),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
