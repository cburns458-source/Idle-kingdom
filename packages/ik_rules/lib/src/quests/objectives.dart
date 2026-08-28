import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../production/recipes.dart';
import '../recipes/knowledge.dart';
import '../save/generated/save_models.dart';
import 'quests.dart';
import 'steps.dart';

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
    required this.talkNpcIds,
    required this.optionalTalkNpcIds,
    required this.visitLocationIds,
    required this.inspectIds,
    required this.holds,
    required this.actionTargets,
    required this.requiresSkills,
    required this.requiresQuestIds,
    required this.unlockOnAcceptLocationIds,
    required this.rewardXp,
    required this.goldCost,
    required this.acceptGoldCost,
    required this.rewardGold,
    required this.bribeGold,
    required this.branchSkillXp,
    required this.choiceNpcId,
    required this.turnInNpcId,
    required this.autoStartLocationId,
    required this.autoCompleteOnTalk,
    required this.autoCompleteOnVisit,
    required this.unlockLocationIds,
    required this.rewardRecipeIds,
    required this.rewardProjectNpcIds,
    required this.rewardCosmeticIds,
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
  final List<String> talkNpcIds;
  final List<String> optionalTalkNpcIds;
  final List<String> visitLocationIds;
  final List<String> inspectIds;
  final List<QuestCounterTarget> holds;
  final List<QuestCounterTarget> actionTargets;
  final List<QuestCounterTarget> requiresSkills;
  final List<String> requiresQuestIds;
  final List<String> unlockOnAcceptLocationIds;
  final List<QuestCounterTarget> rewardXp;
  final num goldCost;
  final num acceptGoldCost;
  final num rewardGold;
  final num bribeGold;
  final num branchSkillXp;
  final String? choiceNpcId;
  final String? turnInNpcId;
  final String? autoStartLocationId;
  final bool autoCompleteOnTalk;
  final bool autoCompleteOnVisit;
  final List<String> unlockLocationIds;
  final List<String> rewardRecipeIds;
  final List<String> rewardProjectNpcIds;
  final List<String> rewardCosmeticIds;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'delivers': delivers.map((line) => line.toJson()).toList(),
    'processTargets': processTargets.map((line) => line.toJson()).toList(),
    'defeatTargets': defeatTargets.map((line) => line.toJson()).toList(),
    'learnRecipeIds': learnRecipeIds,
    'restoreFacilityIds': restoreFacilityIds,
    'constructPortalIds': constructPortalIds,
    'unlockTravelIds': unlockTravelIds,
    'talkNpcIds': talkNpcIds,
    'optionalTalkNpcIds': optionalTalkNpcIds,
    'visitLocationIds': visitLocationIds,
    'inspectIds': inspectIds,
    'holds': holds.map((line) => line.toJson()).toList(),
    'actionTargets': actionTargets.map((line) => line.toJson()).toList(),
    'requiresSkills': requiresSkills.map((line) => line.toJson()).toList(),
    'requiresQuestIds': requiresQuestIds,
    'unlockOnAcceptLocationIds': unlockOnAcceptLocationIds,
    'rewardXp': rewardXp.map((line) => line.toJson()).toList(),
    'goldCost': goldCost,
    'acceptGoldCost': acceptGoldCost,
    'rewardGold': rewardGold,
    'bribeGold': bribeGold,
    'branchSkillXp': branchSkillXp,
    'choiceNpcId': choiceNpcId,
    'turnInNpcId': turnInNpcId,
    'autoStartLocationId': autoStartLocationId,
    'autoCompleteOnTalk': autoCompleteOnTalk,
    'autoCompleteOnVisit': autoCompleteOnVisit,
    'unlockLocationIds': unlockLocationIds,
    'rewardRecipeIds': rewardRecipeIds,
    'rewardProjectNpcIds': rewardProjectNpcIds,
    'rewardCosmeticIds': rewardCosmeticIds,
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

final RegExp _skillAmount = RegExp(r'^(SKL-\d+)\s+(\d+)$', caseSensitive: false);

