import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';

import '../content/asset_paths.dart';
import 'format.dart';

/// An item's art, at whatever size the tile it sits in wants.
///
/// Takes the row rather than the id because the icon is chosen from the item's
/// category and name, and an id alone only resolves the handful of pinned ones.
class ItemIcon extends StatelessWidget {
  const ItemIcon({super.key, required this.item, this.size = 34});

  final ItemRow? item;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      itemIconPath(item),
      width: size,
      height: size,
      filterQuality: FilterQuality.none,
    );
  }
}

/// The outline art for an empty equipment slot.
class SlotGlyph extends StatelessWidget {
  const SlotGlyph({super.key, required this.slotId, this.size = 34});

  final String slotId;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.45,
      child: Image.asset(
        slotIconPath(slotId),
        width: size,
        height: size,
        filterQuality: FilterQuality.none,
      ),
    );
  }
}

/// A gold amount with the coin beside it.
class GoldAmount extends StatelessWidget {
  const GoldAmount({super.key, required this.amount, this.size = 14, this.style});

  final num amount;
  final double size;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(formatThousands(amount), style: style ?? const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(width: 4),
        Image.asset(goldIconPath(), width: size, height: size, filterQuality: FilterQuality.none),
      ],
    );
  }
}
