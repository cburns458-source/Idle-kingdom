import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/pools.dart';
import '../activity/xp.dart';
import '../js_compat.dart';
import '../production/recipes.dart';
import '../save/generated/save_models.dart';
import '../world/submaps.dart';
import 'objectives.dart';
import 'progress.dart';
import 'quests.dart';

class QuestJournalStep {
  const QuestJournalStep({required this.key, required this.label, required this.state});

  final String key;
  final String label;
  final String state;

  Map<String, Object?> toJson() => <String, Object?>{'key': key, 'label': label, 'state': state};
}

List<QuestStepRow> getQuestSteps(GameDatabase db, String questId) {
  return db.questSteps
      .where((row) => row.questId == questId)
      .sorted((left, right) => left.stepOrder.compareTo(right.stepOrder))
      .toList();
}

bool questUsesSteps(GameDatabase db, String questId) {
  return getQuestSteps(db, questId).isNotEmpty;
}

/// Every authored step, marked done — used once the quest is finished.
List<QuestJournalStep> questCompletedJournal(GameDatabase db, QuestRow quest) {
  return getQuestSteps(db, jsString(quest['Quest ID']))
      .map((step) => QuestJournalStep(key: step.stepId, label: step.journalLabel, state: 'done'))
      .toList();
}

List<StructuredQuestObjectives> questObjectiveSources(GameDatabase db, QuestRow quest) {
  return [
    parseStructuredObjectives(quest),
    ...getQuestSteps(
      db,
      jsString(quest['Quest ID']),
    ).map((step) => parseNotesObjectives(step.notes ?? '')),
  ];
}

/// First Talk step for an NPC may still use the save-wide `talk:npc` flag.
num _talkProgressForStep(
  GameDatabase db,
  String questId,
  Map<String, num> counters,
  String talkKey,
  String stepId,
) {
  final scoped = counters['$talkKey:$stepId'] ?? 0;
  if (scoped >= 1) return scoped;
  final npcId = talkKey.substring('talk:'.length);
  final first = getQuestSteps(db, questId).cast<QuestStepRow?>().firstWhere(
    (step) => parseNotesObjectives(step!.notes ?? '').talkNpcIds.contains(npcId),
    orElse: () => null,
  );
  if (first?.stepId != stepId) return 0;
  return counters[talkKey] ?? 0;
}

List<QuestProgressLine> _scopedTalkLines(
  GameDatabase db,
  String questId,
  List<QuestProgressLine> lines,
  Map<String, num> counters,
  String? stepId,
) {
  if (stepId == null) return lines;
  return [
    for (final line in lines)
      if (line.key.startsWith('talk:'))
        QuestProgressLine(
          key: '${line.key}:$stepId',
          label: line.label,
          current: _talkProgressForStep(db, questId, counters, line.key, stepId),
          required: line.required,
        )
      else
        line,
  ];
}

bool _isAskAroundSkipped(GameDatabase db, PlayerSave save, String questId, String notes) {
  final structured = parseNotesObjectives(notes);
  if (structured.optionalTalkNpcIds.isEmpty) return false;
  if (hasQuestFlag(save, questId, 'choice:bribe') || hasQuestFlag(save, questId, 'choice:combat')) {
    return true;
  }
  final quest = getQuest(db, questId);
  if (quest == null) return false;
  return questAllStepDelivers(
    db,
    quest,
  ).any((line) => inventoryCount(save, line.targetId) >= line.quantity);
}

List<QuestProgressLine> _journalProgressLines(
  GameDatabase db,
  PlayerSave save,
  String questId,
  String notes,
) {
  final lines = _stepProgressLines(db, save, questId, notes);
  final structured = parseNotesObjectives(notes);
  if (structured.optionalTalkNpcIds.isEmpty) return lines;
  final counters = getQuestProgress(save, questId).counters ?? const <String, num>{};
  final revealed = structured.optionalTalkNpcIds.any(
    (npcId) => (counters['talk:$npcId'] ?? 0) >= 1,
  );
  if (revealed) return lines;
  return lines
      .where(
        (line) => !structured.talkNpcIds.any(
          (npcId) => line.key == 'talk:$npcId' || line.key.startsWith('talk:$npcId:'),
        ),
      )
      .toList();
}

/// Step types that only a dialogue action can complete.
const List<String> dialogueStepTypes = <String>['Talk', 'Show', 'HandIn'];

class StepItemNeed {
  const StepItemNeed({required this.itemId, required this.quantity});

  final String itemId;
  final int quantity;
}

