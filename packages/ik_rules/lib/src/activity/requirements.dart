import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../save/generated/save_models.dart';
import 'xp.dart';

Set<String> _equippedCapabilityTags(GameDatabase db, PlayerSave save) {
  final tags = <String>{};
  for (final stack in save.equipment.slots.values) {
    if (stack == null || isBlank(stack.itemId)) continue;
    final equipment = db.equipment.firstWhereOrNull((row) => row.raw['Item ID'] == stack.itemId);
    final caps = equipment?.raw['Capabilities / Effects'];
    if (caps is! String) continue;
    for (final part in caps.split(';')) {
      final tag = part.trim().toLowerCase();
      if (tag.isNotEmpty) tags.add(tag);
    }
  }
  return tags;
}

/// Soft proficiency markers are not hard gates for Gathering.
bool isHardRequirement(RequirementRow requirement) {
  final type = requirement.requirementType;
  if (type == 'Tool Capability') return true;
  if (type == 'Station') return true;
  if (type == 'Skill Level') {
    return (requirement.operatorValue ?? '').toLowerCase() != 'proficiency';
  }
  return true;
}

List<RequirementRow> requirementsForEntity(GameDatabase db, String entityType, String entityId) {
  return db.requirements
      .where((row) => row.entityType == entityType && row.entityId == entityId)
      .toList();
}

class RequirementCheck {
  const RequirementCheck({required this.met, required this.detail});

  final bool met;
  final String detail;

  Map<String, Object?> toJson() => <String, Object?>{'met': met, 'detail': detail};
}

RequirementCheck evaluateRequirement(GameDatabase db, PlayerSave save, RequirementRow requirement) {
  final type = requirement.requirementType;
  final rawReference = requirement.referenceIdValue;
  final reference = rawReference == null ? '' : jsString(rawReference);

  if (type == 'Tool Capability') {
    final met = _equippedCapabilityTags(db, save).contains(reference.toLowerCase());
    return RequirementCheck(
      met: met,
      detail: met ? 'Has $reference' : 'Requires equipped ${reference.replaceAll('_', ' ')}',
    );
  }

  if (type == 'Station') {
    final facility = db.facilities.firstWhereOrNull((row) => row.raw['Facility ID'] == reference);
    final atLocation = facility?.raw['Location ID'] == save.currentLocationId;
    final name = facility?.raw['Display Name'] ?? 'station';
    return RequirementCheck(
      met: facility != null && atLocation,
      detail: atLocation ? 'At $name' : 'Requires $name at this location',
    );
  }

  if (type == 'Skill Level') {
    final skill = getSkillProgress(save, reference);
    final required = jsNumber(requirement.requiredValue ?? 1);
    final operator = (requirement.operatorValue ?? '>=').toLowerCase();
    if (operator == 'proficiency') {
      // Soft gate: always met for start validation, duration carries the penalty.
      return RequirementCheck(
        met: true,
        detail: skill.level >= required
            ? 'Proficiency ${jsNumberToString(required)}'
            : 'Below proficiency ${jsNumberToString(required)} (slower)',
      );
    }
    final met = skill.level >= required;
    return RequirementCheck(
      met: met,
      detail: met
          ? 'Level ${jsNumberToString(skill.level)}'
          : 'Requires $reference level ${jsNumberToString(required)}',
    );
  }

  return const RequirementCheck(met: true, detail: 'OK');
}

List<String> unmetHardRequirements(
  GameDatabase db,
  PlayerSave save,
  List<RequirementRow> requirements,
) {
  final failures = <String>[];
  for (final requirement in requirements) {
    if (!isHardRequirement(requirement)) continue;
    final result = evaluateRequirement(db, save, requirement);
    if (!result.met) failures.add(result.detail);
  }
  return failures;
}
