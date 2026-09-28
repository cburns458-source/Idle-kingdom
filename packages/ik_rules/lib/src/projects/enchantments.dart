import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../inventory/add_items.dart';
import '../js_compat.dart';
import '../save/generated/save_models.dart';
import '../tags.dart';
import 'projects.dart';

/// Where an enchantment is being applied.
sealed class EnchantTarget {
  const EnchantTarget();

  Map<String, Object?> toJson();
}

class EquippedEnchantTarget extends EnchantTarget {
  const EquippedEnchantTarget(this.slotId);

  final String slotId;

  @override
  Map<String, Object?> toJson() => <String, Object?>{'kind': 'equipped', 'slotId': slotId};
}

class InventoryEnchantTarget extends EnchantTarget {
  const InventoryEnchantTarget(this.index);

  final int index;

  @override
  Map<String, Object?> toJson() => <String, Object?>{'kind': 'inventory', 'index': index};
}

class EnchantTargetOption {
  const EnchantTargetOption({
    required this.id,
    required this.label,
    required this.target,
    required this.preferred,
  });

  final String id;
  final String label;
  final EnchantTarget target;
  final bool preferred;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    'target': target.toJson(),
    'preferred': preferred,
  };
}

/// Combat axes (not hatchets/pickaxes) — weapon enchantments only.
bool isAxeItem(ItemRow? item, EquipmentRow equipment) {
  final subtype = lowerOrEmpty(item?.raw['Subtype']);
  final key = lowerOrEmpty(item?.raw['Internal Key']);
  final name = lowerOrEmpty(item?.raw['Display Name']);
  final caps = capabilityTags(equipment.raw['Capabilities / Effects']);

  if (subtype == 'hatchet' || key.contains('hatchet') || name.contains('hatchet')) return false;
  if (subtype == 'pickaxe' || key.contains('pickaxe') || name.contains('pickaxe')) return false;
  if (subtype == 'axe') return true;
  if (caps.contains('combat_weapon') && caps.contains('woodcutting_tool')) return true;
  if (RegExp(r'\baxe\b').hasMatch(name) ||
      RegExp(r'(^|_)axe$').hasMatch(key) ||
      key.contains('_axe')) {
    return true;
  }
  return false;
}

bool _isGatheringToolEquipment(ItemRow? item, EquipmentRow equipment) {
  // Axes are combat-classified for Arcana; hatchets remain gathering tools.
  if (isAxeItem(item, equipment)) return false;

  if (equipment.raw['Action Time Reduction %'] is num) return true;

  final caps = capabilityTags(equipment.raw['Capabilities / Effects']);
  return caps.contains('mining_tool') ||
      caps.contains('woodcutting_tool') ||
      caps.contains('fishing_tool') ||
      caps.contains('hunting_tool') ||
      caps.contains('harvesting_tool');
}

bool _isWeaponEquipment(ItemRow? item, EquipmentRow equipment) {
  final hasDamage = equipment.raw['Min Damage'] is num || equipment.raw['Max Damage'] is num;
  if (!hasDamage) return false;
  // Axes are combat weapons even when they also carry woodcutting_tool.
  if (isAxeItem(item, equipment)) return true;
  final caps = capabilityTags(equipment.raw['Capabilities / Effects']);
  if (caps.contains('combat_weapon')) return true;
  // Gathering tools may list damage for emergency combat but are not weapon-enchant targets.
  if (_isGatheringToolEquipment(item, equipment)) return false;
  return hasDamage;
}

bool _isArmorEquipment(EquipmentRow equipment) {
  final caps = capabilityTags(equipment.raw['Capabilities / Effects']);
  if (caps.contains('combat_armor') || caps.contains('specialist_armor')) return true;
  return equipment.raw['Damage Reduction'] is num;
}

bool _toolHasCapability(EquipmentRow equipment, String capability) {
  return capabilityTags(equipment.raw['Capabilities / Effects']).contains(capability);
}

