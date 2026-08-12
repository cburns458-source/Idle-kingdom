import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../loot/drop_chance.dart';

/// Combat-facing equipment stats for hold tooltips.
List<String> equipmentTooltipStatLines(EquipmentRow? equipment) {
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

  final dropBonus = parseRelativeDropChanceBonusPercent(equipment.raw['Capabilities / Effects']);
  if (dropBonus > 0) {
    lines.add('+${jsNumberToString(dropBonus)}% relative Drop Chance');
  }

  return lines;
}

EquipmentRow? equipmentForItemId(GameDatabase db, String itemId) {
  return db.equipment.firstWhereOrNull((row) => row.raw['Item ID'] == itemId);
}
