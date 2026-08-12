import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../production/recipes.dart';
import '../recipes/knowledge.dart';
import '../save/generated/save_models.dart';
import 'quests.dart';

/// One counted objective line.
class QuestCounterTarget {
  const QuestCounterTarget({required this.targetId, required this.quantity});

  /// ITEM / ENM / RCP / PRJ / LOC / FAC id depending on kind.
  final String targetId;
  final num quantity;

  Map<String, Object?> toJson() => <String, Object?>{'targetId': targetId, 'quantity': quantity};
}

/// Normalized quest objectives parsed from quest fields + Notes.
class StructuredQuestObjectives {
  const StructuredQuestObjectives({
    required this.kind,
    required this.delivers,
    required this.processTargets,
    required this.defeatTargets,
    required this.learnRecipeIds,
    required this.restoreFacilityIds,
    required this.constructPortalIds,
    required this.unlockTravelIds,
    required this.goldCost,
    required this.unlockLocationIds,
    required this.rewardRecipeIds,
    required this.rewardProjectNpcIds,
  });

  /// One of the Bible §14.4 kinds, e.g. `gather_deliver` or `defeat`.
  final String kind;
  final List<QuestCounterTarget> delivers;
  final List<QuestCounterTarget> processTargets;
  final List<QuestCounterTarget> defeatTargets;
  final List<String> learnRecipeIds;
  final List<String> restoreFacilityIds;
  final List<String> constructPortalIds;
  final List<String> unlockTravelIds;
  final num goldCost;
  final List<String> unlockLocationIds;
  final List<String> rewardRecipeIds;
  final List<String> rewardProjectNpcIds;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'delivers': delivers.map((line) => line.toJson()).toList(),
    'processTargets': processTargets.map((line) => line.toJson()).toList(),
    'defeatTargets': defeatTargets.map((line) => line.toJson()).toList(),
    'learnRecipeIds': learnRecipeIds,
    'restoreFacilityIds': restoreFacilityIds,
    'constructPortalIds': constructPortalIds,
    'unlockTravelIds': unlockTravelIds,
    'goldCost': goldCost,
    'unlockLocationIds': unlockLocationIds,
    'rewardRecipeIds': rewardRecipeIds,
    'rewardProjectNpcIds': rewardProjectNpcIds,
  };
}

final RegExp _idQuantity = RegExp(r'^([A-Z]+-\d+)\s*x\s*(\d+)$', caseSensitive: false);
final RegExp _bareId = RegExp(r'^[A-Z]+-\d+$');

List<QuestCounterTarget> _parseIdQtyList(String raw) {
  final out = <QuestCounterTarget>[];
  for (final part in raw.split(',')) {
    final match = _idQuantity.firstMatch(part.trim());
    if (match == null) continue;
    out.add(
      QuestCounterTarget(
        targetId: match.group(1)!.toUpperCase(),
        quantity: jsNumber(match.group(2)),
      ),
    );
  }
  return out;
}

List<String> _parseIdList(String raw) {
  return raw.split(',').map((part) => part.trim().toUpperCase()).where(_bareId.hasMatch).toList();
}

String normalizeObjectiveKind(Object? raw) {
  final value = lowerOrEmpty(raw);
  if (value.contains('defeat') || value.contains('kill') || value.contains('combat')) {
    return 'defeat';
  }
  if (value.contains('process') || value.contains('craft') || value.contains('cook')) {
    return 'process';
  }
  if (value.contains('learn') || value.contains('recipe')) return 'learn_recipe';
  if (value.contains('restore') || value.contains('facility')) return 'restore_facility';
  if (value.contains('portal')) return 'construct_portal';
  if (value.contains('travel') || value.contains('mount') || value.contains('route')) {
    return 'unlock_travel';
  }
  if (value.contains('guild')) return 'guild_collab';
  return 'gather_deliver';
}

String? _noteField(String notes, String pattern) {
  return RegExp(pattern, caseSensitive: false).firstMatch(notes)?.group(1);
}