/// Bows for Double Shot and bow-only enchantment targets.
bool isBowItem(ItemRow? item, EquipmentRow equipment) {
  final subtype = lowerOrEmpty(item?.raw['Subtype']);
  final key = lowerOrEmpty(item?.raw['Internal Key']);
  final name = lowerOrEmpty(item?.raw['Display Name']);
  if (subtype == 'bow' || key.contains('bow') || RegExp(r'\bbow\b').hasMatch(name)) {
    return true;
  }
  final caps = capabilityTags(equipment.raw['Capabilities / Effects']);
  return caps.contains('bow') || caps.contains('bow_combat_xp');
}

bool _isMiningTool(ItemRow? item, EquipmentRow equipment) {
  if (isAxeItem(item, equipment)) return false;
  return _toolHasCapability(equipment, 'mining_tool');
}

bool _isFishingTool(ItemRow? item, EquipmentRow equipment) {
  return _toolHasCapability(equipment, 'fishing_tool');
}

bool _isWoodcuttingTool(ItemRow? item, EquipmentRow equipment) {
  if (isAxeItem(item, equipment)) return false;
  return _toolHasCapability(equipment, 'woodcutting_tool');
}

bool _equipmentMatchesEnchantment(
  GameDatabase db,
  String itemId,
  EquipmentRow equipment,
  EnchantmentRow enchantment,
) {
  final target = lowerOrEmpty(enchantment.raw['Valid Target']);
  final item = db.items.firstWhereOrNull((row) => row.raw['Item ID'] == itemId);
  final caps = capabilityTags(equipment.raw['Capabilities / Effects']);
  // Special-effect gear (e.g. Lucky Necklace) keeps its own bonus and cannot be enchanted.
  if (caps.contains('special_effect') || caps.contains('not_enchantable')) return false;
  // Craftable Jewelry (necklaces/rings) is flagged enchantable data-side and accepts
  // either gathering or weapon-category (combat) enchantments, despite not being a tool/weapon.
  final isEnchantableAccessory = caps.contains('arcana_enchantable');

  if (target.contains('bow')) return isBowItem(item, equipment);
  if (target.contains('mining')) return _isMiningTool(item, equipment);
  if (target.contains('fishing')) return _isFishingTool(item, equipment);
  if (target.contains('woodcutting')) return _isWoodcuttingTool(item, equipment);
  if (target.contains('weapon') &&
      (_isWeaponEquipment(item, equipment) || isEnchantableAccessory)) {
    return true;
  }
  if (target.contains('jewelry') && isEnchantableAccessory) return true;
  if (target.contains('gathering') &&
      (_isGatheringToolEquipment(item, equipment) || isEnchantableAccessory)) {
    return true;
  }
  if (target.contains('armor') && _isArmorEquipment(equipment)) return true;
  return false;
}

String encodeEnchantTarget(EnchantTarget target) {
  return switch (target) {
    EquippedEnchantTarget(:final slotId) => 'eq:$slotId',
    InventoryEnchantTarget(:final index) => 'inv:$index',
  };
}

EnchantTarget? decodeEnchantTarget(String? value) {
  if (isBlank(value)) return null;
  final raw = value!;
  if (raw.startsWith('eq:')) {
    return EquippedEnchantTarget(raw.substring(3));
  }
  if (raw.startsWith('inv:')) {
    final index = jsNumber(raw.substring(4));
    if (!jsIsInteger(index) || index < 0) return null;
    return InventoryEnchantTarget(index.toInt());
  }
  // Legacy: bare slot id from older saves/UI
  if (raw.startsWith('SLOT-')) {
    return EquippedEnchantTarget(raw);
  }
  return null;
}

