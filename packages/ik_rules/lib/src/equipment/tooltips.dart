import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../loot/drop_chance.dart';
import '../potions/effects.dart';
import '../save/generated/save_models.dart';
import '../spells/spells.dart';
import 'loadout.dart';

String? _skillDisplayName(GameDatabase? db, String? skillId) {
  if (isBlank(skillId)) return null;
  if (db == null) return skillId;
  final name = db.skills
      .firstWhereOrNull((skill) => skill.raw['Skill ID'] == skillId)
      ?.raw['Display Name'];
  return name is String && name.isNotEmpty ? name : skillId;
}

/// Potion effect line from capability tags, always including the 6-use duration.
List<String> potionTooltipStatLines(EquipmentRow? equipment, String itemId) {
  final effect = parsePotionEffect(equipment, itemId);
  if (effect == null) return const <String>[];
  final parts = <String>[];
  final instant = effect.instantHealMaxHpPercent;
  if (instant != null && instant > 0) {
    parts.add('Heals ${jsNumberToString(instant)}%');
  }
  final regen = effect.regenMaxHpPercentPerRound;
  if (regen != null && regen > 0) {
    parts.add('Heals ${jsNumberToString(regen)}% each round');
  }
  final flatMin = effect.damageBonusMin;
  final flatMax = effect.damageBonusMax;
  if (flatMin != null && flatMax != null && (flatMin > 0 || flatMax > 0)) {
    parts.add('+${jsNumberToString(flatMin)}–${jsNumberToString(flatMax)} damage');
  }
  final damage = effect.damageBonusPercent;
  if (damage != null && damage > 0) {
    parts.add('+${jsNumberToString(damage)}% damage');
  }
  final drop = effect.relativeDropChanceBonusPercent;
  if (drop != null && drop > 0) {
    parts.add('+${jsNumberToString(drop)}% relative Drop Chance');
  }
  final duration = effect.baseDurationReductionPercent;
  if (duration != null && duration > 0) {
    parts.add('-${jsNumberToString(duration)}% base duration');
  }
  final poison = enemyCurrentHpDamagePercent(effect);
  if (poison != null && poison > 0) {
    parts.add('Deals ${jsNumberToString(poison)}% of enemy current HP each round');
  }
  parts.add('$potionActionDuration uses');
  return <String>[parts.join(', ')];
}

/// Combat-facing equipment stats for hold tooltips.
List<String> equipmentTooltipStatLines(EquipmentRow? equipment, [GameDatabase? db]) {
  if (equipment == null) return const <String>[];
  final lines = <String>[];
  final min = equipment.raw['Min Damage'];
  final max = equipment.raw['Max Damage'];
  if (min is num && max is num) {
    lines.add('Damage ${jsNumberToString(min)}–${jsNumberToString(math.max(min, max))}');
  } else if (min is num) {
    lines.add('Damage ${jsNumberToString(min)}');
  } else if (max is num) {
    lines.add('Damage ${jsNumberToString(max)}');
  }

  final hp = equipment.raw['HP Bonus'];
  if (hp is num && hp != 0) {
    lines.add(hp > 0 ? 'Health +${jsNumberToString(hp)}' : 'Health ${jsNumberToString(hp)}');
  }

  final reduction = equipment.raw['Damage Reduction'];
  if (reduction is num && reduction != 0) {
    lines.add(
      reduction > 0
          ? 'Damage reduction +${jsNumberToString(reduction)}'
          : 'Damage reduction ${jsNumberToString(reduction)}',
    );
  }

  final healing = equipment.raw['Healing Amount'];
  if (healing is num && healing != 0) {
    lines.add(
      healing > 0
          ? 'Healing +${jsNumberToString(healing)}'
          : 'Healing ${jsNumberToString(healing)}',
    );
  }

  final successRaw = equipment.raw['Action Time Reduction %'];
  if (successRaw is num && successRaw > 0) {
    final skills = <String>[];
    for (final id in <Object?>[
      equipment.raw['Required Skill ID'],
      equipment.raw['Secondary Required Skill ID'],
    ]) {
      final name = _skillDisplayName(db, id is String ? id : null);
      if (name != null) skills.add(name);
    }
    lines.add(
      skills.isEmpty
          ? '+${jsNumberToString(successRaw)}% success chance'
          : '${skills.join(', ')}: +${jsNumberToString(successRaw)}% success chance',
    );
  }

  final itemId = equipment.raw['Item ID'];
  final potionLines = itemId is String
      ? potionTooltipStatLines(equipment, itemId)
      : const <String>[];
  if (potionLines.isNotEmpty) {
    lines.addAll(potionLines);
  } else {
    final dropBonus = parseRelativeDropChanceBonusPercent(equipment.raw['Capabilities / Effects']);
    if (dropBonus > 0) {
      lines.add('+${jsNumberToString(dropBonus)}% relative Drop Chance');
    }
  }
  lines.addAll(skillRelativeDropChanceTooltipLines(equipment.raw['Capabilities / Effects']));
  final lockpickBreakReduction = parseLockpickBreakChanceReductionPercent(
    equipment.raw['Capabilities / Effects'],
  );
  if (lockpickBreakReduction != 0) {
    lines.add(
      lockpickBreakReduction > 0
          ? 'Lockpick break chance -${jsNumberToString(lockpickBreakReduction)}%'
          : 'Lockpick break chance +${jsNumberToString(lockpickBreakReduction.abs())}%',
    );
  }

  final spellPower = parseSpellPowerPercent(equipment.raw['Capabilities / Effects']);
  if (spellPower > 0) {
    lines.add('Equipped spells +${jsNumberToString(spellPower)}% stronger');
  }

  return lines;
}

EquipmentRow? equipmentForItemId(GameDatabase db, String itemId) {
  return db.equipment.firstWhereOrNull((row) => row.raw['Item ID'] == itemId);
}
