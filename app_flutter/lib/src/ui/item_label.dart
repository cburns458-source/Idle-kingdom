import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

/// The enchantment's display name, or null for a plain stack.
String? enchantmentName(GameDatabase db, String? enchantmentId) {
  return enchantmentTooltipLines(db, enchantmentId).firstOrNull;
}

/// Tile tooltip: the item name, with the enchantment under it when there is one.
String itemTileTooltip(String name, String? enchantment) {
  return enchantment == null ? name : '$name\n$enchantment';
}

/// `Iron Sword • Thorns`; a plain item keeps its bare name.
String enchantedItemLabel(String name, String? enchantment) {
  return enchantment == null ? name : '$name • $enchantment';
}