QuestStepRow? getQuestStep(GameDatabase db, String questId, String stepId) {
  return db.questSteps.firstWhereOrNull((row) => row.stepId == stepId && row.questId == questId);
}

/// `Talk`, `Show` or `HandIn`, or null for a Notes-driven step.
String? dialogueStepType(QuestStepRow? step) {
  final raw = step?.raw['Step Type'];
  final type = raw is String ? raw.trim() : '';
  return dialogueStepTypes.contains(type) ? type : null;
}

final RegExp _wholeCount = RegExp(r'^\d+$');

/// `ITEM-x:n;ITEM-y:m` from a Show/HandIn step. Entries without a whole
/// quantity of at least 1 are skipped; repeated items are summed.
List<StepItemNeed> parseStepItems(Object? raw) {
  final needs = <StepItemNeed>[];
  if (raw is! String) return needs;
  for (final entry in raw.split(';')) {
    final parts = entry.split(':').map((part) => part.trim()).toList();
    if (parts.length != 2 || parts[0].isEmpty || !_wholeCount.hasMatch(parts[1])) continue;
    final quantity = int.parse(parts[1]);
    if (quantity < 1) continue;
    final index = needs.indexWhere((need) => need.itemId == parts[0]);
    if (index >= 0) {
      needs[index] = StepItemNeed(itemId: parts[0], quantity: needs[index].quantity + quantity);
    } else {
      needs.add(StepItemNeed(itemId: parts[0], quantity: quantity));
    }
  }
  return needs;
}

/// Counter holding how many of [itemId] the NPC already keeps for a HandIn step.
String handInCounterKey(String stepId, String itemId) => 'handIn:$stepId:$itemId';

bool isStepLatched(PlayerSave save, String questId, String stepId) {
  return (getQuestProgress(save, questId).counters?[stepCompleteKey(stepId)] ?? 0) >= 1;
}

bool _isStepComplete(
  GameDatabase db,
  PlayerSave save,
  String questId,
  String notes, [
  String? stepId,
]) {
  final counters = getQuestProgress(save, questId).counters ?? const <String, num>{};
  if (stepId != null && (counters[stepCompleteKey(stepId)] ?? 0) >= 1) return true;
  if (stepId != null && dialogueStepType(getQuestStep(db, questId, stepId)) != null) {
    return isStepPassed(db, save, questId, stepId);
  }
  if (_isAskAroundSkipped(db, save, questId, notes)) return true;
  final structured = parseNotesObjectives(notes);
  final progress = objectiveProgressFromStructured(db, save, structured, counters);
  final lines = _scopedTalkLines(db, questId, progress.progressLines, counters, stepId);
  if (lines.isEmpty) return true;
  return lines.every((line) => line.current >= line.required);
}

bool isStepComplete(
  GameDatabase db,
  PlayerSave save,
  String questId,
  String notes, [
  String? stepId,
]) => _isStepComplete(db, save, questId, notes, stepId);

/// Progress lines that read the bag right now rather than a saved counter.
final RegExp _liveInventoryLine = RegExp(r'^(?:deliver|hold):');

/// Whether the quest is already past [stepId]: a later step is latched, holds a
/// counter scoped to it (a talk or a partial hand-in), or is a Notes-driven step
/// whose saved-counter objectives are met. Lets saves from before a step was
/// typed Show / Talk / HandIn skip it; nothing is written.
bool isStepPassed(GameDatabase db, PlayerSave save, String questId, String stepId) {
  final steps = getQuestSteps(db, questId);
  final index = steps.indexWhere((step) => step.stepId == stepId);
  if (index < 0) return false;
  final counters = getQuestProgress(save, questId).counters ?? const <String, num>{};
  final keys = [
    for (final entry in counters.entries)
      if (entry.value > 0) entry.key,
  ];
  for (final later in steps.skip(index + 1)) {
    final laterId = later.stepId;
    if (keys.any((key) => key.endsWith(':$laterId') || key.startsWith('handIn:$laterId:'))) {
      return true;
    }
    if (dialogueStepType(later) != null) continue;
    final structured = parseNotesObjectives(later.notes ?? '');
    final progress = objectiveProgressFromStructured(db, save, structured, counters);
    final lines = _scopedTalkLines(
      db,
      questId,
      progress.progressLines,
      counters,
      laterId,
    ).where((line) => !_liveInventoryLine.hasMatch(line.key)).toList();
    if (lines.isNotEmpty && lines.every((line) => line.current >= line.required)) return true;
  }
  return false;
}

