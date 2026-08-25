import 'dart:math' as math;

import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../save/generated/save_models.dart';
import 'capacity.dart';
import 'favorites.dart';
import 'gold.dart';

/// Result of a partial add: how many actually fit.
class AddItemsResult {
  const AddItemsResult({required this.save, required this.added});

  final PlayerSave save;
  final num added;
}

/// Result of an all-or-nothing add.
class AddItemsExactResult {
  const AddItemsExactResult.ok(this.save) : reason = null;

  const AddItemsExactResult.failed(this.reason) : save = null;

  final PlayerSave? save;
  final String? reason;

  bool get ok => reason == null;
}

/// Adds as many as fit without exceeding the bag slot limit or stack maximum.
///
/// Gold currency items become `save.gold` instead of taking a bag slot. Ported
/// from `addItemsToInventory` in `src/game/activity/rewards.ts`.
AddItemsResult addItemsToInventory(
  PlayerSave save,
  String itemId,
  num quantity, [
  String? enchantmentId,
  bool favorite = false,
  GameDatabase? db,
]) {
  final want = quantity.floor();
  if (want <= 0) return AddItemsResult(save: save, added: 0);

  if (isGoldCurrencyItem(itemId, db) && isBlank(enchantmentId)) {
    return AddItemsResult(
      save: save.copyWith(gold: save.gold + want),
      added: want,
    );
  }

  final addable = maxAddableQuantity(save, itemId, enchantmentId, favorite, db);
  final added = math.min(want, addable);
  if (added <= 0) return AddItemsResult(save: save, added: 0);

  final inventory = [...save.inventory];

  if (isNotBlank(enchantmentId)) {
    for (var i = 0; i < added; i += 1) {
      inventory.add(
        InventoryStack(
          itemId: itemId,
          quantity: 1,
          enchantmentId: enchantmentId,
          favorite: favorite ? true : null,
        ),
      );
    }
    return AddItemsResult(
      save: sortInventoryFavoritesFirst(save.copyWith(inventory: inventory)),
      added: added,
    );
  }

  final existingIndex = mergeableStackIndex(inventory, itemId);
  if (existingIndex >= 0) {
    final existing = inventory[existingIndex];
    inventory[existingIndex] = existing.copyWith(
      quantity: math.min(inventoryStackMax, existing.quantity + added),
    );
  } else {
    inventory.add(
      InventoryStack(itemId: itemId, quantity: added, favorite: favorite ? true : null),
    );
  }
  return AddItemsResult(
    save: sortInventoryFavoritesFirst(save.copyWith(inventory: inventory)),
    added: added,
  );
}

/// Adds only what fits, never overflowing slots or stacks.
PlayerSave addItemToInventory(
  PlayerSave save,
  String itemId,
  num quantity, [
  String? enchantmentId,
  bool favorite = false,
  GameDatabase? db,
]) {
  return addItemsToInventory(save, itemId, quantity, enchantmentId, favorite, db).save;
}

/// Adds the full quantity or leaves the save untouched.
AddItemsExactResult addItemToInventoryExact(
  PlayerSave save,
  String itemId,
  num quantity, [
  String? enchantmentId,
  bool favorite = false,
  GameDatabase? db,
]) {
  final want = quantity.floor();
  if (want <= 0) return AddItemsExactResult.ok(save);
  if (isGoldCurrencyItem(itemId, db) && isBlank(enchantmentId)) {
    return AddItemsExactResult.ok(addItemsToInventory(save, itemId, want, null, false, db).save);
  }
  if (!canFitItemQuantity(save, itemId, want, enchantmentId, favorite, db)) {
    if (save.inventory.length >= inventorySlotLimit) {
      return const AddItemsExactResult.failed('Inventory is full (180 slots).');
    }
    return const AddItemsExactResult.failed('That stack cannot hold more of this item.');
  }
  final result = addItemsToInventory(save, itemId, want, enchantmentId, favorite, db);
  if (result.added < want) {
    return const AddItemsExactResult.failed('Inventory is full (180 slots).');
  }
  return AddItemsExactResult.ok(result.save);
}
