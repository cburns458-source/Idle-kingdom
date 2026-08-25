import 'dart:math' as math;

import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../save/generated/save_models.dart';
import 'gold.dart';

/// Bag slot cap; each stack or enchanted item uses one slot.
const int inventorySlotLimit = 180;

/// Max quantity on a single non-enchanted stack, matching `Number.MAX_SAFE_INTEGER`.
const int inventoryStackMax = 9007199254740991;

int inventorySlotCount(PlayerSave save) => save.inventory.length;

int inventorySlotsFree(PlayerSave save) =>
    math.max(0, inventorySlotLimit - inventorySlotCount(save));

/// Index of the unenchanted pile to grow. Hearted stacks win when both exist.
/// Enchanted items never merge. Returns -1 when a new slot is needed.
int mergeableStackIndex(List<InventoryStack> inventory, String itemId, [String? enchantmentId]) {
  if (isNotBlank(enchantmentId)) return -1;
  var unfavorited = -1;
  for (final entry in inventory.indexed) {
    final stack = entry.$2;
    if (stack.itemId != itemId || isNotBlank(stack.enchantmentId)) continue;
    if (stack.favorite == true) return entry.$1;
    if (unfavorited < 0) unfavorited = entry.$1;
  }
  return unfavorited;
}

/// How many of this item can still be added without overflowing slots or the
/// stack maximum.
num maxAddableQuantity(
  PlayerSave save,
  String itemId, [
  String? enchantmentId,
  bool favorite = false,
  GameDatabase? db,
]) {
  if (isGoldCurrencyItem(itemId, db) && isBlank(enchantmentId)) {
    return inventoryStackMax;
  }
  if (isNotBlank(enchantmentId)) {
    return inventorySlotsFree(save);
  }

  final existingIndex = mergeableStackIndex(save.inventory, itemId);
  if (existingIndex >= 0) {
    return math.max(0, inventoryStackMax - save.inventory[existingIndex].quantity);
  }
  return inventorySlotsFree(save) > 0 ? inventoryStackMax : 0;
}

bool canFitItemQuantity(
  PlayerSave save,
  String itemId,
  num quantity, [
  String? enchantmentId,
  bool favorite = false,
  GameDatabase? db,
]) {
  final want = quantity.floor();
  if (want <= 0) return true;
  return maxAddableQuantity(save, itemId, enchantmentId, favorite, db) >= want;
}