/// Parses structured objectives from quest fields + Notes.
///
/// Notes extensions (semicolon-separated):
///   Deliver: ITEM-x xN, ...
///   Defeat: ENM-x xN, ...
///   Process: RCP-x xN, ...
///   LearnRecipe: RCP-x, ...
///   GoldCost: N
///   UnlockLocation: LOC-x
///   RewardRecipe: RCP-x
///   RewardProjectNpc: NPC-x
StructuredQuestObjectives parseStructuredObjectives(QuestRow quest) {
  final notes = quest['Notes'] is String ? quest['Notes']! as String : '';
  final kind = normalizeObjectiveKind(quest['Objective Type']);

  final delivers = <QuestCounterTarget>[];
  final defeatTargets = <QuestCounterTarget>[];
  final processTargets = <QuestCounterTarget>[];

  final deliverNote = _noteField(notes, r'Deliver:\s*([^;]+)');
  if (deliverNote != null) delivers.addAll(_parseIdQtyList(deliverNote));

  final defeatNote = _noteField(notes, r'Defeat:\s*([^;]+)');
  if (defeatNote != null) defeatTargets.addAll(_parseIdQtyList(defeatNote));

  final processNote = _noteField(notes, r'Process:\s*([^;]+)');
  if (processNote != null) processTargets.addAll(_parseIdQtyList(processNote));

  final learnNote = _noteField(notes, r'LearnRecipe:\s*([^;]+)');
  final restoreNote = _noteField(notes, r'RestoreFacility:\s*([^;]+)');
  final portalNote = _noteField(notes, r'ConstructPortal:\s*([^;]+)');
  final travelNote = _noteField(notes, r'UnlockTravel:\s*([^;]+)');
  final goldNote = _noteField(notes, r'GoldCost:\s*(\d+)');
  final unlockNote = _noteField(notes, r'UnlockLocation(?:s)?:\s*([^;]+)');
  final rewardRecipeNote = _noteField(notes, r'RewardRecipe:\s*([^;]+)');
  final rewardNpcNote = _noteField(notes, r'RewardProjectNpc:\s*([^;]+)');

  /// Field fallbacks apply only when Notes carried no lines of that kind.
  void addFieldFallback(String forKind, List<QuestCounterTarget> into) {
    if (into.isNotEmpty || kind != forKind) return;
    final targetId = quest['Objective Target ID'];
    final required = quest['Required Quantity'];
    if (targetId is String && targetId.isNotEmpty && required is num && required > 0) {
      into.add(QuestCounterTarget(targetId: targetId, quantity: required));
    }
  }

  addFieldFallback('gather_deliver', delivers);
  addFieldFallback('defeat', defeatTargets);
  addFieldFallback('process', processTargets);

  return StructuredQuestObjectives(
    kind: kind,
    delivers: delivers,
    processTargets: processTargets,
    defeatTargets: defeatTargets,
    learnRecipeIds: learnNote == null ? const <String>[] : _parseIdList(learnNote),
    restoreFacilityIds: restoreNote == null ? const <String>[] : _parseIdList(restoreNote),
    constructPortalIds: portalNote == null ? const <String>[] : _parseIdList(portalNote),
    unlockTravelIds: travelNote == null ? const <String>[] : _parseIdList(travelNote),
    goldCost: goldNote == null ? 0 : jsNumber(goldNote),
    unlockLocationIds: unlockNote == null ? const <String>[] : _parseIdList(unlockNote),
    rewardRecipeIds: rewardRecipeNote == null ? const <String>[] : _parseIdList(rewardRecipeNote),
    rewardProjectNpcIds: rewardNpcNote == null ? const <String>[] : _parseIdList(rewardNpcNote),
  );
}

/// One line of the quest tracker.
class QuestProgressLine {
  const QuestProgressLine({
    required this.key,
    required this.label,
    required this.current,
    required this.required,
  });

  final String key;
  final String label;
  final num current;
  final num required;

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'label': label,
    'current': current,
    'required': required,
  };
}

/// One deliverable item line, with how many the bag holds.
class QuestDeliverLine {
  const QuestDeliverLine({
    required this.itemId,
    required this.name,
    required this.owned,
    required this.required,
  });

  final String itemId;
  final String name;
  final num owned;
  final num required;

  Map<String, Object?> toJson() => <String, Object?>{
    'itemId': itemId,
    'name': name,
    'owned': owned,
    'required': required,
  };
}

class QuestObjectiveStatus {
  const QuestObjectiveStatus({
    required this.lines,
    required this.progressLines,
    required this.goldOwned,
    required this.goldRequired,
    required this.ready,
  });

