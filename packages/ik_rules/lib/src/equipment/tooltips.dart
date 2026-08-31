import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../loot/drop_chance.dart';

String? _skillDisplayName(GameDatabase? db, String? skillId) {
  if (isBlank(skillId)) return null;
  if (db == null) return skillId;
  final name = db.skills
      .firstWhereOrNull((skill) => skill.raw['Skill ID'] == skillId)
      ?.raw['Display Name'];
  return name is String && name.isNotEmpty ? name : skillId;
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

  final atr = equipment.raw['Action Time Reduction %'];
  if (atr is num && atr > 0) {
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
          ? '-${jsNumberToString(atr)}% action time'
          : '${skills.join(', ')}: -${jsNumberToString(atr)}% action time',
    );
  }

  final dropBonus = parseRelativeDropChanceBonusPercent(equipment.raw['Capabilities / Effects']);
  if (dropBonus > 0) {
    lines.add('+${jsNumberToString(dropBonus)}% relative Drop Chance');
  }
  lines.addAll(skillRelativeDropChanceTooltipLines(equipment.raw['Capabilities / Effects']));

  return lines;
}

EquipmentRow? equipmentForItemId(GameDatabase db, String itemId) {
  return db.equipment.firstWhereOrNull((row) => row.raw['Item ID'] == itemId);
}