/// Equipped slots and inventory stacks that can receive this enchantment.
List<EnchantTargetOption> eligibleEnchantmentTargets(
  GameDatabase db,
  PlayerSave save,
  EnchantmentRow enchantment,
) {
  final out = <EnchantTargetOption>[];

  for (final entry in save.equipment.slots.entries) {
    final stack = entry.value;
    if (stack == null || isBlank(stack.itemId) || isNotBlank(stack.enchantmentId)) continue;
    final equipment = db.equipment.firstWhereOrNull((row) => row.raw['Item ID'] == stack.itemId);
    if (equipment == null ||
        !_equipmentMatchesEnchantment(db, stack.itemId, equipment, enchantment)) {
      continue;
    }
    final itemName = db.items
        .firstWhereOrNull((row) => row.raw['Item ID'] == stack.itemId)
        ?.raw['Display Name'];
    final slotName = db.equipmentSlots
        .firstWhereOrNull((row) => row.raw['Slot ID'] == entry.key)
        ?.raw['Display Name'];
    final target = EquippedEnchantTarget(entry.key);
    out.add(
      EnchantTargetOption(
        id: encodeEnchantTarget(target),
        label:
            'Equipped · ${slotName ?? entry.key}: '
            '${itemName ?? stack.itemId}',
        target: target,
        preferred: true,
      ),
    );
  }

  for (final (index, stack) in save.inventory.indexed) {
    if (isBlank(stack.itemId) || isNotBlank(stack.enchantmentId)) continue;
    final equipment = db.equipment.firstWhereOrNull((row) => row.raw['Item ID'] == stack.itemId);
    if (equipment == null ||
        !_equipmentMatchesEnchantment(db, stack.itemId, equipment, enchantment)) {
      continue;
    }
    final itemName = db.items
        .firstWhereOrNull((row) => row.raw['Item ID'] == stack.itemId)
        ?.raw['Display Name'];
    final target = InventoryEnchantTarget(index);
    final quantitySuffix = stack.quantity > 1 ? ' ×${jsNumberToString(stack.quantity)}' : '';
    out.add(
      EnchantTargetOption(
        id: encodeEnchantTarget(target),
        label: 'Inventory · ${itemName ?? stack.itemId}$quantitySuffix',
        target: target,
        preferred: false,
      ),
    );
  }

  return out;
}

PlayerSave? applyEnchantmentToTarget(PlayerSave save, EnchantTarget target, String enchantmentId) {
  if (target is EquippedEnchantTarget) {
    final stack = save.equipment.slots[target.slotId];
    if (stack == null || isNotBlank(stack.enchantmentId)) return null;
    // Enchanted gear is unique — keep one enchanted item in the slot.
    if (stack.quantity > 1) {
      final remainder = stack.quantity - 1;
      final withEnchantedSlot = save.copyWith(
        equipment: EquipmentLoadout(
          slots: {
            ...save.equipment.slots,
            target.slotId: EquippedStack(
              itemId: stack.itemId,
              quantity: 1,
              enchantmentId: enchantmentId,
            ),
          },
        ),
      );
      return addItemToInventory(withEnchantedSlot, stack.itemId, remainder);
    }
    return save.copyWith(
      equipment: EquipmentLoadout(
        slots: {
          ...save.equipment.slots,
          target.slotId: stack.copyWith(quantity: 1, enchantmentId: enchantmentId),
        },
      ),
    );
  }

  final index = (target as InventoryEnchantTarget).index;
  final stack = index < 0 || index >= save.inventory.length ? null : save.inventory[index];
  if (stack == null || isNotBlank(stack.enchantmentId)) return null;

  final inventory = [...save.inventory];
  if (stack.quantity > 1) {
    inventory[index] = stack.copyWith(quantity: stack.quantity - 1);
    inventory.insert(
      index + 1,
      InventoryStack(itemId: stack.itemId, quantity: 1, enchantmentId: enchantmentId),
    );
  } else {
    inventory[index] = InventoryStack(
      itemId: stack.itemId,
      quantity: 1,
      enchantmentId: enchantmentId,
    );
  }

  return save.copyWith(inventory: inventory);
}

PlayerSave? applyEnchantmentToSlot(PlayerSave save, String slotId, String enchantmentId) {
  return applyEnchantmentToTarget(save, EquippedEnchantTarget(slotId), enchantmentId);
}

Iterable<String> _equippedEnchantmentIds(PlayerSave save) {
  return save.equipment.slots.values
      .where((stack) => stack != null && isNotBlank(stack.enchantmentId))
      .map((stack) => stack!.enchantmentId!);
}

