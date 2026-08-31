import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/xp.dart';
import '../inventory/add_items.dart';
import '../inventory/capacity.dart';
import '../js_compat.dart';
import '../save/generated/save_models.dart';
import '../spells/spells.dart';
import '../tags.dart';
import '../world/blessing.dart';

const String foodSlotId = 'SLOT-0011';
const String potionSlotId = 'SLOT-0012';
const String offhandSlotId = 'SLOT-0002';

bool isDaggerItem(GameDatabase db, String itemId) {
  final item = db.items.firstWhereOrNull((row) => row.raw['Item ID'] == itemId);
  if (item == null) return false;
  if (lowerOrEmpty(item.raw['Subtype']) == 'dagger') return true;
  final key = lowerOrEmpty(item.raw['Internal Key']);
  final name = lowerOrEmpty(item.raw['Display Name']);
  return key.contains('dagger') || RegExp(r'\bdagger\b').hasMatch(name);
}

bool itemHasCapability(GameDatabase db, String itemId, String tag) {
  final equipment = db.equipment.firstWhereOrNull((row) => row.raw['Item ID'] == itemId);
  return capabilityTags(equipment?.raw['Capabilities / Effects']).contains(tag.toLowerCase());
}

bool isTwoHandedItem(GameDatabase db, String itemId) => itemHasCapability(db, itemId, 'two_handed');

/// Either the updated save or the reason the change was refused.
class EquipResult {
  const EquipResult.ok(this.save, {this.warning}) : reason = null;

  const EquipResult.failed(this.reason) : save = null, warning = null;

  final PlayerSave? save;
  final String? reason;
  final String? warning;

  bool get ok => reason == null;
}

EquippedStack? slotStack(PlayerSave save, String slotId) => save.equipment.slots[slotId];

String? slotItemId(PlayerSave save, String slotId) => slotStack(save, slotId)?.itemId;

bool isFoodSlot(String slotId) => slotId == foodSlotId;

bool isPotionSlot(String slotId) => slotId == potionSlotId;

/// Food and potion slots hold full stacks (any quantity).
bool isStackableConsumableSlot(String slotId) => isFoodSlot(slotId) || isPotionSlot(slotId);

PlayerSave _removeItemQuantity(
  PlayerSave save,
  String itemId,
  num quantity, [
  String? enchantmentId,
]) {
  if (quantity <= 0) return save;
  var remaining = quantity;
  final inventory = <InventoryStack>[];
  for (final stack in save.inventory) {
    if (stack.itemId != itemId || remaining <= 0 || stack.enchantmentId != enchantmentId) {
      inventory.add(stack);
      continue;
    }
    final take = math.min(stack.quantity, remaining);
    remaining -= take;
    inventory.add(stack.copyWith(quantity: stack.quantity - take));
  }
  return save.copyWith(inventory: inventory.where((stack) => stack.quantity > 0).toList());
}

/// The stack at [index], or null where JavaScript would read `undefined`.
///
/// A fractional or out-of-range index is a miss rather than an error, matching
/// an array lookup on a key that does not exist.
InventoryStack? _stackAt(List<InventoryStack> inventory, num index) {
  if (!jsIsInteger(index) || index < 0 || index >= inventory.length) return null;
  return inventory[index.toInt()];
}

PlayerSave _removeInventoryAtIndex(PlayerSave save, num index, num quantity) {
  if (quantity <= 0) return save;
  final stack = _stackAt(save.inventory, index);
  if (stack == null || stack.quantity < quantity) return save;
  final inventory = [...save.inventory];
  inventory[index.toInt()] = stack.copyWith(quantity: stack.quantity - quantity);
  return save.copyWith(inventory: inventory.where((entry) => entry.quantity > 0).toList());
}

PlayerSave _setSlot(PlayerSave save, String slotId, EquippedStack? stack) {
  return save.copyWith(
    equipment: EquipmentLoadout(slots: {...save.equipment.slots, slotId: stack}),
  );
}

String? _skillRequirementFailure(
  GameDatabase db,
  PlayerSave save,
  String? skillId,
  num? requiredLevel,
) {
  if (isBlank(skillId) || requiredLevel == null) return null;
  final progress = getSkillProgress(save, skillId!);
  if (progress.level >= requiredLevel) return null;
  final displayName = db.skills
      .firstWhereOrNull((skill) => skill.raw['Skill ID'] == skillId)
      ?.raw['Display Name'];
  final skillName = displayName is String ? displayName : skillId;
  return 'Requires $skillName level ${jsNumberToString(requiredLevel)}';
}

String? equipmentRequirementFailure(GameDatabase db, PlayerSave save, EquipmentRow equipment) {
  return _skillRequirementFailure(
        db,
        save,
        equipment.raw['Required Skill ID'] as String?,
        equipment.raw['Required Level'] as num?,
      ) ??
      _skillRequirementFailure(
        db,
        save,
        equipment.raw['Secondary Required Skill ID'] as String?,
        equipment.raw['Secondary Required Level'] as num?,
      );
}

