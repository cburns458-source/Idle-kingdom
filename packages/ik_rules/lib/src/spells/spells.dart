import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../projects/projects.dart';
import '../save/generated/save_models.dart';
import '../tags.dart';

const List<String> spellSlotIds = <String>['SLOT-0013', 'SLOT-0014', 'SLOT-0015', 'SLOT-0016'];

bool isSpellSlotId(String slotId) => spellSlotIds.contains(slotId);

bool isSpellEquipment(EquipmentRow? equipment) {
  if (equipment == null) return false;
  final tags = capabilityTags(equipment.raw['Capabilities / Effects']);
  if (tags.contains('spell') || tags.any((tag) => tag.startsWith('spell_effect:'))) {
    return true;
  }
  final slotId = equipment.raw['Slot ID'];
  return isSpellSlotId(slotId is String ? slotId : '');
}

bool isSpellItem(GameDatabase db, String itemId) {
  final item = db.items.firstWhereOrNull((row) => row.raw['Item ID'] == itemId);
  if (lowerOrEmpty(item?.raw['Category']) == 'spell') return true;
  final tags = jsString(item?.raw['Functional / Source Tags'] ?? '').toLowerCase();
  if (tags.contains('spell')) return true;
  return isSpellEquipment(db.equipment.firstWhereOrNull((row) => row.raw['Item ID'] == itemId));
}

String? firstEmptySpellSlot(PlayerSave save) {
  for (final slotId in spellSlotIds) {
    if (isBlank(save.equipment.slots[slotId]?.itemId)) return slotId;
  }
  return null;
}

/// All equipped spell stacks (empty slots omitted). Effects from each apply.
List<EquippedStack> equippedSpellStacks(PlayerSave save) {
  final out = <EquippedStack>[];
  for (final slotId in spellSlotIds) {
    final stack = save.equipment.slots[slotId];
    if (stack != null && isNotBlank(stack.itemId)) out.add(stack);
  }
  return out;
}

String? spellEffectEnchantmentId(GameDatabase db, String itemId) {
  final equipment = db.equipment.firstWhereOrNull((row) => row.raw['Item ID'] == itemId);
  for (final tag in capabilityTags(equipment?.raw['Capabilities / Effects'])) {
    if (tag.startsWith('spell_effect:')) {
      return tag.substring('spell_effect:'.length).toUpperCase();
    }
  }
  final itemTags = jsString(
    db.items
            .firstWhereOrNull((row) => row.raw['Item ID'] == itemId)
            ?.raw['Functional / Source Tags'] ??
        '',
  );
  for (final part in itemTags.split(';')) {
    final tag = part.trim().toLowerCase();
    if (tag.startsWith('spell_effect:')) {
      return tag.substring('spell_effect:'.length).toUpperCase();
    }
  }
  return null;
}

bool _spellAllowsStacking(GameDatabase db, String itemId) {
  final equipment = db.equipment.firstWhereOrNull((row) => row.raw['Item ID'] == itemId);
  final equipmentTags = capabilityTags(equipment?.raw['Capabilities / Effects']);
  if (equipmentTags.contains('spell_stacks')) return true;
  if (equipmentTags.contains('spell_no_stack')) return false;
  final item = db.items.firstWhereOrNull((row) => row.raw['Item ID'] == itemId);
  final itemTags = capabilityTags(item?.raw['Functional / Source Tags']);
  if (itemTags.contains('spell_stacks')) return true;
  if (itemTags.contains('spell_no_stack')) return false;
  // Default: stack (matches Strength / Abundance). Future uniques opt out with spell_no_stack.
  return true;
}

/// One spell's contribution to a percent bonus.
class SpellContribution {
  const SpellContribution({required this.percent, required this.stacks});

  final num percent;
  final bool stacks;
}

/// Combines percent bonuses from equipped spells.
///
/// Stacking spells add; non-stacking spells contribute only their best value.
num combineSpellPercentBonuses(List<SpellContribution> contributions) {
  num stacked = 0;
  num bestUnique = 0;
  for (final entry in contributions) {
    if (entry.percent <= 0) continue;
    if (entry.stacks) {
      stacked += entry.percent;
    } else {
      bestUnique = math.max(bestUnique, entry.percent);
    }
  }
  return stacked + bestUnique;
}

