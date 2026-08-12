import 'dart:math' as math;

import 'package:collection/collection.dart';

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

bool _stackMatches(InventoryStack stack, String itemId, String? enchantmentId, bool favorite) {
  return stack.itemId == itemId &&
      stack.enchantmentId == enchantmentId &&
      (stack.favorite == true) == favorite;
}

/// How many of this item can still be added without overflowing slots or the
/// stack maximum.
num maxAddableQuantity(
  PlayerSave save,
  String itemId, [
  String? enchantmentId,
  bool favorite = false,
]) {
  if (isGoldCurrencyItem(itemId) && isBlank(enchantmentId)) {
    return inventoryStackMax;
  }
  if (isNotBlank(enchantmentId)) {
    return inventorySlotsFree(save);
  }

  final existing = save.inventory.firstWhereOrNull(
    (stack) => _stackMatches(stack, itemId, null, favorite),
  );
  if (existing != null) {
    return math.max(0, inventoryStackMax - existing.quantity);
  }
  return inventorySlotsFree(save) > 0 ? inventoryStackMax : 0;
}

bool canFitItemQuantity(
  PlayerSave save,
  String itemId,
  num quantity, [
  String? enchantmentId,
  bool favorite = false,
]) {
  final want = quantity.floor();
  if (want <= 0) return true;
  return maxAddableQuantity(save, itemId, enchantmentId, favorite) >= want;
}