String _effectOf(GameDatabase db, String enchantmentId) {
  final effect = getEnchantment(db, enchantmentId)?.raw['Effect'];
  return effect is String ? effect : '';
}

/// Flat damage bonus from equipped enchantments with explicit numeric data.
///
/// Legacy only: Minor Strength was reworked from +20 flat to +5% damage range.
num equippedEnchantmentDamageBonus(GameDatabase db, PlayerSave save) {
  num bonus = 0;
  for (final enchantmentId in _equippedEnchantmentIds(save)) {
    if (_effectOf(db, enchantmentId).contains('+20 minimum and maximum Damage')) {
      bonus += 20;
    }
  }
  return bonus;
}

/// Damage-range multiplier from weapon enchantments (+N% damage range).
num equippedEnchantmentDamageRangeMultiplier(GameDatabase db, PlayerSave save) {
  num percent = 0;
  for (final enchantmentId in _equippedEnchantmentIds(save)) {
    final match = RegExp(
      r'\+(\d+(?:\.\d+)?)%\s*damage range',
      caseSensitive: false,
    ).firstMatch(_effectOf(db, enchantmentId));
    if (match != null) percent += jsNumber(match.group(1));
  }
  return 1 + percent / 100;
}

/// Max-HP bonus percent from armor enchantments (e.g. Vital Plating).
num equippedEnchantmentMaxHpBonusPercent(GameDatabase db, PlayerSave save) {
  num percent = 0;
  for (final enchantmentId in _equippedEnchantmentIds(save)) {
    final match = RegExp(
      r'\+(\d+(?:\.\d+)?)%\s*maximum HP',
      caseSensitive: false,
    ).firstMatch(_effectOf(db, enchantmentId));
    if (match != null) percent += jsNumber(match.group(1));
  }
  return percent;
}

/// True when an equipped bow carries Double Shot.
bool equippedEnchantmentHasDoubleShot(GameDatabase db, PlayerSave save) {
  for (final stack in save.equipment.slots.values) {
    if (stack == null || isBlank(stack.itemId) || isBlank(stack.enchantmentId)) continue;
    final equipment = db.equipment.firstWhereOrNull((row) => row.raw['Item ID'] == stack.itemId);
    final item = db.items.firstWhereOrNull((row) => row.raw['Item ID'] == stack.itemId);
    if (equipment == null || !isBowItem(item, equipment)) continue;
    if (stack.enchantmentId == 'ENCH-0018') return true;
    final effect = _effectOf(db, stack.enchantmentId!);
    if (RegExp(r'attack twice', caseSensitive: false).hasMatch(effect)) return true;
  }
  return false;
}

const String _miningSkillId = 'SKL-0002';
const String _fishingSkillId = 'SKL-0003';
const String _woodcuttingSkillId = 'SKL-0006';

String? _skillIdFromDurationEffect(String effect) {
  if (RegExp(r'Mining Action duration', caseSensitive: false).hasMatch(effect)) {
    return _miningSkillId;
  }
  if (RegExp(r'Fishing Action duration', caseSensitive: false).hasMatch(effect)) {
    return _fishingSkillId;
  }
  if (RegExp(r'Woodcutting Action duration', caseSensitive: false).hasMatch(effect)) {
    return _woodcuttingSkillId;
  }
  if (RegExp(r'Gathering Action duration', caseSensitive: false).hasMatch(effect)) {
    return '*';
  }
  return null;
}

String? _skillIdFromAtrEffect(String effect) {
  if (RegExp(r'Mining action time reduction', caseSensitive: false).hasMatch(effect)) {
    return _miningSkillId;
  }
  if (RegExp(r'Fishing action time reduction', caseSensitive: false).hasMatch(effect)) {
    return _fishingSkillId;
  }
  if (RegExp(r'Woodcutting action time reduction', caseSensitive: false).hasMatch(effect)) {
    return _woodcuttingSkillId;
  }
  return null;
}