int getCurrentStepIndex(GameDatabase db, PlayerSave save, QuestRow quest) {
  final questId = jsString(quest['Quest ID']);
  final steps = getQuestSteps(db, questId);
  for (var index = 0; index < steps.length; index++) {
    final step = steps[index];
    if (!_isStepComplete(db, save, questId, step.notes ?? '', step.stepId)) return index;
  }
  return steps.length;
}

String? getCurrentStepId(GameDatabase db, PlayerSave save, QuestRow quest) {
  final steps = getQuestSteps(db, jsString(quest['Quest ID']));
  final index = getCurrentStepIndex(db, save, quest);
  if (index < 0 || index >= steps.length) return null;
  return steps[index].stepId;
}

/// Counter key that latches a quest step as done (BUG-01).
String stepCompleteKey(String stepId) => 'step:$stepId';

/// Latches completed steps and unlocks locations listed on completed steps
/// (`UnlockLocation` in step Notes).
///
/// Steps are latched in order: the first time every step up to and including
/// a step is complete, a `step:<stepId>` = 1 counter is stored so live checks
/// such as `Hold:` cannot regress the quest later (e.g. cooking raw potatoes).
PlayerSave applyQuestStepUnlocks(GameDatabase db, PlayerSave save) {
  var next = save;
  var unlocked = [...save.unlockedLocationIds];
  var changed = false;
  for (final quest in asQuestRows(db)) {
    final questId = jsString(quest['Quest ID']);
    if (getQuestProgress(next, questId).status != 'active') continue;
    var latching = true;
    for (final step in getQuestSteps(db, questId)) {
      final stepId = step.stepId;
      if (!_isStepComplete(db, next, questId, step.notes ?? '', stepId)) {
        latching = false;
        continue;
      }
      // Typed steps latch only through their dialogue action, never by being passed.
      if (latching && stepId.isNotEmpty && dialogueStepType(step) == null) {
        next = latchStep(next, questId, stepId);
      }
      for (final locationId in parseNotesObjectives(step.notes ?? '').unlockLocationIds) {
        final updated = unlockLocation(unlocked, locationId);
        if (updated.length != unlocked.length) {
          unlocked = updated;
          changed = true;
        }
      }
    }
  }
  return changed ? next.copyWith(unlockedLocationIds: unlocked) : next;
}

/// Replaces a quest's counters, keeping `progress` as their sum.
PlayerSave withQuestCounters(PlayerSave save, String questId, Map<String, num> counters) {
  final progress = getQuestProgress(save, questId);
  return save.copyWith(
    quests: [
      ...save.quests.where((row) => row.questId != questId),
      QuestProgress(
        questId: progress.questId,
        status: progress.status,
        counters: counters,
        progress: counters.values.fold<num>(0, (sum, value) => sum + value),
      ),
    ],
  );
}

/// Marks a step done for good (BUG-01). The one write path for Talk, Show and HandIn too.
PlayerSave latchStep(PlayerSave save, String questId, String stepId) {
  final key = stepCompleteKey(stepId);
  final progress = getQuestProgress(save, questId);
  if ((progress.counters?[key] ?? 0) >= 1) return save;
  final counters = <String, num>{...?progress.counters, key: 1};
  return save.copyWith(
    quests: [
      ...save.quests.where((row) => row.questId != questId),
      QuestProgress(
        questId: progress.questId,
        status: progress.status,
        counters: counters,
        progress: counters.values.fold<num>(0, (sum, value) => sum + value),
      ),
    ],
  );
}

String currentStepTalkKey(GameDatabase db, PlayerSave save, QuestRow quest, String npcId) {
  final questId = jsString(quest['Quest ID']);
  if (!questUsesSteps(db, questId)) return 'talk:$npcId';
  final steps = getQuestSteps(db, questId);
  final index = getCurrentStepIndex(db, save, quest);
  if (index < 0 || index >= steps.length) return 'talk:$npcId';
  return 'talk:$npcId:${steps[index].stepId}';
}

List<QuestProgressLine> _stepProgressLines(
  GameDatabase db,
  PlayerSave save,
  String questId,
  String notes, [
  String? stepId,
]) {
  final structured = parseNotesObjectives(notes);
  final counters = getQuestProgress(save, questId).counters ?? const <String, num>{};
  final lines = objectiveProgressFromStructured(db, save, structured, counters).progressLines;
  return _scopedTalkLines(db, questId, lines, counters, stepId);
}