  final List<QuestDeliverLine> lines;
  final List<QuestProgressLine> progressLines;
  final num goldOwned;
  final num goldRequired;
  final bool ready;

  Map<String, Object?> toJson() => <String, Object?>{
    'lines': lines.map((line) => line.toJson()).toList(),
    'progressLines': progressLines.map((line) => line.toJson()).toList(),
    'goldOwned': goldOwned,
    'goldRequired': goldRequired,
    'ready': ready,
  };
}

QuestObjectiveStatus questObjectiveProgress(GameDatabase db, PlayerSave save, QuestRow quest) {
  final structured = parseStructuredObjectives(quest);
  final counters =
      save.quests.firstWhereOrNull((row) => row.questId == quest['Quest ID'])?.counters ??
      const <String, num>{};

  final deliverLines = structured.delivers.map((line) {
    final displayName = db.items
        .firstWhereOrNull((item) => item.raw['Item ID'] == line.targetId)
        ?.raw['Display Name'];
    return QuestDeliverLine(
      itemId: line.targetId,
      name: displayName is String ? displayName : line.targetId,
      owned: inventoryCount(save, line.targetId),
      required: line.quantity,
    );
  }).toList();

  final progressLines = <QuestProgressLine>[
    for (final line in deliverLines)
      QuestProgressLine(
        key: 'deliver:${line.itemId}',
        label: 'Deliver ${line.name}',
        current: line.owned,
        required: line.required,
      ),
    for (final line in structured.defeatTargets)
      QuestProgressLine(
        key: 'defeat:${line.targetId}',
        label: 'Defeat ${_enemyName(db, line.targetId)}',
        current: counters['defeat:${line.targetId}'] ?? 0,
        required: line.quantity,
      ),
    for (final line in structured.processTargets)
      QuestProgressLine(
        key: 'process:${line.targetId}',
        label: 'Craft ${_recipeOrProjectName(db, line.targetId)}',
        current: counters['process:${line.targetId}'] ?? 0,
        required: line.quantity,
      ),
    for (final recipeId in structured.learnRecipeIds)
      QuestProgressLine(
        key: 'learn:$recipeId',
        label: 'Learn ${_recipeName(db, recipeId)}',
        current: knowsRecipe(save, db, recipeId) ? 1 : 0,
        required: 1,
      ),
    if (structured.goldCost > 0)
      QuestProgressLine(
        key: 'gold',
        label: 'Gold',
        current: save.gold,
        required: structured.goldCost,
      ),
  ];

  final counterReady = progressLines.every((line) => line.current >= line.required);
  final hasWork =
      progressLines.isNotEmpty ||
      structured.goldCost > 0 ||
      structured.restoreFacilityIds.isNotEmpty ||
      structured.constructPortalIds.isNotEmpty ||
      structured.unlockTravelIds.isNotEmpty;

  // Guild collab / restore / portal stay incomplete until those systems land.
  final deferredIncomplete =
      structured.kind == 'guild_collab' ||
      structured.restoreFacilityIds.isNotEmpty ||
      structured.constructPortalIds.isNotEmpty;

  return QuestObjectiveStatus(
    lines: deliverLines,
    progressLines: progressLines,
    goldOwned: save.gold,
    goldRequired: structured.goldCost,
    ready: hasWork && counterReady && !deferredIncomplete,
  );
}

String _enemyName(GameDatabase db, String enemyId) {
  final displayName = db.enemies
      .firstWhereOrNull((enemy) => enemy.raw['Enemy ID'] == enemyId)
      ?.raw['Display Name'];
  return displayName is String ? displayName : enemyId;
}

String _recipeName(GameDatabase db, String recipeId) {
  final displayName = db.recipes
      .firstWhereOrNull((recipe) => recipe.raw['Recipe ID'] == recipeId)
      ?.raw['Display Name'];
  return displayName is String ? displayName : recipeId;
}

String _recipeOrProjectName(GameDatabase db, String targetId) {
  final recipeName = db.recipes
      .firstWhereOrNull((recipe) => recipe.raw['Recipe ID'] == targetId)
      ?.raw['Display Name'];
  if (recipeName is String) return recipeName;
  final projectName = db.projects
      .firstWhereOrNull((project) => project.raw['Project ID'] == targetId)
      ?.raw['Display Name'];
  return projectName is String ? projectName : targetId;
}
