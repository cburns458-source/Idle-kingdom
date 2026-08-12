import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/pools.dart';
import '../activity/requirements.dart';
import '../js_compat.dart';
import '../save/generated/save_models.dart';
import '../tags.dart';
import 'loadout.dart';

class AutoEquipProposal {
  const AutoEquipProposal({
    required this.activityId,
    required this.itemId,
    required this.itemName,
    required this.capabilities,
    required this.failureReason,
  });

  final String activityId;
  final String itemId;
  final String itemName;
  final List<String> capabilities;
  final String failureReason;

  Map<String, Object?> toJson() => <String, Object?>{
    'activityId': activityId,
    'itemId': itemId,
    'itemName': itemName,
    'capabilities': capabilities,
    'failureReason': failureReason,
  };
}

bool _equipmentProvidesAll(EquipmentRow equipment, List<String> needed) {
  final tags = capabilityTags(equipment.raw['Capabilities / Effects']).toSet();
  return needed.every(tags.contains);
}

num _toolTierScore(EquipmentRow equipment) {
  final level = jsNumber(equipment.raw['Required Level'] ?? 0);
  final actionTimeReduction = jsNumber(equipment.raw['Action Time Reduction %'] ?? 0);
  return level * 1000 + actionTimeReduction;
}

/// Hard tool-capability requirements checked when starting an activity.
List<String> toolCapabilitiesRequiredForActivity(GameDatabase db, String activityId) {
  final needed = <String>{};
  void collect(String entityType, String entityId) {
    for (final requirement in requirementsForEntity(db, entityType, entityId)) {
      if (!isHardRequirement(requirement)) continue;
      if (requirement.raw['Requirement Type'] != 'Tool Capability') continue;
      final capability = jsString(requirement.raw['Reference ID / Value'] ?? '')
          .trim()
          .toLowerCase();
      if (capability.isNotEmpty) needed.add(capability);
    }
  }

  collect('Activity', activityId);

  final activity = db.activities.firstWhereOrNull((row) => row.raw['Activity ID'] == activityId);
  final poolId = activity?.raw['Pool ID'];
  if (poolId is String && poolId.isNotEmpty) {
    for (final candidate in eligiblePoolEntries(db, poolId)) {
      collect('Action', jsString(candidate.action.raw['Action ID']));
    }
  }

  return needed.toList();
}

RequirementRow _toolCapabilityRequirement(String activityId, String capability) {
  return RequirementRow(<String, Object?>{
    'Requirement ID': 'auto-equip',
    'Entity Type': 'Activity',
    'Entity ID': activityId,
    'Requirement Group': 'A',
    'Group Logic': 'AND',
    'Requirement Type': 'Tool Capability',
    'Reference ID / Value': capability,
    'Operator': null,
    'Required Value': null,
    'Status': 'Planned',
    'Notes': null,
  });
}

List<String> missingToolCapabilities(GameDatabase db, PlayerSave save, String activityId) {
  return toolCapabilitiesRequiredForActivity(db, activityId)
      .where(
        (capability) =>
            !evaluateRequirement(db, save, _toolCapabilityRequirement(activityId, capability)).met,
      )
      .toList();
}

/// Proposes the highest-tier bag item that unblocks a missing tool capability.
///
/// Returns null when nothing is missing or nothing in the bag qualifies.
AutoEquipProposal? proposeAutoEquipForActivity(
  GameDatabase db,
  PlayerSave save,
  String activityId,
  String failureReason,
) {
  final missing = missingToolCapabilities(db, save, activityId);
  if (missing.isEmpty) return null;

  String? bestItemId;
  String bestItemName = '';
  num bestScore = 0;

  for (final stack in save.inventory) {
    if (stack.quantity <= 0) continue;
    final equipment = db.equipment.firstWhereOrNull((row) => row.raw['Item ID'] == stack.itemId);
    final slotId = equipment?.raw['Slot ID'];
    if (equipment == null || slotId is! String || slotId.isEmpty) continue;
    if (!_equipmentProvidesAll(equipment, missing)) continue;
    if (equipmentRequirementFailure(db, save, equipment) != null) continue;

    final displayName = db.items
        .firstWhereOrNull((item) => item.raw['Item ID'] == stack.itemId)
        ?.raw['Display Name'];
    final itemName = displayName is String ? displayName : stack.itemId;
    final score = _toolTierScore(equipment);
    // Ties break on name, using code-unit order the way JavaScript's `<` does.
    if (bestItemId == null ||
        score > bestScore ||
        (score == bestScore && itemName.compareTo(bestItemName) < 0)) {
      bestItemId = stack.itemId;
      bestItemName = itemName;
      bestScore = score;
    }
  }

  if (bestItemId == null) return null;

  return AutoEquipProposal(
    activityId: activityId,
    itemId: bestItemId,
    itemName: bestItemName,
    capabilities: missing,
    failureReason: failureReason,
  );
}

EquipResult applyAutoEquipProposal(GameDatabase db, PlayerSave save, AutoEquipProposal proposal) {
  return equipItemFromInventory(db, save, proposal.itemId);
}
