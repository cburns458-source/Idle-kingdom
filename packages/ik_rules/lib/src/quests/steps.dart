import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../save/generated/save_models.dart';
import 'objectives.dart';
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

bool _isStepComplete(GameDatabase db, PlayerSave save, String questId, String notes) {
  final structured = parseNotesObjectives(notes);
  final counters = getQuestProgress(save, questId).counters ?? const <String, num>{};
  final progress = objectiveProgressFromStructured(db, save, structured, counters);
  if (progress.progressLines.isEmpty) return true;
  return progress.progressLines.every((line) => line.current >= line.required);
}

int getCurrentStepIndex(GameDatabase db, PlayerSave save, QuestRow quest) {
  final questId = jsString(quest['Quest ID']);
  final steps = getQuestSteps(db, questId);
  for (var index = 0; index < steps.length; index++) {
    if (!_isStepComplete(db, save, questId, steps[index].notes ?? '')) return index;
  }
  return steps.length;
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
          label: line.label,
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

  return steps.take(currentIndex + 1).toList().asMap().entries.map((entry) {
    final step = entry.value;
    return QuestJournalStep(
      key: step.stepId,
      label: step.journalLabel,
      state: entry.key < currentIndex ? 'done' : 'current',
    );
  }).toList();
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
  return objectives.talkNpcIds.contains(npcId) || objectives.optionalTalkNpcIds.contains(npcId);
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
        !_isStepComplete(db, save, questId, step.notes ?? ''),
  );
}

bool questTouchesNpcForSave(GameDatabase db, PlayerSave save, QuestRow quest, String npcId) {
  if (quest['NPC ID'] == npcId) return true;

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
