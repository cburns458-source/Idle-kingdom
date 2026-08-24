import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/xp.dart';
import '../activity/requirements.dart';
import '../equipment/specialist.dart';
import '../js_compat.dart';
import '../npcs/knowledge.dart';
import '../production/recipes.dart';
import '../save/generated/save_models.dart';

/// One material line of a project.
class ProjectInput {
  const ProjectInput({required this.itemId, required this.quantity});

  final String itemId;
  final num quantity;

  Map<String, Object?> toJson() => <String, Object?>{'itemId': itemId, 'quantity': quantity};
}

/// A skill gate on a project.
class ProjectSkillRequirement {
  const ProjectSkillRequirement({required this.skillId, required this.level});

  final String skillId;
  final num level;

  Map<String, Object?> toJson() => <String, Object?>{'skillId': skillId, 'level': level};
}

/// A Special Production station in the location menu.
class SpecialProductionStation {
  const SpecialProductionStation({
    required this.facility,
    required this.skillId,
    required this.skillName,
    required this.label,
  });

  final FacilityRow facility;
  final String skillId;
  final String skillName;
  final String label;

  Map<String, Object?> toJson() => <String, Object?>{
    'facilityId': facility.raw['Facility ID'],
    'skillId': skillId,
    'skillName': skillName,
    'label': label,
  };
}

/// Menu labels for Special Production stations (place names, not skill names).
String specialProductionStationLabel(String skillId, String skillName) {
  if (skillId == 'SKL-0011') return 'Smithing forge';
  if (skillId == 'SKL-0012') return 'Artisans workshop';
  if (skillId == 'SKL-0013') return 'Mages quarters';
  return skillName;
}

bool isCompleteProject(ProjectRow project) {
  if (project.raw['Status'] == 'Needs Data') return false;
  if (project.raw['Instant'] != 'Yes') return false;
  if (project.raw['XP Reward'] is! num) return false;
  if (project.raw['Output Quantity'] is! num) return false;
  if (isBlank(project.raw['Output Item / Target ID'] as String?) ||
      isBlank(project.raw['Facility ID'] as String?) ||
      isBlank(project.raw['Skill ID'] as String?)) {
    return false;
  }
  return project.raw['Gold Cost'] is num;
}

List<ProjectInput> projectInputs(ProjectRow project) {
  final out = <ProjectInput>[];
  for (var slot = 1; slot <= 4; slot += 1) {
    final itemId = project.raw['Input $slot Item ID'];
    final quantity = project.raw['Input $slot Quantity'];
    if (itemId is String && itemId.isNotEmpty && quantity is num && quantity > 0) {
      out.add(ProjectInput(itemId: itemId, quantity: quantity));
    }
  }
  return out;
}

/// Project inputs after equipped modifiers (Wizard's Hat essence discount).
List<ProjectInput> projectInputsForSave(PlayerSave save, ProjectRow project) {
  return projectInputs(project)
      .map(
        (input) => input.itemId == essenceItemId
            ? ProjectInput(itemId: input.itemId, quantity: wizardEssenceCost(input.quantity, save))
            : input,
      )
      .toList();
}

List<ProjectSkillRequirement> projectSkillRequirements(ProjectRow project) {
  final out = <ProjectSkillRequirement>[];
  for (var slot = 1; slot <= 3; slot += 1) {
    final skillId = project.raw['Required Skill $slot ID'];
    final level = project.raw['Required Skill $slot Level'];
    if (skillId is String && skillId.isNotEmpty && level is num) {
      out.add(ProjectSkillRequirement(skillId: skillId, level: level));
    }
  }
  return out;
}

ProjectRow? getProject(GameDatabase db, String projectId) {
  return db.projects.firstWhereOrNull((project) => project.raw['Project ID'] == projectId);
}

EnchantmentRow? getEnchantment(GameDatabase db, String enchantmentId) {
  return db.enchantments.firstWhereOrNull((row) => row.raw['Enchantment ID'] == enchantmentId);
}

bool isEnchantmentOutput(String outputId) => outputId.startsWith('ENCH-');

bool meetsProjectSkills(PlayerSave save, ProjectRow project) {
  return projectSkillRequirements(
    project,
  ).every((requirement) => getSkillProgress(save, requirement.skillId).level >= requirement.level);
}

bool meetsProjectKnowledge(GameDatabase db, PlayerSave save, ProjectRow project) {
  return hasProjectKnowledge(db, save, jsString(project.raw['Skill ID'])).ok;
}

/// A skill gate the player has not reached yet.
class UnmetProjectSkill {
  const UnmetProjectSkill({
    required this.skillId,
    required this.skillName,
    required this.level,
    required this.have,
  });

  final String skillId;
  final String skillName;
  final num level;
  final num have;

  Map<String, Object?> toJson() => <String, Object?>{
    'skillId': skillId,
    'skillName': skillName,
    'level': level,
    'have': have,
  };
}

List<UnmetProjectSkill> unmetProjectSkillRequirements(
  GameDatabase db,
  PlayerSave save,
  ProjectRow project,
) {
  return projectSkillRequirements(project)
      .map((requirement) {
        final displayName = db.skills
            .firstWhereOrNull((skill) => skill.raw['Skill ID'] == requirement.skillId)
            ?.raw['Display Name'];
        return UnmetProjectSkill(
          skillId: requirement.skillId,
          skillName: displayName is String ? displayName : requirement.skillId,
          level: requirement.level,
          have: getSkillProgress(save, requirement.skillId).level,
        );
      })
      .where((requirement) => requirement.have < requirement.level)
      .toList();
}

