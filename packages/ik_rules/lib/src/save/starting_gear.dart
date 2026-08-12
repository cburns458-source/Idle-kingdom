import '../js_compat.dart';
import 'generated/save_models.dart';
import 'json_save.dart';

bool _hasItem(List<Object?> inventory, SaveJson slots, String itemId) {
  final owned = inventory.any(
    (entry) =>
        entry is SaveJson && entry['itemId'] == itemId && isPositiveQuantity(entry['quantity']),
  );
  if (owned) return true;
  return slots.values.any(
    (stack) =>
        stack is SaveJson && stack['itemId'] == itemId && isPositiveQuantity(stack['quantity']),
  );
}

SaveJson? _firstStack(List<Object?> inventory, String itemId) {
  for (final entry in inventory) {
    if (entry is SaveJson && entry['itemId'] == itemId) return entry;
  }
  return null;
}

SaveJson _withGear(SaveJson save, List<Object?> inventory, SaveJson slots) {
  final next = copySave(save);
  next['inventory'] = inventory;
  next['equipment'] = <String, Object?>{'slots': slots};
  return next;
}

/// Ensure the demo hunting Net is owned and equipped when the tool slot is free.
///
/// Runs as a save migration, so it takes loose JSON: the save being upgraded is
/// only a version 4 save and has no guarantee of matching the current schema.
SaveJson ensureStartingHuntingToolJson(SaveJson save) {
  final slots = objectOrEmpty(objectAt(save, 'equipment') ?? <String, Object?>{}, 'slots');
  final inventory = arrayOrEmpty(save, 'inventory');
  final weapon = slots[weaponToolSlotId];

  if (!_hasItem(inventory, slots, startingHuntingToolId)) {
    if (weapon == null) {
      slots[weaponToolSlotId] = <String, Object?>{'itemId': startingHuntingToolId, 'quantity': 1};
    } else {
      final existing = _firstStack(inventory, startingHuntingToolId);
      if (existing != null) {
        existing['quantity'] = jsNumber(existing['quantity']) + 1;
      } else {
        inventory.add(<String, Object?>{'itemId': startingHuntingToolId, 'quantity': 1});
      }
    }
    return _withGear(save, inventory, slots);
  }

  // Already owned: equip it if the weapon/tool slot is empty.
  if (weapon == null) {
    final stack = _firstStack(inventory, startingHuntingToolId);
    if (stack != null && isPositiveQuantity(stack['quantity'])) {
      for (final entry in inventory) {
        if (entry is SaveJson && entry['itemId'] == startingHuntingToolId) {
          entry['quantity'] = jsNumber(entry['quantity']) - 1;
        }
      }
      inventory.removeWhere(
        (entry) => entry is! SaveJson || !isPositiveQuantity(entry['quantity']),
      );
      slots[weaponToolSlotId] = <String, Object?>{'itemId': startingHuntingToolId, 'quantity': 1};
      return _withGear(save, inventory, slots);
    }
  }

  return save;
}

/// Typed wrapper for callers that already hold a current-schema save.
PlayerSave ensureStartingHuntingTool(PlayerSave save) =>
    PlayerSave.fromJson(ensureStartingHuntingToolJson(save.toJson()));
