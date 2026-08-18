import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../npcs/knowledge.dart';
import '../projects/projects.dart';

/// One row of a skill menu: what it makes and the level it needs.
class SkillMenuListItem {
  const SkillMenuListItem({required this.id, required this.displayName, required this.level});

  final String id;
  final String displayName;

  /// Proficiency or required skill level, null when the row has none.
  final num? level;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'displayName': displayName,
    'level': level,
  };
}

/// Actions for a skill menu: display names only, unique by name.
List<SkillMenuListItem> actionsForSkill(GameDatabase db, String skillId) {
  final rows = db.actions
      .where(
        (action) =>
            action.raw['Relevant Skill ID'] == skillId &&
            action.raw['Status'] != 'Needs Data' &&
            isNotBlank((action.raw['Display Name'] as String?)?.trim()),
      )
      .toList();

  mergeSort(rows, compare: _compareSkillActions);

  final seen = <String>{};
  final items = <SkillMenuListItem>[];
  for (final action in rows) {
    final displayName = jsString(action.raw['Display Name']).trim();
    if (!seen.add(displayName)) continue;
    final proficiency = action.raw['Proficiency Level'];
    items.add(
      SkillMenuListItem(
        id: jsString(action.raw['Action ID']),
        displayName: displayName,
        level: proficiency is num ? proficiency : null,
      ),
    );
  }
  return items;
}

/// Projects for smithing / artisanry / arcana: output item name and level.
List<SkillMenuListItem> projectsForSkill(GameDatabase db, String skillId) {
  final rows = db.projects
      .where((project) => project.raw['Skill ID'] == skillId && isCompleteProject(project))
      .toList();

  mergeSort(
    rows,
    compare: (a, b) {
      final aLevel = _projectLevelForSkill(a, skillId) ?? double.infinity;
      final bLevel = _projectLevelForSkill(b, skillId) ?? double.infinity;
      if (aLevel != bLevel) return aLevel < bLevel ? -1 : 1;
      return jsLocaleCompare(projectOutputName(db, a), projectOutputName(db, b));
    },
  );

  final seen = <String>{};
  final items = <SkillMenuListItem>[];
  for (final project in rows) {
    final displayName = projectOutputName(db, project);
    if (displayName.isEmpty || !seen.add(displayName)) continue;
    items.add(
      SkillMenuListItem(
        id: jsString(project.raw['Project ID']),
        displayName: displayName,
        level: _projectLevelForSkill(project, skillId),
      ),
    );
  }
  return items;
}

/// Combined skill menu rows: actions first, then projects.
List<SkillMenuListItem> skillMenuEntries(GameDatabase db, String skillId) {
  return <SkillMenuListItem>[...actionsForSkill(db, skillId), ...projectsForSkill(db, skillId)];
}

/// `{level}. {name}` for a skill-menu row.
String skillMenuLine(SkillMenuListItem item) {
  final level = item.level;
  if (level == null) return item.displayName;
  final number = level == level.roundToDouble() ? level.toInt() : level;
  return '$number. ${item.displayName}';
}

/// Rows shown on a skill tile: smithing is grouped by material, others are listed.
List<SkillMenuListItem> skillMenuDisplayEntries(GameDatabase db, String skillId) {
  if (skillId != smithingSkillId) return skillMenuEntries(db, skillId);
  final items = <SkillMenuListItem>[...actionsForSkill(db, skillId)];
  final seen = <String>{};
  for (final project in projectsForSkill(db, skillId)) {
    final material = _smithingMaterial(project.displayName);
    if (material == null) {
      items.add(project);
      continue;
    }
    final key = '${project.level ?? ''}|$material';
    if (!seen.add(key)) continue;
    items.add(SkillMenuListItem(id: key, displayName: '$material items', level: project.level));
  }
  return items;
}

String? _smithingMaterial(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return null;
  return parts.first;
}

String projectOutputName(GameDatabase db, ProjectRow project) {
  final outputId = project.raw['Output Item / Target ID'];
  if (outputId is! String || outputId.isEmpty) return jsString(project.raw['Display Name']);
  if (isEnchantmentOutput(outputId)) {
    final enchantment = getEnchantment(db, outputId)?.raw['Display Name'];
    return enchantment is String ? enchantment : jsString(project.raw['Display Name']);
  }
  final item = db.items
      .firstWhereOrNull((row) => row.raw['Item ID'] == outputId)
      ?.raw['Display Name'];
  return item is String ? item : jsString(project.raw['Display Name']);
}

num? _projectLevelForSkill(ProjectRow project, String skillId) {
  return projectSkillRequirements(project)
      .firstWhereOrNull((requirement) => requirement.skillId == skillId)
      ?.level;
}

int _compareSkillActions(ActionRow a, ActionRow b) {
  final aProficiency = a.raw['Proficiency Level'];
  final bProficiency = b.raw['Proficiency Level'];
  final aLevel = aProficiency is num ? aProficiency : double.infinity;
  final bLevel = bProficiency is num ? bProficiency : double.infinity;
  if (aLevel != bLevel) return aLevel < bLevel ? -1 : 1;
  return jsLocaleCompare(jsString(a.raw['Display Name']), jsString(b.raw['Display Name']));
}