List<QuestJournalStep> questStepJournal(GameDatabase db, PlayerSave save, QuestRow quest) {
  final questId = jsString(quest['Quest ID']);
  final steps = getQuestSteps(db, questId);
  if (steps.isEmpty) return const <QuestJournalStep>[];

  final currentIndex = getCurrentStepIndex(db, save, quest);
  if (currentIndex >= steps.length) {
    return questCompletedJournal(db, quest);
  }

  return steps.take(currentIndex + 1).toList().asMap().entries.expand((entry) {
    final step = entry.value;
    final done = entry.key < currentIndex;
    final head = QuestJournalStep(
      key: step.stepId,
      label: step.journalLabel,
      state: done ? 'done' : 'current',
    );
    final progressSource = done
        ? _stepProgressLines(
            db,
            save,
            questId,
            step.notes ?? '',
          ).where((line) => line.key.startsWith('action:')).toList()
        : _journalProgressLines(db, save, questId, step.notes ?? '');
    final progress = progressSource
        .map(
          (line) => QuestJournalStep(
            key: line.key,
            label: line.caption,
            state: line.current >= line.required ? 'done' : 'current',
          ),
        )
        .toList();
    return <QuestJournalStep>[head, ...progress];
  }).toList();
}

/// Skill and prior-quest gates for a quest that has not been accepted yet.
List<QuestJournalStep> questRequirementJournal(GameDatabase db, PlayerSave save, QuestRow quest) {
  final parsed = parseStructuredObjectives(quest);
  final steps = <QuestJournalStep>[];
  for (final requirement in parsed.requiresSkills) {
    final displayName = db.skills
        .firstWhereOrNull((row) => row.raw['Skill ID'] == requirement.targetId)
        ?.raw['Display Name'];
    final name = displayName is String ? displayName : requirement.targetId;
    final needed = requirement.quantity;
    final level = getSkillProgress(save, requirement.targetId).level;
    steps.add(
      QuestJournalStep(
        key: 'skill:${requirement.targetId}',
        label: 'Reach $name $needed ($level / $needed)',
        state: level >= needed ? 'done' : 'current',
      ),
    );
  }
  for (final requiredQuestId in parsed.requiresQuestIds) {
    final required = getQuest(db, requiredQuestId);
    final displayName = required?['Display Name'];
    final name = displayName is String ? displayName : requiredQuestId;
    final done = getQuestProgress(save, requiredQuestId).status == 'completed';
    steps.add(
      QuestJournalStep(
        key: 'quest:$requiredQuestId',
        label: 'Complete $name',
        state: done ? 'done' : 'current',
      ),
    );
  }
  if (steps.isEmpty) return steps;
  return [
    const QuestJournalStep(key: 'header:required', label: 'Required', state: 'header'),
    ...steps,
  ];
}

StructuredQuestObjectives? questActiveStepObjectives(
  GameDatabase db,
  PlayerSave save,
  QuestRow quest,
) {
  final questId = jsString(quest['Quest ID']);
  final steps = getQuestSteps(db, questId);
  if (steps.isEmpty) return null;

  final currentIndex = getCurrentStepIndex(db, save, quest);
  if (currentIndex >= steps.length) return null;

  return parseNotesObjectives(steps[currentIndex].notes ?? '');
}

List<QuestCounterTarget> questAllStepDelivers(GameDatabase db, QuestRow quest) {
  final questId = jsString(quest['Quest ID']);
  final delivers = <QuestCounterTarget>[];
  for (final step in getQuestSteps(db, questId)) {
    delivers.addAll(parseNotesObjectives(step.notes ?? '').delivers);
  }
  return delivers;
}

bool questAllStepsComplete(GameDatabase db, PlayerSave save, QuestRow quest) {
  final questId = jsString(quest['Quest ID']);
  if (!questUsesSteps(db, questId)) return false;
  return getCurrentStepIndex(db, save, quest) >= getQuestSteps(db, questId).length;
}

/// Non-talk progress on the current step (or quest Notes) is already satisfied.
bool nonTalkObjectivesMet(GameDatabase db, PlayerSave save, QuestRow quest) {
  final questId = jsString(quest['Quest ID']);
  if (!questUsesSteps(db, questId)) {
    final notes = quest['Notes'] is String ? quest['Notes']! as String : '';
    final lines = _stepProgressLines(db, save, questId, notes);
    return lines
        .where((line) => !line.key.startsWith('talk:'))
        .every((line) => line.current >= line.required);
  }
  final steps = getQuestSteps(db, questId);
  final index = getCurrentStepIndex(db, save, quest);
  if (index < 0 || index >= steps.length) return true;
  final step = steps[index];
  final lines = _stepProgressLines(db, save, questId, step.notes ?? '', step.stepId);
  return lines
      .where((line) => !line.key.startsWith('talk:'))
      .every((line) => line.current >= line.required);
}

