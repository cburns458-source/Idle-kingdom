import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../production/recipes.dart';
import '../quests/progress.dart';
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

  if (type == 'Empty Slot') {
    final stack = save.equipment.slots[reference];
    final empty = stack == null || isBlank(stack.itemId) || stack.quantity <= 0;
    final slotName = db.equipmentSlots
        .firstWhereOrNull((row) => row.raw['Slot ID'] == reference)
        ?.raw['Display Name'];
    final name = slotName is String && slotName.isNotEmpty ? slotName : reference;
    return RequirementCheck(
      met: empty,
      detail: empty ? 'No $name equipped' : 'Requires no equipped $name',
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

  if (type == 'Quest Access') {
    final met = questIsActiveOrComplete(save, reference);
    return RequirementCheck(
      met: met,
      detail: met ? 'Quest unlocked' : 'Requires completing or starting that quest',
    );
  }

  if (type == 'Quest Active') {
    final met = questIsActive(save, reference);
    return RequirementCheck(met: met, detail: met ? 'Quest in progress' : 'Not available yet');
  }

  if (type == 'Quest Flag') {
    final parts = reference.split(':');
    if (parts.length < 2) {
      return const RequirementCheck(met: false, detail: 'Quest flag is incomplete.');
    }
    final questId = parts.first;
    final key = parts.sublist(1).join(':');
    final met = hasQuestFlag(save, questId, key);
    return RequirementCheck(met: met, detail: met ? 'Quest flag set' : 'Not available yet');
  }

  if (type == 'Item Absent') {
    final met = inventoryCount(save, reference) <= 0;
    return RequirementCheck(met: met, detail: met ? 'Item not held' : 'Already have that item');
  }

  return const RequirementCheck(met: true, detail: 'OK');
}

bool isQuestGateRequirement(String type) {
  return type == 'Quest Access' ||
      type == 'Quest Flag' ||
      type == 'Quest Active' ||
      type == 'Item Absent';
}

/// Hide gated activities until their quest flag, access, or item condition is met.
bool activityVisibleForSave(GameDatabase db, PlayerSave save, String activityId) {
  return entityVisibleForSave(db, save, 'Activity', activityId);
}

bool entityVisibleForSave(GameDatabase db, PlayerSave save, String entityType, String entityId) {
  for (final requirement in requirementsForEntity(db, entityType, entityId)) {
    if (!isQuestGateRequirement(requirement.requirementType)) continue;
    if (!evaluateRequirement(db, save, requirement).met) return false;
  }
  return true;
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