/// Crafts affordable from bag materials. Infinite when the project needs none.
num maxProjectsFromMaterials(PlayerSave save, ProjectRow project) {
  final inputs = projectInputsForSave(save, project);
  if (inputs.isEmpty) return double.infinity;
  num max = double.infinity;
  for (final input in inputs) {
    max = math.min(max, (inventoryCount(save, input.itemId) / input.quantity).floor());
  }
  return max.isFinite ? math.max(0, max) : 0;
}

/// Crafts affordable from gold. Infinite when the project is free.
num maxProjectsFromGold(PlayerSave save, ProjectRow project) {
  final cost = jsNumber(project.raw['Gold Cost'] ?? 0);
  if (cost <= 0) return double.infinity;
  return (save.gold / cost).floor();
}

num maxProjectQuantity(PlayerSave save, ProjectRow project) {
  final materialMax = maxProjectsFromMaterials(save, project);
  final goldMax = maxProjectsFromGold(save, project);
  if (!materialMax.isFinite && !goldMax.isFinite) return 1;
  return math.max(0, math.min(materialMax, goldMax));
}

/// Launch projects at a facility (skill gates affect completion, not listing).
List<ProjectRow> projectsForFacility(GameDatabase db, String facilityId, [String? skillId]) {
  final lookupId = projectFacilityIdForLookup(facilityId);
  final matching = db.projects
      .where(
        (project) =>
            isCompleteProject(project) &&
            project.raw['Facility ID'] == lookupId &&
            (isBlank(skillId) || project.raw['Skill ID'] == skillId),
      )
      .toList();
  mergeSort(
    matching,
    compare: (a, b) => jsCompareThen(
      jsNumberOrZero(a.raw['Required Skill 1 Level']) -
          jsNumberOrZero(b.raw['Required Skill 1 Level']),
      () => jsLocaleCompare(jsString(a.raw['Display Name']), jsString(b.raw['Display Name'])),
    ),
  );
  return matching;
}

/// Special Production stations at a location, derived from Facilities + Projects.
///
/// Instant projects do not use the Primary Activity slot.
List<SpecialProductionStation> specialProductionStationsAt(GameDatabase db, String locationId) {
  final facilities = db.facilities.where(
    (facility) =>
        facility.raw['Location ID'] == locationId &&
        facility.raw['Status'] != 'Needs Data' &&
        facility.raw['Facility Type'] == 'Special Production Station',
  );

  final stations = <SpecialProductionStation>[];
  for (final facility in facilities) {
    final lookupId = projectFacilityIdForLookup(jsString(facility.raw['Facility ID']));
    final skillIds = <String>{};
    for (final project in db.projects) {
      if (!isCompleteProject(project) || project.raw['Facility ID'] != lookupId) continue;
      skillIds.add(jsString(project.raw['Skill ID']));
    }
    for (final skillId in skillIds) {
      final displayName = db.skills
          .firstWhereOrNull((skill) => skill.raw['Skill ID'] == skillId)
          ?.raw['Display Name'];
      final skillName = displayName is String ? displayName : skillId;
      stations.add(
        SpecialProductionStation(
          facility: facility,
          skillId: skillId,
          skillName: skillName,
          label: specialProductionStationLabel(skillId, skillName),
        ),
      );
    }
  }

  // Artisanry uses the Crafting Workshop facility (not typed as Special Production Station).
  final workshops = db.facilities.where(
    (facility) =>
        facility.raw['Location ID'] == locationId &&
        projectFacilityIdForLookup(jsString(facility.raw['Facility ID'])) == 'FAC-0003',
  );
  for (final facility in workshops) {
    final lookupId = projectFacilityIdForLookup(jsString(facility.raw['Facility ID']));
    final hasArtisanry = db.projects.any(
      (project) =>
          isCompleteProject(project) &&
          project.raw['Skill ID'] == 'SKL-0012' &&
          project.raw['Facility ID'] == lookupId,
    );
    if (!hasArtisanry) continue;
    if (stations.any(
      (station) =>
          station.facility.raw['Facility ID'] == facility.raw['Facility ID'] &&
          station.skillId == 'SKL-0012',
    )) {
      continue;
    }
    stations.add(
      SpecialProductionStation(
        facility: facility,
        skillId: 'SKL-0012',
        skillName: 'Artisanry',
        label: specialProductionStationLabel('SKL-0012', 'Artisanry'),
      ),
    );
  }

  mergeSort(stations, compare: (a, b) => jsLocaleCompare(a.label, b.label));
  return stations;
}

/// Stations the player can see, hiding ones still gated by a quest.
List<SpecialProductionStation> specialProductionStationsVisibleAt(
  GameDatabase db,
  PlayerSave save,
  String locationId,
) {
  return specialProductionStationsAt(db, locationId)
      .where(
        (station) => entityVisibleForSave(
          db,
          save,
          'Facility',
          jsString(station.facility.raw['Facility ID']),
        ),
      )
      .toList();
}