/// Required or optional Talk on the current step (or quest Notes).
bool questCanTalkToNpc(GameDatabase db, PlayerSave save, QuestRow quest, String npcId) {
  final objectives = questUsesSteps(db, jsString(quest['Quest ID']))
      ? questActiveStepObjectives(db, save, quest)
      : parseStructuredObjectives(quest);
  if (objectives == null) return false;
  final talks =
      objectives.talkNpcIds.contains(npcId) || objectives.optionalTalkNpcIds.contains(npcId);
  if (!talks) return false;
  if (!objectives.holds.every((hold) => inventoryCount(save, hold.targetId) >= hold.quantity)) {
    return false;
  }
  return nonTalkObjectivesMet(db, save, quest);
}

/// True when this NPC still has an unfinished Talk step (or Notes talk).
bool questNpcHasIncompleteTalk(GameDatabase db, PlayerSave save, QuestRow quest, String npcId) {
  final questId = jsString(quest['Quest ID']);
  final steps = getQuestSteps(db, questId);
  if (steps.isEmpty) {
    return parseStructuredObjectives(quest).talkNpcIds.contains(npcId);
  }
  return steps.any(
    (step) =>
        parseNotesObjectives(step.notes ?? '').talkNpcIds.contains(npcId) &&
        !_isStepComplete(db, save, questId, step.notes ?? '', step.stepId),
  );
}

bool questTouchesNpcForSave(GameDatabase db, PlayerSave save, QuestRow quest, String npcId) {
  if (quest['NPC ID'] == npcId) {
    final status = getQuestProgress(save, jsString(quest['Quest ID'])).status;
    if (status == 'inactive') return questAvailableForSave(db, save, quest);
    return true;
  }

  final meta = parseStructuredObjectives(quest);
  final progress = getQuestProgress(save, jsString(quest['Quest ID']));
  if (progress.status != 'active') return false;

  if (meta.turnInNpcId == npcId || meta.choiceNpcId == npcId) {
    if (!questUsesSteps(db, jsString(quest['Quest ID']))) return true;
    if (questActiveStepObjectives(db, save, quest)?.talkNpcIds.contains(npcId) ?? false) {
      return true;
    }
    return !questNpcHasIncompleteTalk(db, save, quest, npcId);
  }

  return questCanTalkToNpc(db, save, quest, npcId);
}

/// Locked nodes stay hidden until a current Visit step (or a standing/unlock check) reveals them.
bool questRevealsLocation(GameDatabase db, PlayerSave save, String locationId) {
  for (final quest in asQuestRows(db)) {
    if (getQuestProgress(save, jsString(quest['Quest ID'])).status != 'active') continue;
    final step = questActiveStepObjectives(db, save, quest);
    if (step != null && step.visitLocationIds.contains(locationId)) return true;
  }
  return false;
}

/// Quest action counts that belong on this activity's dock card.
List<QuestProgressLine> questActionProgressForActivity(
  GameDatabase db,
  PlayerSave save,
  String activityId,
) {
  final activity = db.activities.firstWhereOrNull((row) => row.raw['Activity ID'] == activityId);
  final poolId = activity?.raw['Pool ID'];
  final actionIds = <String>{};
  if (poolId is String && poolId.isNotEmpty) {
    for (final candidate in eligiblePoolEntries(db, poolId)) {
      actionIds.add(jsString(candidate.action.raw['Action ID']));
    }
  }
  if (save.currentActivityId == activityId && save.currentActionId != null) {
    actionIds.add(save.currentActionId!);
  }
  if (actionIds.isEmpty) return const <QuestProgressLine>[];

  final lines = <QuestProgressLine>[];
  for (final quest in asQuestRows(db)) {
    final questId = jsString(quest['Quest ID']);
    if (getQuestProgress(save, questId).status != 'active') continue;
    if (questUsesSteps(db, questId)) {
      final index = getCurrentStepIndex(db, save, quest);
      final steps = getQuestSteps(db, questId);
      if (index < 0 || index >= steps.length) continue;
      final step = steps[index];
      for (final line in _stepProgressLines(db, save, questId, step.notes ?? '', step.stepId)) {
        if (!line.key.startsWith('action:')) continue;
        final actionId = line.key.substring('action:'.length);
        if (actionIds.contains(actionId)) lines.add(line);
      }
    } else {
      for (final line in _stepProgressLines(db, save, questId, jsString(quest['Notes']))) {
        if (!line.key.startsWith('action:')) continue;
        final actionId = line.key.substring('action:'.length);
        if (actionIds.contains(actionId)) lines.add(line);
      }
    }
  }
  return lines;
}
