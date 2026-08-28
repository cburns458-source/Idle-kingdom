import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/pools.dart';
import '../activity/xp.dart';
import '../js_compat.dart';
import '../production/recipes.dart';
import '../save/generated/save_models.dart';
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
  return questAllStepDelivers(db, quest).any(
    (line) => inventoryCount(save, line.targetId) >= line.quantity,
  );
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
  final revealed = structured.optionalTalkNpcIds.any((npcId) => (counters['talk:$npcId'] ?? 0) >= 1);
  if (revealed) return lines;
  return lines
      .where(
        (line) => !structured.talkNpcIds.any(
          (npcId) => line.key == 'talk:$npcId' || line.key.startsWith('talk:$npcId:'),
        ),
      )
      .toList();
}

bool _isStepComplete(
  GameDatabase db,
  PlayerSave save,
  String questId,
  String notes, [
  String? stepId,
]) {
  if (_isAskAroundSkipped(db, save, questId, notes)) return true;
  final structured = parseNotesObjectives(notes);
  final counters = getQuestProgress(save, questId).counters ?? const <String, num>{};
  final progress = objectiveProgressFromStructured(db, save, structured, counters);
  final lines = _scopedTalkLines(db, questId, progress.progressLines, counters, stepId);
  if (lines.isEmpty) return true;
  return lines.every((line) => line.current >= line.required);
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

String currentStepTalkKey(GameDatabase db, PlayerSave save, QuestRow quest, String npcId) {
  final questId = jsString(quest['Quest ID']);
  if (!questUsesSteps(db, questId)) return 'talk:$npcId';
  final steps = getQuestSteps(db, questId);
  final index = getCurrentStepIndex(db, save, quest);
  if (index < 0 || index >= steps.length) return 'talk:$npcId';
  return 'talk:$npcId:${steps[index].stepId}';
}

const String _citadelQuestId = 'QST-0004';
const String _citadelGuideNpcId = 'NPC-0013';

bool citadelGuideHeard(PlayerSave save) {
  return jsNumber(
        getQuestProgress(save, _citadelQuestId).counters?['talk:$_citadelGuideNpcId'] ?? 0,
      ) >=
      1;
}

List<QuestProgressLine> _stepProgressLines(
  GameDatabase db,
  PlayerSave save,
  String questId,
  String notes,
) {
  final structured = parseNotesObjectives(notes);
  final counters = getQuestProgress(save, questId).counters ?? const <String, num>{};
  return objectiveProgressFromStructured(db, save, structured, counters).progressLines;
}

List<QuestJournalStep> questStepJournal(GameDatabase db, PlayerSave save, QuestRow quest) {
  final questId = jsString(quest['Quest ID']);
  final steps = getQuestSteps(db, questId);
  if (steps.isEmpty) return const <QuestJournalStep>[];

  final currentIndex = getCurrentStepIndex(db, save, quest);
  if (questId == _citadelQuestId && citadelGuideHeard(save) && currentIndex >= 1) {
    final heard = steps.first;
    final remaining = steps.skip(1).expand((step) {
      return _stepProgressLines(db, save, questId, step.notes ?? '').map(
        (line) => QuestJournalStep(
          key: line.key,
          label: line.caption,
          state: line.current >= line.required ? 'done' : 'current',
        ),
      );
    });
    return [
      QuestJournalStep(key: heard.stepId, label: heard.journalLabel, state: 'done'),
      ...remaining,
    ];
  }

  if (currentIndex >= steps.length) {
    return steps
        .map((step) => QuestJournalStep(key: step.stepId, label: step.journalLabel, state: 'done'))
        .toList();
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
        ? _stepProgressLines(db, save, questId, step.notes ?? '')
              .where((line) => line.key.startsWith('action:'))
              .toList()
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
  return steps;
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

/// Required or optional Talk on the current step (or quest Notes).
bool questCanTalkToNpc(GameDatabase db, PlayerSave save, QuestRow quest, String npcId) {
  final objectives = questUsesSteps(db, jsString(quest['Quest ID']))
      ? questActiveStepObjectives(db, save, quest)
      : parseStructuredObjectives(quest);
  if (objectives == null) return false;
  final talks =
      objectives.talkNpcIds.contains(npcId) || objectives.optionalTalkNpcIds.contains(npcId);
  if (!talks) return false;
  return objectives.holds.every((hold) => inventoryCount(save, hold.targetId) >= hold.quantity);
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
      for (final step in getQuestSteps(db, questId)) {
        for (final line in _stepProgressLines(db, save, questId, step.notes ?? '')) {
          if (!line.key.startsWith('action:')) continue;
          final actionId = line.key.substring('action:'.length);
          if (actionIds.contains(actionId)) lines.add(line);
        }
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