List<QuestCounterTarget> _parseSkillAmountList(String raw) {
  final out = <QuestCounterTarget>[];
  for (final part in raw.split(',')) {
    final match = _skillAmount.firstMatch(part.trim());
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

List<String> _parseTokenList(String raw) {
  return raw
      .split(',')
      .map((part) => part.trim().toLowerCase())
      .where((part) => part.isNotEmpty)
      .toList();
}

String? _singleId(String? raw) {
  if (raw == null) return null;
  final ids = _parseIdList(raw);
  return ids.isEmpty ? null : ids.first;
}

/// Parses objective tokens from Notes (not reward metadata).
StructuredQuestObjectives parseNotesObjectives(
  String notes, {
  String kind = 'gather_deliver',
  String? fallbackTargetId,
  num? fallbackQuantity,
}) {
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
  final talkNote = _noteField(notes, r'(?:^|;)\s*Talk:\s*([^;]+)');
  final optionalTalkNote = _noteField(notes, r'(?:^|;)\s*OptionalTalk:\s*([^;]+)');
  final visitNote = _noteField(notes, r'Visit:\s*([^;]+)');
  final inspectNote = _noteField(notes, r'Inspect:\s*([^;]+)');
  final holdNote = _noteField(notes, r'Hold:\s*([^;]+)');
  final actionNote = _noteField(notes, r'Action:\s*([^;]+)');
  final goldNote = _noteField(notes, r'GoldCost:\s*(\d+)');

  if (delivers.isEmpty && kind == 'gather_deliver') {
    if (fallbackTargetId != null &&
        fallbackTargetId.isNotEmpty &&
        fallbackQuantity != null &&
        fallbackQuantity > 0) {
      delivers.add(QuestCounterTarget(targetId: fallbackTargetId, quantity: fallbackQuantity));
    }
  }

  if (defeatTargets.isEmpty && kind == 'defeat') {
    if (fallbackTargetId != null &&
        fallbackTargetId.isNotEmpty &&
        fallbackQuantity != null &&
        fallbackQuantity > 0) {
      defeatTargets.add(QuestCounterTarget(targetId: fallbackTargetId, quantity: fallbackQuantity));
    }
  }

  if (processTargets.isEmpty && kind == 'process') {
    if (fallbackTargetId != null &&
        fallbackTargetId.isNotEmpty &&
        fallbackQuantity != null &&
        fallbackQuantity > 0) {
      processTargets.add(
        QuestCounterTarget(targetId: fallbackTargetId, quantity: fallbackQuantity),
      );
    }
  }

  return StructuredQuestObjectives(
    kind: kind,
    delivers: delivers,
    processTargets: processTargets,
    defeatTargets: defeatTargets,
    learnRecipeIds: learnNote == null ? const <String>[] : _parseIdList(learnNote),
    restoreFacilityIds: restoreNote == null ? const <String>[] : _parseIdList(restoreNote),
    constructPortalIds: portalNote == null ? const <String>[] : _parseIdList(portalNote),
    unlockTravelIds: travelNote == null ? const <String>[] : _parseIdList(travelNote),
    talkNpcIds: talkNote == null ? const <String>[] : _parseIdList(talkNote),
    optionalTalkNpcIds: optionalTalkNote == null
        ? const <String>[]
        : _parseIdList(optionalTalkNote),
    visitLocationIds: visitNote == null ? const <String>[] : _parseIdList(visitNote),
    inspectIds: inspectNote == null ? const <String>[] : _parseTokenList(inspectNote),
    holds: holdNote == null ? const <QuestCounterTarget>[] : _parseIdQtyList(holdNote),
    actionTargets: actionNote == null ? const <QuestCounterTarget>[] : _parseIdQtyList(actionNote),
    requiresSkills: const <QuestCounterTarget>[],
    requiresQuestIds: const <String>[],
    unlockOnAcceptLocationIds: const <String>[],
    rewardXp: const <QuestCounterTarget>[],
    goldCost: goldNote == null ? 0 : jsNumber(goldNote),
    acceptGoldCost: 0,
    rewardGold: 0,
    bribeGold: 0,
    branchSkillXp: 0,
    choiceNpcId: null,
    turnInNpcId: null,
    autoStartLocationId: null,
    autoCompleteOnTalk: false,
    autoCompleteOnVisit: false,
    unlockLocationIds: const <String>[],
    rewardRecipeIds: const <String>[],
    rewardProjectNpcIds: const <String>[],
    rewardCosmeticIds: const <String>[],
  );
}

/// Parses structured objectives from quest fields + Notes.
///
/// Notes extensions (semicolon-separated):
///   Deliver: ITEM-x xN, ...
///   Defeat: ENM-x xN, ...
///   Process: RCP-x xN, ...
///   LearnRecipe: RCP-x, ...
///   Talk: NPC-x, ...
///   OptionalTalk: NPC-x, ...
///   Visit: LOC-x, ...
///   Inspect: bazaar, bounties, processing
///   GoldCost: N
///   AcceptGold: N
///   RewardGold: N
///   BribeGold: N
///   BranchSkillXp: N
///   ChoiceNpc: NPC-x
///   TurnInNpc: NPC-x
///   AutoStart: LOC-x
///   UnlockLocation: LOC-x
///   RewardRecipe: RCP-x
///   RewardProjectNpc: NPC-x
///   RewardCosmetic: COS-x
StructuredQuestObjectives parseStructuredObjectives(QuestRow quest) {
  final notes = quest['Notes'] is String ? quest['Notes']! as String : '';
  final kind = normalizeObjectiveKind(quest['Objective Type']);
  final targetId = quest['Objective Target ID'];
  final required = quest['Required Quantity'];
  final objectives = parseNotesObjectives(
    notes,
    kind: kind,
    fallbackTargetId: targetId is String ? targetId : null,
    fallbackQuantity: required is num ? required : null,
  );

  final acceptGoldNote = _noteField(notes, r'AcceptGold:\s*(\d+)');
  final rewardGoldNote = _noteField(notes, r'RewardGold:\s*(\d+)');
  final bribeGoldNote = _noteField(notes, r'BribeGold:\s*(\d+)');
  final branchXpNote = _noteField(notes, r'BranchSkillXp:\s*(\d+)');
  final choiceNpcNote = _noteField(notes, r'ChoiceNpc:\s*([^;]+)');
  final turnInNote = _noteField(notes, r'TurnInNpc:\s*([^;]+)');
  final autoStartNote = _noteField(notes, r'AutoStart:\s*([^;]+)');
  final unlockNote = _noteField(notes, r'UnlockLocation(?:s)?:\s*([^;]+)');
  final unlockOnAcceptNote = _noteField(notes, r'UnlockOnAccept:\s*([^;]+)');
  final requiresSkillNote = _noteField(notes, r'RequiresSkill:\s*([^;]+)');
  final requiresQuestNote = _noteField(notes, r'RequiresQuest:\s*([^;]+)');
  final rewardXpNote = _noteField(notes, r'RewardXp:\s*([^;]+)');
  final rewardRecipeNote = _noteField(notes, r'RewardRecipe:\s*([^;]+)');
  final rewardNpcNote = _noteField(notes, r'RewardProjectNpc:\s*([^;]+)');
  final rewardCosmeticNote = _noteField(notes, r'RewardCosmetic:\s*([^;]+)');

  return StructuredQuestObjectives(
    kind: objectives.kind,
    delivers: objectives.delivers,
    processTargets: objectives.processTargets,
    defeatTargets: objectives.defeatTargets,
    learnRecipeIds: objectives.learnRecipeIds,
    restoreFacilityIds: objectives.restoreFacilityIds,
    constructPortalIds: objectives.constructPortalIds,
    unlockTravelIds: objectives.unlockTravelIds,
    talkNpcIds: objectives.talkNpcIds,
    optionalTalkNpcIds: objectives.optionalTalkNpcIds,
    visitLocationIds: objectives.visitLocationIds,
    inspectIds: objectives.inspectIds,
    holds: objectives.holds,
    actionTargets: objectives.actionTargets,
    requiresSkills: requiresSkillNote == null
        ? const <QuestCounterTarget>[]
        : _parseSkillAmountList(requiresSkillNote),
    requiresQuestIds: requiresQuestNote == null
        ? const <String>[]
        : _parseIdList(requiresQuestNote),
    unlockOnAcceptLocationIds: unlockOnAcceptNote == null
        ? const <String>[]
        : _parseIdList(unlockOnAcceptNote),
    rewardXp: rewardXpNote == null
        ? const <QuestCounterTarget>[]
        : _parseSkillAmountList(rewardXpNote),
    goldCost: objectives.goldCost,
    acceptGoldCost: acceptGoldNote == null ? 0 : jsNumber(acceptGoldNote),
    rewardGold: rewardGoldNote == null ? 0 : jsNumber(rewardGoldNote),
    bribeGold: bribeGoldNote == null ? 0 : jsNumber(bribeGoldNote),
    branchSkillXp: branchXpNote == null ? 0 : jsNumber(branchXpNote),
    choiceNpcId: _singleId(choiceNpcNote),
    turnInNpcId: _singleId(turnInNote),
    autoStartLocationId: _singleId(autoStartNote),
    autoCompleteOnTalk: RegExp(r'AutoCompleteOnTalk', caseSensitive: false).hasMatch(notes),
    autoCompleteOnVisit: RegExp(r'AutoCompleteOnVisit', caseSensitive: false).hasMatch(notes),
    unlockLocationIds: unlockNote == null ? const <String>[] : _parseIdList(unlockNote),
    rewardRecipeIds: rewardRecipeNote == null ? const <String>[] : _parseIdList(rewardRecipeNote),
    rewardProjectNpcIds: rewardNpcNote == null ? const <String>[] : _parseIdList(rewardNpcNote),
    rewardCosmeticIds: rewardCosmeticNote == null
        ? const <String>[]
        : _parseIdList(rewardCosmeticNote),
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

QuestObjectiveStatus objectiveProgressFromStructured(
  GameDatabase db,
  PlayerSave save,
  StructuredQuestObjectives structured, [
  Map<String, num> counters = const <String, num>{},
]) {
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
    for (final npcId in structured.talkNpcIds)
      QuestProgressLine(
        key: 'talk:$npcId',
        label: 'Talk to ${_npcDisplayName(db, npcId)}',
        current: counters['talk:$npcId'] ?? 0,
        required: 1,
      ),
    for (final locationId in structured.visitLocationIds)
      QuestProgressLine(
        key: 'visit:$locationId',
        label: 'Visit ${_locationDisplayName(db, locationId)}',
        current: counters['visit:$locationId'] ?? 0,
        required: 1,
      ),
    for (final inspectId in structured.inspectIds)
      QuestProgressLine(
        key: 'inspect:$inspectId',
        label: _inspectLabel(inspectId),
        current: counters['inspect:$inspectId'] ?? 0,
        required: 1,
      ),
    for (final line in structured.holds)
      QuestProgressLine(
        key: 'hold:${line.targetId}',
        label: 'Show ${_itemName(db, line.targetId)}',
        current: inventoryCount(save, line.targetId),
        required: line.quantity,
      ),
    for (final line in structured.actionTargets)
      QuestProgressLine(
        key: 'action:${line.targetId}',
        label: _actionName(db, line.targetId),
        current: counters['action:${line.targetId}'] ?? 0,
        required: line.quantity,
      ),
    if (structured.goldCost > 0)
      QuestProgressLine(
        key: 'gold',
        label: 'Gold',
        current: save.gold,
        required: structured.goldCost,
      ),
  ];

  return QuestObjectiveStatus(
    lines: deliverLines,
    progressLines: progressLines,
    goldOwned: save.gold,
    goldRequired: structured.goldCost,
    ready: false,
  );
}

QuestObjectiveStatus questObjectiveProgress(GameDatabase db, PlayerSave save, QuestRow quest) {
  final questId = jsString(quest['Quest ID']);
  final progress = save.quests.firstWhereOrNull((row) => row.questId == questId);
  StructuredQuestObjectives structured;
  if (progress?.status == 'active' && questUsesSteps(db, questId)) {
    final stepObjectives = questActiveStepObjectives(db, save, quest);
    structured = stepObjectives ?? parseNotesObjectives('');
  } else {
    structured = parseStructuredObjectives(quest);
  }
  final counters = progress?.counters ?? const <String, num>{};
  final body = objectiveProgressFromStructured(db, save, structured, counters);

  final counterReady = body.progressLines.every((line) => line.current >= line.required);
  final hasWork =
      body.progressLines.isNotEmpty ||
      structured.goldCost > 0 ||
      structured.restoreFacilityIds.isNotEmpty ||
      structured.constructPortalIds.isNotEmpty ||
      structured.unlockTravelIds.isNotEmpty;

  final deferredIncomplete =
      structured.kind == 'guild_collab' ||
      structured.restoreFacilityIds.isNotEmpty ||
      structured.constructPortalIds.isNotEmpty;

  return QuestObjectiveStatus(
    lines: body.lines,
    progressLines: body.progressLines,
    goldOwned: body.goldOwned,
    goldRequired: body.goldRequired,
    ready: progress?.status == 'active' && questUsesSteps(db, questId)
        ? questAllStepsComplete(db, save, quest)
        : hasWork && counterReady && !deferredIncomplete,
  );
}

List<QuestJournalStep> questLegacyJournalSteps(GameDatabase db, PlayerSave save, QuestRow quest) {
  final structured = parseStructuredObjectives(quest);
  final counters =
      save.quests.firstWhereOrNull((row) => row.questId == quest['Quest ID'])?.counters ??
      const <String, num>{};
  final allLines = objectiveProgressFromStructured(db, save, structured, counters).progressLines;
  if (allLines.isEmpty) return const <QuestJournalStep>[];

  final firstOpen = allLines.indexWhere((line) => line.current < line.required);
  final currentIndex = firstOpen == -1 ? allLines.length - 1 : firstOpen;

  return allLines.take(currentIndex + 1).toList().asMap().entries.map((entry) {
    return QuestJournalStep(
      key: entry.value.key,
      label: entry.value.label,
      state: entry.key < currentIndex || firstOpen == -1 ? 'done' : 'current',
    );
  }).toList();
}

String _itemName(GameDatabase db, String itemId) {
  final displayName = db.items
      .firstWhereOrNull((item) => item.raw['Item ID'] == itemId)
      ?.raw['Display Name'];
  return displayName is String ? displayName : itemId;
}

String _actionName(GameDatabase db, String actionId) {
  final displayName = db.actions
      .firstWhereOrNull((action) => action.raw['Action ID'] == actionId)
      ?.raw['Display Name'];
  return displayName is String ? displayName : actionId;
}

String _npcDisplayName(GameDatabase db, String npcId) {
  final displayName = db.npcs
      .firstWhereOrNull((row) => row.raw['NPC ID'] == npcId)
      ?.raw['Display Name'];
  return displayName is String ? displayName : npcId;
}

String _locationDisplayName(GameDatabase db, String locationId) {
  final displayName = db.locations
      .firstWhereOrNull((row) => row.raw['Location ID'] == locationId)
      ?.raw['Display Name'];
  return displayName is String ? displayName : locationId;
}

String _inspectLabel(String inspectId) {
  if (inspectId == 'bazaar') return 'Inspect the Grand Bazaar';
  if (inspectId == 'bounties') return 'Inspect the Bounty Board';
  if (inspectId == 'processing') return 'Use a Processing District station';
  return 'Inspect $inspectId';
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
