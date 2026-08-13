import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';

import '../theme.dart';
import 'format.dart';
import 'item_icon.dart';

/// One ingredient, marked short when the bag cannot cover a single craft.
class IngredientChip extends StatelessWidget {
  const IngredientChip({super.key, required this.item, required this.need, required this.owned});

  final ItemRow? item;
  final num need;
  final num owned;

  @override
  Widget build(BuildContext context) {
    final short = owned < need;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: short ? Palette.danger : Palette.edge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ItemIcon(item: item, size: 18),
          const SizedBox(width: 4),
          Text(
            '${formatThousands(owned)}/${formatThousands(need)}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: short ? Palette.danger : Palette.parchmentText,
            ),
          ),
        ],
      ),
    );
  }
}
