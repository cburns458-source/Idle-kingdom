/// Item taking shared by dialogue hand-ins and legacy quest turn-ins.
///
/// Counts read the bag only, never the bank. Enchanted stacks do not count.
/// Hearted (favourited) stacks count everywhere; taking from one needs the
/// player's confirmation (`confirm_favourites`). Ported from
/// `src/game/inventory/bag.ts`.
library;

import 'dart:math' as math;

import '../js_compat.dart';
import '../save/generated/save_models.dart';

/// Player-facing text for `confirm_favourites`; the UI asks Yes / No with it.
const String confirmFavouritesPrompt = 'Some items are favourited. Do you still want to use them?';

class DialogueItemDelta {
  const DialogueItemDelta({required this.itemId, required this.qty});

  final String itemId;

  /// Positive when granted, negative when taken or handed in.
  final num qty;

  Map<String, Object?> toJson() => <String, Object?>{'itemId': itemId, 'qty': qty};
}

/// Unenchanted bag quantity of [itemId].
num bagCount(PlayerSave save, String itemId) {
  num total = 0;
  for (final stack in save.inventory) {
    if (stack.itemId == itemId && isBlank(stack.enchantmentId)) total += stack.quantity;
  }
  return total;
}

/// Unenchanted bag quantity of [itemId] outside hearted (favourited) stacks.
num unfavouriteCount(PlayerSave save, String itemId) {
  num total = 0;
  for (final stack in save.inventory) {
    if (stack.itemId == itemId && isBlank(stack.enchantmentId) && stack.favorite != true) {
      total += stack.quantity;
    }
  }
  return total;
}

/// How much of taking [quantity] [itemId] from [save] would come out of hearted stacks.
num favouritesNeeded(PlayerSave save, String itemId, num quantity) =>
    math.max(0, quantity - unfavouriteCount(save, itemId));

/// Adds [qty] of [itemId] to [lines] (item ID to quantity, first-seen order).
void addFavouriteLine(Map<String, num> lines, String itemId, num qty) {
  if (qty <= 0) return;
  lines[itemId] = (lines[itemId] ?? 0) + qty;
}

/// Removes [quantity] unenchanted [itemId] from the bag, unhearted stacks first.
/// Returns null when the bag holds fewer.
PlayerSave? takeFromBag(PlayerSave save, String itemId, num quantity) {
  if (quantity <= 0) return save;
  if (bagCount(save, itemId) < quantity) return null;
  final inventory = [...save.inventory];
  var remaining = quantity;
  for (final favoritePass in const <bool>[false, true]) {
    for (var index = 0; index < inventory.length; index++) {
      if (remaining <= 0) break;
      final stack = inventory[index];
      if (stack.itemId != itemId || isNotBlank(stack.enchantmentId)) continue;
      if ((stack.favorite == true) != favoritePass) continue;
      final taken = math.min(stack.quantity, remaining);
      inventory[index] = stack.copyWith(quantity: stack.quantity - taken);
      remaining -= taken;
    }
  }
  return save.copyWith(inventory: inventory.where((stack) => stack.quantity > 0).toList());
}
