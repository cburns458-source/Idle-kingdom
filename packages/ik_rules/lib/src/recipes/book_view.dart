import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../production/recipes.dart';
import '../projects/projects.dart';
import '../save/generated/save_models.dart';
import '../skills/skill_actions.dart';
import 'knowledge.dart';

/// One group inside a recipe-book tab.
class RecipeBookSection {
  const RecipeBookSection({this.title, required this.entries});

  final String? title;
  final List<RecipeBookEntry> entries;
}

/// One tab of a recipe book, matching the skill-menu tab labels.
class RecipeBookTab {
  const RecipeBookTab({required this.id, required this.label, required this.sections});

  final String id;
  final String label;
  final List<RecipeBookSection> sections;
}

/// Tabbed recipe book for one skill or a station's filtered rows.
class RecipeBookView {
  const RecipeBookView({required this.skillId, required this.tabs});

  final String skillId;
  final List<RecipeBookTab> tabs;
}

String? recipeBookSkillId(GameDatabase db, List<RecipeBookEntry> entries) {
  if (entries.isEmpty) return null;
  final first = entries.first;
  if (first.kind == 'recipe') {
    final skillId = getRecipe(db, first.id)?.raw['Skill ID'];
    return skillId is String && skillId.isNotEmpty ? skillId : null;
  }
  final skillId = getProject(db, first.id)?.raw['Skill ID'];
  return skillId is String && skillId.isNotEmpty ? skillId : null;
}

RecipeBookView recipeBookView(PlayerSave save, GameDatabase db, String skillId) {
  return recipeBookViewForEntries(db, skillId, recipeBookForSkill(save, db, skillId));
}

RecipeBookView recipeBookViewForEntries(
  GameDatabase db,
  String skillId,
  List<RecipeBookEntry> entries,
) {
  final buckets = <String, _TabBucket>{};
  for (final entry in entries) {
    final outputId = entry.kind == 'project'
        ? jsString(getProject(db, entry.id)?.raw['Output Item / Target ID'])
        : jsString(getRecipe(db, entry.id)?.raw['Output Item ID']);
    final placement = skillMenuPlacementForOutput(db, skillId, entry.name, outputId);
    final bucket = buckets.putIfAbsent(
      placement.tabId,
      () => _TabBucket(id: placement.tabId, label: placement.tabLabel),
    );
    bucket.add(placement.sectionTitle, entry);
  }
  final tabOrder = [for (final tab in skillMenuView(db, skillId).tabs) tab.id];
  final tabs = <RecipeBookTab>[
    for (final id in tabOrder)
      if (buckets[id] case final bucket?) bucket.toTab(),
    for (final bucket in buckets.values)
      if (!tabOrder.contains(bucket.id)) bucket.toTab(),
  ];
  if (tabs.isEmpty) {
    return RecipeBookView(
      skillId: skillId,
      tabs: const [RecipeBookTab(id: 'actions', label: 'Actions', sections: [])],
    );
  }
  return RecipeBookView(skillId: skillId, tabs: tabs);
}

class _TabBucket {
  _TabBucket({required this.id, required this.label});

  final String id;
  final String label;
  final List<String?> _sectionOrder = <String?>[];
  final Map<String?, List<RecipeBookEntry>> _sections = <String?, List<RecipeBookEntry>>{};

  void add(String? title, RecipeBookEntry entry) {
    if (!_sections.containsKey(title)) {
      _sectionOrder.add(title);
      _sections[title] = <RecipeBookEntry>[];
    }
    _sections[title]!.add(entry);
  }

  RecipeBookTab toTab() {
    return RecipeBookTab(
      id: id,
      label: label,
      sections: [
        for (final title in _sectionOrder)
          RecipeBookSection(title: title, entries: _sections[title]!),
      ],
    );
  }
}
