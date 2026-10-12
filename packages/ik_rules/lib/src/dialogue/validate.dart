/// Content checks for dialogue graphs, dialogue quest steps and Reward Mode.
///
/// Kept apart from `validateDatabase` because that one runs inside
/// `prepareDatabase` and a failure there stops the game loading; these run in
/// the test suite against the real database so a typo fails CI, not players.
/// Ported from `src/game/dialogue/validate.ts`.
library;

import 'package:ik_content/ik_content.dart';

import '../quests/objectives.dart';
import '../quests/quests.dart';
import '../quests/steps.dart';
import 'engine.dart';

/// Columns that pay on completion; a `dialogue` quest must leave them blank.
const List<String> _questRewardColumns = <String>[
  'Reward XP Skill ID',
  'Reward XP Amount',
  'Reward Item ID',
  'Reward Item Quantity',
  'Possible Rewards',
];

const Map<String, String> _stepActionTypes = <String, String>{
  'talk_flag': 'Talk',
  'show_items': 'Show',
  'hand_in': 'HandIn',
};

final RegExp _positiveWhole = RegExp(r'^[1-9]\d*$');
final RegExp _giftFlag = RegExp(r'^gift:([A-Z]+-\d+)(?::.+)?$');

bool _isBlank(Object? value) => value == null || (value is String && value.trim().isEmpty);

bool _hasId(Iterable<Map<String, Object?>> rows, String field, String id) =>
    rows.any((row) => row[field] == id);

Iterable<Map<String, Object?>> _raws(Iterable<DbRow> rows) => rows.map((row) => row.raw);

ValidationIssue _issue(
  String table,
  String id,
  String message, [
  IssueSeverity severity = IssueSeverity.error,
]) => ValidationIssue(severity: severity, table: table, id: id, message: message);

String? _arg(DialogueToken token, int index) =>
    index < token.args.length ? token.args[index] : null;

/// Reference checks shared by conditions and actions.
String? _referenceProblem(GameDatabase db, DialogueToken token) {
  final a = _arg(token, 0) ?? '';
  final b = _arg(token, 1) ?? '';
  final quests = db.quests;
  switch (token.name) {
    case 'quest_active':
    case 'quest_done':
    case 'start_quest':
    case 'complete_quest':
      return _hasId(quests, 'Quest ID', a) ? null : 'Unknown quest $a in ${token.raw}';
    case 'quest_step':
    case 'step_ready':
    case 'talk_flag':
    case 'show_items':
    case 'hand_in':
      if (!_hasId(quests, 'Quest ID', a)) return 'Unknown quest $a in ${token.raw}';
      final step = getQuestStep(db, a, b);
      if (step == null) return 'Step $b is not part of $a in ${token.raw}';
      final wanted = _stepActionTypes[token.name];
      if (wanted != null && dialogueStepType(step) != wanted) {
        return '${token.name} needs a $wanted step but $b is not one';
      }
      return null;
    case 'dialogue_done':
      return _hasId(_raws(db.dialogues), 'Dialogue ID', a)
          ? null
          : 'Unknown dialogue $a in ${token.raw}';
    case 'has_item':
    case 'grant_item':
    case 'take_item':
      if (!_hasId(_raws(db.items), 'Item ID', a)) return 'Unknown item $a in ${token.raw}';
      if (token.args.length > 1 && !_positiveWhole.hasMatch(b)) {
        return 'Quantity must be a whole number ≥ 1 in ${token.raw}';
      }
      return null;
    case 'total_level':
      return _positiveWhole.hasMatch(a) ? null : 'Level must be a whole number ≥ 1 in ${token.raw}';
    case 'skill':
      if (!_hasId(_raws(db.skills), 'Skill ID', a)) return 'Unknown skill $a in ${token.raw}';
      return _positiveWhole.hasMatch(b) ? null : 'Level must be a whole number ≥ 1 in ${token.raw}';
    case 'has_book':
    case 'grant_book':
      return _hasId(_raws(db.books), 'Book ID', a) ? null : 'Unknown book $a in ${token.raw}';
  }
  return null;
}

List<DialogueToken> _checkConditions(
  GameDatabase db,
  String table,
  String id,
  Object? condition,
  List<ValidationIssue> issues,
) {
  final tokens = parseDialogueTokens(condition is String ? condition : null);
  for (final token in tokens) {
    if (!isKnownDialogueCondition(token)) {
      final known = dialogueConditionArity.containsKey(token.name);
      issues.add(
        _issue(
          table,
          id,
          known ? 'Malformed condition: ${token.raw}' : 'Unknown condition: ${token.raw}',
        ),
      );
      continue;
    }
    final problem = _referenceProblem(db, token);
    if (problem != null) issues.add(_issue(table, id, problem));
  }
  return tokens;
}