/// Why the Temple will not let this slot be filled, or null anywhere else.
///
/// The monks train bare-handed, so nothing goes in either hand while the player
/// stands on their ground. Gear worn on arrival is left alone: only reaching for
/// something new is refused.
String? templeHandsRefusal(PlayerSave save, String slotId) {
  if (save.currentLocationId != templeLocationId) return null;
  if (slotId != weaponToolSlotId && slotId != offhandSlotId) return null;
  return 'The monks keep your hands empty at the Temple.';
}

/// Unequips a slot, returning any equipped stack to inventory.
///
/// Blocked (not performed) when the bag has no room for the returned item, so
/// gear is never silently destroyed.
EquipResult unequipSlot(PlayerSave save, String slotId) {
  final equipped = slotStack(save, slotId);
  if (equipped == null || equipped.quantity <= 0) {
    return EquipResult.ok(_setSlot(save, slotId, null));
  }
  final favorite = equipped.favorite == true;
  if (!canFitItemQuantity(
    save,
    equipped.itemId,
    equipped.quantity,
    equipped.enchantmentId,
    favorite,
  )) {
    return const EquipResult.failed('Not enough inventory space to unequip that item.');
  }
  return EquipResult.ok(
    addItemToInventory(
      _setSlot(save, slotId, null),
      equipped.itemId,
      equipped.quantity,
      equipped.enchantmentId,
      favorite,
    ),
  );
}

/// Equips an inventory item into its equipment slot.
///
/// Food / potion: moves the entire inventory stack into the slot (any quantity).
/// Other gear: moves one item into the slot.
EquipResult equipItemFromInventory(GameDatabase db, PlayerSave save, String itemId) {
  final index = save.inventory.indexWhere(
    (entry) => entry.itemId == itemId && isBlank(entry.enchantmentId),
  );
  final fallback = save.inventory.indexWhere((entry) => entry.itemId == itemId);
  return equipInventoryIndex(db, save, index >= 0 ? index : fallback);
}

