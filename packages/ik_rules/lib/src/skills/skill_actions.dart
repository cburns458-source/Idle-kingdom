import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
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