/// A grant on a non-Repeatable choice must be once-only: it completes a quest in
/// the same commit, or is gated by `!dialogue_done:`, or sets a `gift:` flag its
/// own (or its dialogue's) Condition rejects with `!flag:`.
void _checkOnceOnly(
  GameDatabase db,
  DialogueChoiceRow choice,
  List<DialogueToken> dialogueCondition,
  bool dialogueRepeatable,
  List<DialogueToken> conditions,
  List<DialogueToken> actions,
  List<ValidationIssue> issues,
) {
  final id = choice.choiceId;
  if (choice.raw['Repeatable'] == true) return;
  if (!actions.any((token) => token.name == 'grant_item' || token.name == 'grant_book')) return;
  if (actions.any((token) => token.name == 'complete_quest')) return;
  final gates = [...conditions, ...dialogueCondition].where(isKnownDialogueCondition).toList();
  if (gates.any((token) => token.negated && token.name == 'dialogue_done')) return;
  final blocked = {
    for (final token in gates)
      if (token.negated && token.name == 'flag') token.args.first,
  };
  final guards = actions
      .where(
        (token) =>
            token.name == 'set_flag' &&
            isKnownDialogueAction(token) &&
            blocked.contains(token.args.first),
      )
      .toList();
  if (guards.isEmpty) {
    issues.add(
      _issue(
        'DialogueChoices',
        id,
        'A once-only grant must set a gift flag that its Condition rejects (set_flag:gift:… with !flag:gift:…), '
            'be gated by !dialogue_done:, complete a quest, or mark the choice Repeatable',
        // One-time dialogues only record completion at the end, so a grant mid-way can repeat.
        dialogueRepeatable ? IssueSeverity.error : IssueSeverity.warning,
      ),
    );
    return;
  }
  for (final guard in guards) {
    final owner = _giftFlag.firstMatch(guard.args.first)?.group(1);
    final known =
        owner != null &&
        (_hasId(db.quests, 'Quest ID', owner) || _hasId(_raws(db.dialogues), 'Dialogue ID', owner));
    if (!known) {
      issues.add(
        _issue(
          'DialogueChoices',
          id,
          'Gift flag ${guard.args.first} must be gift:<quest or dialogue ID>[:key]',
        ),
      );
    }
  }
}

List<String> _questRewardsPaid(QuestRow quest) {
  final paid = <String>[
    for (final column in _questRewardColumns)
      if (!_isBlank(quest[column])) column,
  ];
  final parsed = parseStructuredObjectives(quest);
  if (parsed.rewardXp.isNotEmpty) paid.add('RewardXP');
  if (parsed.rewardGold > 0) paid.add('RewardGold');
  if (parsed.rewardItems.isNotEmpty) paid.add('RewardItem');
  if (parsed.rewardRecipeIds.isNotEmpty) paid.add('RewardRecipe');
  if (parsed.rewardProjectNpcIds.isNotEmpty) paid.add('RewardProjectNpc');
  if (parsed.rewardCosmeticIds.isNotEmpty) paid.add('RewardCosmetic');
  if (parsed.rewardBookIds.isNotEmpty) paid.add('RewardBook');
  if (parsed.branchSkillXp > 0) paid.add('BranchSkillXP');
  return paid;
}

