import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../save/generated/save_models.dart';
import '../tags.dart';

final RegExp _relativeDropChanceTag = RegExp(r'^\+(\d+(?:\.\d+)?)%\s+relative\s+drop\s+chance$');
final RegExp _skillRelativeDropChanceTag = RegExp(
  r'^\+(\d+(?:\.\d+)?)%\s+relative\s+(.+?)\s+drop\s+chance$',
);

/// Sums every `+N% relative Drop Chance` tag in a capability string.
num parseRelativeDropChanceBonusPercent(Object? effects) {
  num total = 0;
  for (final tag in capabilityTags(effects)) {
    final match = _relativeDropChanceTag.firstMatch(tag);
    if (match != null) total += jsNumber(match.group(1));
  }
  return total;
}

/// Sum `+N% relative <skill> drop chance` tags that match this skill name.
num parseSkillRelativeDropChanceBonusPercent(Object? effects, String? skillName) {
  if (skillName == null || skillName.trim().isEmpty) return 0;
  final needle = skillName.trim().toLowerCase();
  num total = 0;
  for (final tag in capabilityTags(effects)) {
    final match = _skillRelativeDropChanceTag.firstMatch(tag);
    if (match == null) continue;
    if (match.group(2) == needle) total += jsNumber(match.group(1));
  }
  return total;
}

List<String> skillRelativeDropChanceTooltipLines(Object? effects) {
  final lines = <String>[];
  for (final tag in capabilityTags(effects)) {
    final match = _skillRelativeDropChanceTag.firstMatch(tag);
    if (match == null) continue;
    final skill = match.group(2)!;
    final labeled = skill
        .split(RegExp(r'\s+'))
        .map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
    lines.add('+${jsNumberToString(jsNumber(match.group(1)))}% relative $labeled Drop Chance');
  }
  return lines;
}

String? _skillDisplayNameForId(GameDatabase db, String? skillId) {
  if (isBlank(skillId)) return null;
  final name = db.skills
      .firstWhereOrNull((skill) => skill.raw['Skill ID'] == skillId)
      ?.raw['Display Name'];
  return name is String && name.isNotEmpty ? name : null;
}

/// Skill-gated gear bonuses (Scythe). Same bonus types add.
num equippedSkillRelativeDropChanceBonusPercent(GameDatabase db, PlayerSave save, String? skillId) {
  final skillName = _skillDisplayNameForId(db, skillId);
  if (skillName == null) return 0;
  num total = 0;
  for (final stack in save.equipment.slots.values) {
    if (stack == null || isBlank(stack.itemId)) continue;
    final equipment = db.equipment.firstWhereOrNull((row) => row.raw['Item ID'] == stack.itemId);
    total += parseSkillRelativeDropChanceBonusPercent(
      equipment?.raw['Capabilities / Effects'],
      skillName,
    );
  }
  return total;
}

/// Equipped gear bonuses (Lucky Necklace, future luck items). Same bonus types add.
num equippedRelativeDropChanceBonusPercent(GameDatabase db, PlayerSave save) {
  num total = 0;
  for (final stack in save.equipment.slots.values) {
    if (stack == null || isBlank(stack.itemId)) continue;
    final equipment = db.equipment.firstWhereOrNull((row) => row.raw['Item ID'] == stack.itemId);
    total += parseRelativeDropChanceBonusPercent(equipment?.raw['Capabilities / Effects']);
  }
  return total;
}

/// Total relative drop-chance bonus from all sources (gear + active luck potion).
/// Same bonus types stack by addition.
num totalRelativeDropChanceBonusPercent(GameDatabase db, PlayerSave save) {
  var total = equippedRelativeDropChanceBonusPercent(db, save);
  final potion = save.activePotionEffect;
  if (potion?.scope == 'one_action') {
    total += potion?.relativeDropChanceBonusPercent ?? 0;
  }
  return total;
}

/// Applies a summed relative drop-chance bonus: base × (1 + bonus/100), capped at 100.
num? applyRelativeDropChance(num? baseChance, num relativeBonusPercent) {
  if (baseChance == null) return null;
  if (relativeBonusPercent == 0 || relativeBonusPercent.isNaN) return baseChance;
  return math.min(100, baseChance * (1 + relativeBonusPercent / 100));
}

/// Add flat percentage points after relative bonuses, capped at 100.
num? applyFlatDropChanceBonus(num? chance, num flatBonusPercent) {
  if (chance == null) return null;
  if (flatBonusPercent == 0 || flatBonusPercent.isNaN) return chance;
  return math.min(100, chance + flatBonusPercent);
}