/// Action-time reduction percent from tool enchantments, keyed by skill.
Map<String, num> equippedEnchantmentActionTimeReductionBySkill(
  GameDatabase db,
  PlayerSave save,
) {
  final totals = <String, num>{};
  for (final enchantmentId in _equippedEnchantmentIds(save)) {
    final effect = _effectOf(db, enchantmentId);
    final skillId = _skillIdFromAtrEffect(effect);
    if (skillId == null) continue;
    final match = RegExp(
      r'\+(\d+(?:\.\d+)?)%\s+\w+\s+action time reduction',
      caseSensitive: false,
    ).firstMatch(effect);
    if (match == null) continue;
    totals[skillId] = (totals[skillId] ?? 0) + jsNumber(match.group(1));
  }
  return totals;
}

const String _critStrikeEnchantmentId = 'ENCH-0008';
const num _critStrikeChancePerEnchant = 10;

/// Total critical strike chance percent from equipped crit enchantments (adds across items).
num equippedEnchantmentCritChancePercent(GameDatabase db, PlayerSave save) {
  num percent = 0;
  for (final enchantmentId in _equippedEnchantmentIds(save)) {
    if (enchantmentId == _critStrikeEnchantmentId) {
      percent += _critStrikeChancePerEnchant;
      continue;
    }
    final match = RegExp(
      r'\+(\d+(?:\.\d+)?)%\s*Critical Strike Chance',
      caseSensitive: false,
    ).firstMatch(_effectOf(db, enchantmentId));
    if (match != null) percent += jsNumber(match.group(1));
  }
  return math.min(100, percent);
}

/// Critical strike damage multiplier (1.5×).
num criticalStrikeDamageMultiplier() => 1.5;

/// Percent of damage received in a combat round reflected back at the attacker (e.g. Thorns).
num equippedEnchantmentThornsPercent(GameDatabase db, PlayerSave save) {
  num percent = 0;
  for (final enchantmentId in _equippedEnchantmentIds(save)) {
    if (enchantmentId == 'ENCH-0006') {
      percent += 10;
      continue;
    }
    final match = RegExp(
      r'(\d+(?:\.\d+)?)%\s+of damage received',
      caseSensitive: false,
    ).firstMatch(_effectOf(db, enchantmentId));
    if (match != null) percent += jsNumber(match.group(1));
  }
  return percent;
}

/// Gathering duration multiplier from equipped enchantments.
///
/// Pass [skillId] so skill-specific minors (mining/fishing/woodcutting) only apply
/// to matching actions. Legacy ENCH-0002 still reduces all gathering.
num equippedEnchantmentGatheringMultiplier(
  GameDatabase db,
  PlayerSave save, [
  String? skillId,
]) {
  num multiplier = 1;
  for (final enchantmentId in _equippedEnchantmentIds(save)) {
    final effect = _effectOf(db, enchantmentId);
    if (enchantmentId == 'ENCH-0002') {
      multiplier *= 0.98;
      continue;
    }
    final match = RegExp(
      r'-(\d+(?:\.\d+)?)%\s+(.+?)\s+Action duration',
      caseSensitive: false,
    ).firstMatch(effect);
    if (match == null) continue;
    final scope = _skillIdFromDurationEffect(effect);
    if (scope == null) continue;
    if (scope != '*' && skillId != null && scope != skillId) continue;
    if (scope != '*' && skillId == null) continue;
    multiplier *= 1 - jsNumber(match.group(1)) / 100;
  }
  return math.max(0.01, multiplier);
}

/// Tooltip lines for an enchanted stack.
///
/// The TypeScript version takes the stack itself; the two Dart stack models have
/// no common supertype, so callers pass the field the function actually reads.
List<String> enchantmentTooltipLines(GameDatabase db, String? enchantmentId) {
  if (isBlank(enchantmentId)) return const <String>[];
  final row = getEnchantment(db, enchantmentId!);
  if (row == null) return <String>['Enchanted ($enchantmentId)'];
  final lines = <String>[jsString(row.raw['Display Name'])];
  final effect = row.raw['Effect'];
  if (effect is String && effect.isNotEmpty) lines.add(effect);
  return lines;
}