String _enchantmentEffect(GameDatabase db, String itemId) {
  final enchantmentId = spellEffectEnchantmentId(db, itemId);
  if (isBlank(enchantmentId)) return '';
  final effect = getEnchantment(db, enchantmentId!)?.raw['Effect'];
  return effect is String ? effect : '';
}

/// Damage-range bonus percent contributed by one spell item (0 if none).
num spellDamageRangeBonusPercent(GameDatabase db, String itemId) {
  final equipment = db.equipment.firstWhereOrNull((row) => row.raw['Item ID'] == itemId);
  for (final tag in capabilityTags(equipment?.raw['Capabilities / Effects'])) {
    final match = RegExp(r'^damage_range_bonus_percent:(\d+(?:\.\d+)?)$').firstMatch(tag);
    if (match != null) return jsNumber(match.group(1));
  }

  final match = RegExp(
    r'\+(\d+(?:\.\d+)?)%\s*damage range',
    caseSensitive: false,
  ).firstMatch(_enchantmentEffect(db, itemId));
  return match == null ? 0 : jsNumber(match.group(1));
}

/// Chance percent to double item drop quantity from one Abundance-style spell.
num spellItemDoubleChancePercent(GameDatabase db, String itemId) {
  final equipment = db.equipment.firstWhereOrNull((row) => row.raw['Item ID'] == itemId);
  for (final tag in capabilityTags(equipment?.raw['Capabilities / Effects'])) {
    final match = RegExp(r'^item_double_chance_percent:(\d+(?:\.\d+)?)$').firstMatch(tag);
    if (match != null) return jsNumber(match.group(1));
  }

  final match = RegExp(
    r'\+(\d+(?:\.\d+)?)%\s*chance to double item quantity',
    caseSensitive: false,
  ).firstMatch(_enchantmentEffect(db, itemId));
  return match == null ? 0 : jsNumber(match.group(1));
}

/// Multiplier from all equipped spells. Same bonus types add when spells stack
/// (2× Strength = +20% => 1.20).
num activeSpellDamageRangeMultiplier(GameDatabase db, PlayerSave save) {
  final contributions = equippedSpellStacks(save)
      .map(
        (stack) => SpellContribution(
          percent: spellDamageRangeBonusPercent(db, stack.itemId),
          stacks: _spellAllowsStacking(db, stack.itemId),
        ),
      )
      .toList();
  return 1 + combineSpellPercentBonuses(contributions) / 100;
}

/// Total chance to double item quantities on a successful drop (capped at 100).
num activeSpellItemDoubleChancePercent(GameDatabase db, PlayerSave save) {
  final contributions = equippedSpellStacks(save)
      .map(
        (stack) => SpellContribution(
          percent: spellItemDoubleChancePercent(db, stack.itemId),
          stacks: _spellAllowsStacking(db, stack.itemId),
        ),
      )
      .toList();
  return math.min(100, combineSpellPercentBonuses(contributions));
}

List<String> spellTooltipLines(GameDatabase db, ItemRow? item, String itemId) {
  final lines = <String>[];
  final enchantmentId = spellEffectEnchantmentId(db, itemId);
  final enchantment = isBlank(enchantmentId) ? null : getEnchantment(db, enchantmentId!);
  final displayName = enchantment?.raw['Display Name'];
  final effect = enchantment?.raw['Effect'];
  final description = item?.raw['Description'];
  if (displayName is String && displayName.isNotEmpty) lines.add(displayName);
  if (effect is String && effect.isNotEmpty) {
    lines.add(effect);
  } else if (description is String && description.isNotEmpty) {
    lines.add(description);
  }
  lines.add('Always active while equipped.');
  lines.add(
    _spellAllowsStacking(db, itemId)
        ? 'Duplicate copies stack.'
        : 'Does not stack with duplicate copies.',
  );
  return lines;
}
