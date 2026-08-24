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

String _remapRetiredNetId(Object? itemId) {
  return itemId == retiredFishingNetItemId ? startingHuntingToolId : jsString(itemId);
}

String _stackMergeKey(SaveJson stack) {
  final enchantment = stack['enchantmentId'] is String ? stack['enchantmentId'] as String : '';
  final favorite = stack['favorite'] == true ? '1' : '0';
  return '${stack['itemId']}\u0000$enchantment\u0000$favorite';
}

List<Object?> _mergeRemappedStacks(List<Object?> stacks) {
  final merged = <SaveJson>[];
  final indexByKey = <String, int>{};
  for (final entry in stacks) {
    if (entry is! SaveJson) continue;
    final next = SaveJson.of(entry);
    next['itemId'] = _remapRetiredNetId(next['itemId']);
    final key = _stackMergeKey(next);
    final existingIndex = indexByKey[key];
    if (existingIndex == null) {
      indexByKey[key] = merged.length;
      merged.add(next);
      continue;
    }
    final existing = merged[existingIndex];
    existing['quantity'] = jsNumber(existing['quantity']) + jsNumber(next['quantity']);
  }
  return merged;
}

/// Turns leftover Fishing Nets into the regular hunting Net.
SaveJson replaceFishingNetsWithNetJson(SaveJson save) {
  final next = copySave(save);
  next['inventory'] = _mergeRemappedStacks(arrayOrEmpty(save, 'inventory'));
  next['bank'] = _mergeRemappedStacks(arrayOrEmpty(save, 'bank'));
  final slots = objectOrEmpty(objectAt(save, 'equipment') ?? <String, Object?>{}, 'slots');
  final nextSlots = <String, Object?>{};
  for (final entry in slots.entries) {
    final stack = asObject(entry.value);
    if (stack == null) {
      nextSlots[entry.key] = entry.value;
      continue;
    }
    final remapped = SaveJson.of(stack);
    remapped['itemId'] = _remapRetiredNetId(remapped['itemId']);
    nextSlots[entry.key] = remapped;
  }
  next['equipment'] = <String, Object?>{'slots': nextSlots};
  return next;
}

PlayerSave replaceFishingNetsWithNet(PlayerSave save) =>
    PlayerSave.fromJson(replaceFishingNetsWithNetJson(save.toJson()));
