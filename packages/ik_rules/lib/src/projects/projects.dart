import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

/// Enchantment lookup by ID.
///
/// Only the lookups other rules depend on are ported here; the rest of
/// `src/game/projects/projects.ts` arrives with the project engine.
EnchantmentRow? getEnchantment(GameDatabase db, String enchantmentId) {
  return db.enchantments.firstWhereOrNull((row) => row.raw['Enchantment ID'] == enchantmentId);
}

bool isEnchantmentOutput(String outputId) => outputId.startsWith('ENCH-');