/// Equips a specific inventory stack index (preserves enchantments).
EquipResult equipInventoryIndex(GameDatabase db, PlayerSave save, num index) {
  final invStack = _stackAt(save.inventory, index);
  if (invStack == null || invStack.quantity <= 0) {
    return const EquipResult.failed('Item is not in inventory.');
  }
  final itemId = invStack.itemId;
  final equipment = db.equipment.firstWhereOrNull((row) => row.raw['Item ID'] == itemId);
  final equipmentSlotId = equipment?.raw['Slot ID'];
  if (equipment == null || equipmentSlotId is! String || equipmentSlotId.isEmpty) {
    return const EquipResult.failed('That item cannot be equipped.');
  }

  // Ahead of the skill requirement: standing at the Temple is the reason that
  // matters, and it applies to gear the player is otherwise qualified for.
  // A dagger rerouted to the off-hand is covered too, since both hands are shut.
  final templeRefusal = templeHandsRefusal(save, equipmentSlotId);
  if (templeRefusal != null) {
    return EquipResult.failed(templeRefusal);
  }

  final requirementFailure = equipmentRequirementFailure(db, save, equipment);
  if (requirementFailure != null) {
    return EquipResult.failed(requirementFailure);
  }

  // Spells may fill any empty spell slot; duplicates are allowed across slots.
  var slotId = equipmentSlotId;
  if (isSpellEquipment(equipment) || isSpellSlotId(slotId)) {
    final empty = firstEmptySpellSlot(save);
    if (empty == null) {
      return const EquipResult.failed('All spell slots are full.');
    }
    slotId = empty;
  } else if (isDaggerItem(db, itemId)) {
    // Daggers equip to the off-hand only (replacing a shield). Dual-wielding two
    // daggers is not supported yet.
    slotId = offhandSlotId;
    final mainhandId = slotItemId(save, weaponToolSlotId);
    if (isNotBlank(mainhandId) && isDaggerItem(db, mainhandId!)) {
      return const EquipResult.failed(
        'Unequip your main-hand dagger before equipping an off-hand dagger.',
      );
    }
  }

  var next = save;
  final current = slotStack(next, slotId);
  final enchantmentId = invStack.enchantmentId;
  final favorite = invStack.favorite == true;

  if (isStackableConsumableSlot(slotId)) {
    if (isNotBlank(enchantmentId)) {
      return EquipResult.failed(
        isPotionSlot(slotId)
            ? 'Enchanted items cannot fill the potion slot.'
            : 'Enchanted items cannot fill the food slot.',
      );
    }
    final moveQty = invStack.quantity;
    final swappingItem =
        current != null && (current.itemId != itemId || isNotBlank(current.enchantmentId));
    if (swappingItem) {
      // Remove the incoming stack first so unequipping the outgoing one can
      // reuse the slot it frees up, instead of over-conservatively rejecting
      // a same-size swap.
      next = _removeInventoryAtIndex(next, index, moveQty);
      final unequipped = unequipSlot(next, slotId);
      if (!unequipped.ok) return unequipped;
      next = unequipped.save!;
      return EquipResult.ok(
        _setSlot(
          next,
          slotId,
          EquippedStack(itemId: itemId, quantity: moveQty, favorite: favorite ? true : null),
        ),
      );
    }
    final existingQty = current?.itemId == itemId && isBlank(current?.enchantmentId)
        ? current!.quantity
        : 0;
    final keepFavorite = favorite || current?.favorite == true;
    next = _removeInventoryAtIndex(next, index, moveQty);
    return EquipResult.ok(
      _setSlot(
        next,
        slotId,
        EquippedStack(
          itemId: itemId,
          quantity: existingQty + moveQty,
          favorite: keepFavorite ? true : null,
        ),
      ),
    );
  }

  if (current != null) {
    // Remove the incoming item first so unequipping the outgoing one can
    // reuse the slot it frees up, instead of over-conservatively rejecting
    // a same-size swap.
    next = _removeInventoryAtIndex(next, index, 1);
    final unequipped = unequipSlot(next, slotId);
    if (!unequipped.ok) return unequipped;
    next = unequipped.save!;
  } else {
    next = _removeInventoryAtIndex(next, index, 1);
  }

  // Two-handed weapons occupy both hands. Equipping one clears the off-hand;
  // equipping an off-hand item while a two-hander is worn clears the main hand.
  // Either extra unequip can fail if the bag is full, which refuses the whole
  // equip so gear is never destroyed.
  if (isTwoHandedItem(db, itemId) && slotId == weaponToolSlotId) {
    final cleared = unequipSlot(next, offhandSlotId);
    if (!cleared.ok) return cleared;
    next = cleared.save!;
  } else if (slotId == offhandSlotId) {
    final mainhandId = slotItemId(next, weaponToolSlotId);
    if (isNotBlank(mainhandId) && isTwoHandedItem(db, mainhandId!)) {
      final cleared = unequipSlot(next, weaponToolSlotId);
      if (!cleared.ok) return cleared;
      next = cleared.save!;
    }
  }

  return EquipResult.ok(
    _setSlot(
      next,
      slotId,
      EquippedStack(
        itemId: itemId,
        quantity: 1,
        enchantmentId: isNotBlank(enchantmentId) ? enchantmentId : null,
        favorite: favorite ? true : null,
      ),
    ),
  );
}

/// Places a stack directly into a slot (demo aids / migrations), removing
/// matching inventory.
///
/// Unlike the player-facing equip flow, this force-set helper always proceeds
/// (falling back to the pre-unequip save if the bag has no room) since it is
/// only used for test/migration setup, not reachable from normal play.
PlayerSave equipStackToSlot(PlayerSave save, String slotId, String itemId, num quantity) {
  if (quantity <= 0) {
    final result = unequipSlot(save, slotId);
    return result.ok ? result.save! : save;
  }
  final unequipped = unequipSlot(save, slotId);
  var next = unequipped.ok ? unequipped.save! : save;
  next = _removeItemQuantity(next, itemId, quantity);
  return _setSlot(next, slotId, EquippedStack(itemId: itemId, quantity: quantity));
}

bool _isEquipmentSkillId(Object? value) => value is String && value.isNotEmpty && value != 'None';

/// Action-time reduction totals keyed by required and secondary skills.
Map<String, num> equippedActionTimeReductionBySkill(GameDatabase db, PlayerSave save) {
  final totals = <String, num>{};
  for (final stack in save.equipment.slots.values) {
    if (stack == null || isBlank(stack.itemId)) continue;
    final row = db.equipment.firstWhereOrNull((entry) => entry.raw['Item ID'] == stack.itemId);
    final amount = jsNumber(row?.raw['Action Time Reduction %'] ?? 0);
    if (amount <= 0) continue;
    for (final skillId in <Object?>[
      row?.raw['Required Skill ID'],
      row?.raw['Secondary Required Skill ID'],
    ]) {
      if (!_isEquipmentSkillId(skillId)) continue;
      final id = skillId as String;
      totals[id] = (totals[id] ?? 0) + amount;
    }
  }
  return totals;
}

/// Reduction that applies only to actions of this skill.
num equippedActionTimeReductionPercent(GameDatabase db, PlayerSave save, String? skillId) {
  if (isBlank(skillId)) return 0;
  return math.max(0, equippedActionTimeReductionBySkill(db, save)[skillId!] ?? 0);
}