List<ValidationIssue> validateDialogueContent(GameDatabase db) {
  final issues = <ValidationIssue>[];
  final npcs = _raws(db.npcs);

  for (final quest in asQuestRows(db)) {
    final id = quest['Quest ID'] is String ? quest['Quest ID']! as String : '';
    final raw = quest['Reward Mode'];
    if (!_isBlank(raw) &&
        !const <String>['legacy', 'dialogue'].contains('$raw'.trim().toLowerCase())) {
      issues.add(_issue('Quests', id, 'Unknown Reward Mode: $raw'));
    }
    if (questRewardMode(quest) == 'dialogue') {
      final paid = _questRewardsPaid(quest);
      if (paid.isNotEmpty) {
        issues.add(
          _issue(
            'Quests',
            id,
            'Reward Mode dialogue must not pay on completion (${paid.join(', ')})',
          ),
        );
      }
    }
  }

  for (final step in db.questSteps) {
    final id = step.stepId;
    final rawTypeCell = step.raw['Step Type'];
    final rawType = rawTypeCell is String ? rawTypeCell.trim() : '';
    final type = dialogueStepType(step);
    if (type == null &&
        dialogueStepTypes.any((name) => name.toLowerCase() == rawType.toLowerCase())) {
      issues.add(
        _issue(
          'QuestSteps',
          id,
          'Step Type must be spelled ${dialogueStepTypes.join(', ')}: $rawType',
        ),
      );
    }
    final npcId = step.raw['Step NPC'];
    if (!_isBlank(npcId) && !_hasId(npcs, 'NPC ID', '$npcId')) {
      issues.add(_issue('QuestSteps', id, 'Missing Step NPC reference: $npcId'));
    }
    final rawItems = step.raw['Step Items'];
    final entries = (rawItems is String ? rawItems : '')
        .split(';')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
    if (type == 'Talk' && entries.isNotEmpty) {
      issues.add(_issue('QuestSteps', id, 'A Talk step takes no Step Items'));
    }
    if (type == 'Show' || type == 'HandIn') {
      if (entries.isEmpty) issues.add(_issue('QuestSteps', id, 'A $type step needs Step Items'));
      final seen = <String>{};
      for (final entry in entries) {
        final parts = entry.split(':').map((part) => part.trim()).toList();
        if (parts.length != 2 || !_positiveWhole.hasMatch(parts[1])) {
          issues.add(
            _issue('QuestSteps', id, 'Step Items entry must be ITEM-x:n with n ≥ 1: $entry'),
          );
          continue;
        }
        if (!_hasId(_raws(db.items), 'Item ID', parts[0])) {
          issues.add(_issue('QuestSteps', id, 'Unknown item in Step Items: ${parts[0]}'));
        }
        if (!seen.add(parts[0])) {
          issues.add(_issue('QuestSteps', id, 'Item listed twice in Step Items: ${parts[0]}'));
        }
      }
    }
  }

  final dialogueConditions = <String, List<DialogueToken>>{};
  for (final dialogue in db.dialogues) {
    final id = dialogue.dialogueId;
    dialogueConditions[id] = _checkConditions(
      db,
      'Dialogues',
      id,
      dialogue.raw['Condition'],
      issues,
    );
    if (!_hasId(npcs, 'NPC ID', dialogue.npcId)) {
      issues.add(_issue('Dialogues', id, 'Missing NPC ID reference: ${dialogue.npcId}'));
    }
    final start = db.dialogueNodes.where((node) => node.nodeId == dialogue.startNodeId).firstOrNull;
    if (start == null || start.dialogueId != id) {
      issues.add(
        _issue(
          'Dialogues',
          id,
          'Start Node ID is not a node of this dialogue: ${dialogue.startNodeId}',
        ),
      );
    }
    final priority = dialogue.raw['Priority'];
    if (priority != null &&
        !(priority is num && priority.isFinite && priority == priority.truncate())) {
      issues.add(_issue('Dialogues', id, 'Priority must be a whole number'));
    }
  }

  for (final choice in db.dialogueChoices) {
    final id = choice.choiceId;
    final node = db.dialogueNodes.where((row) => row.nodeId == choice.nodeId).firstOrNull;
    if (node == null) {
      issues.add(_issue('DialogueChoices', id, 'Missing Node ID reference: ${choice.nodeId}'));
      continue;
    }
    final nextId = choice.nextNodeId;
    if (!_isBlank(nextId)) {
      final next = db.dialogueNodes.where((row) => row.nodeId == nextId).firstOrNull;
      if (next == null || next.dialogueId != node.dialogueId) {
        issues.add(
          _issue('DialogueChoices', id, 'Next Node ID is not a node of this dialogue: $nextId'),
        );
      }
    }
    final conditions = _checkConditions(db, 'DialogueChoices', id, choice.condition, issues);
    final actions = parseDialogueTokens(choice.action);
    for (final token in actions) {
      if (!isKnownDialogueAction(token)) {
        final known = dialogueActionArity.containsKey(token.name) && !token.negated;
        issues.add(
          _issue(
            'DialogueChoices',
            id,
            known ? 'Malformed action: ${token.raw}' : 'Unknown action: ${token.raw}',
          ),
        );
        continue;
      }
      final problem = _referenceProblem(db, token);
      if (problem != null) issues.add(_issue('DialogueChoices', id, problem));
    }
    final dialogue = db.dialogues.where((row) => row.dialogueId == node.dialogueId).firstOrNull;
    _checkOnceOnly(
      db,
      choice,
      dialogueConditions[node.dialogueId] ?? const <DialogueToken>[],
      dialogue?.repeatable == true,
      conditions,
      actions,
      issues,
    );
  }

  return issues;
}
