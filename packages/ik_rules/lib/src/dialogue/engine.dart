/// Standalone dialogue graphs (Dialogues / DialogueNodes / DialogueChoices).
///
/// Pure rules: no randomness. Conditions and actions are `;`-separated tokens
/// (docs/specs/SYS-01-dialogue.md). Actions run in order on a working copy and
/// commit together: if any fails, the original save comes back untouched.
/// QuestDialogue / NpcPanel stay untouched. Ported from
/// `src/game/dialogue/engine.ts`.
library;

import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/xp.dart';
import '../inventory/add_items.dart';
import '../inventory/capacity.dart';
import '../inventory/gold.dart';
import '../js_compat.dart';
import '../library/books.dart';
import '../quests/quests.dart';
import '../quests/steps.dart';
import '../save/generated/save_models.dart';
import '../skills/totals.dart';
import 'step_progress.dart';

class DialogueToken {
  const DialogueToken({
    required this.raw,
    required this.negated,
    required this.name,
    required this.args,
  });

  final String raw;
  final bool negated;
  final String name;
  final List<String> args;
}

/// Accepted arity per token; the flag tokens keep everything after the first `:` as one key.
const Map<String, (int, int)> dialogueConditionArity = <String, (int, int)>{
  'quest_active': (1, 1),
  'quest_step': (2, 2),
  'quest_done': (1, 1),
  'dialogue_done': (1, 1),
  'has_item': (1, 2),
  'total_level': (1, 1),
  'skill': (2, 2),
  'flag': (1, 1),
  'step_ready': (2, 2),
  'has_book': (1, 1),
};

const Map<String, (int, int)> dialogueActionArity = <String, (int, int)>{
  'grant_item': (1, 2),
  'take_item': (1, 2),
  'start_quest': (1, 1),
  'talk_flag': (2, 2),
  'show_items': (2, 2),
  'hand_in': (2, 2),
  'complete_quest': (1, 1),
  'grant_book': (1, 1),
  'set_flag': (1, 1),
  'clear_flag': (1, 1),
};

const Set<String> _keyTokens = <String>{'flag', 'set_flag', 'clear_flag'};
const Set<String> _questActions = <String>{
  'start_quest',
  'talk_flag',
  'show_items',
  'hand_in',
  'complete_quest',
};

List<DialogueToken> parseDialogueTokens(String? value) {
  if (value == null) return const <DialogueToken>[];
  final tokens = <DialogueToken>[];
  for (final part in value.split(';')) {
    final raw = part.trim();
    if (raw.isEmpty) continue;
    final negated = raw.startsWith('!');
    final body = (negated ? raw.substring(1) : raw).trim();
    final colon = body.indexOf(':');
    final name = (colon < 0 ? body : body.substring(0, colon)).trim();
    final rest = colon < 0 ? '' : body.substring(colon + 1);
    final args = colon < 0
        ? const <String>[]
        : _keyTokens.contains(name)
        ? <String>[rest.trim()]
        : rest.split(':').map((arg) => arg.trim()).toList();
    tokens.add(DialogueToken(raw: raw, negated: negated, name: name, args: args));
  }
  return tokens;
}

bool _arityOk(DialogueToken token, Map<String, (int, int)> table) {
  final arity = table[token.name];
  if (arity == null) return false;
  if (token.args.length < arity.$1 || token.args.length > arity.$2) return false;
  return token.args.every((arg) => arg.isNotEmpty);
}

final RegExp _wholeCount = RegExp(r'^\d+$');

/// Whole count of at least 1, defaulting when the argument is absent.
int? _parseCount(String? raw, [int fallback = 1]) {
  if (raw == null) return fallback;
  if (!_wholeCount.hasMatch(raw)) return null;
  final value = int.parse(raw);
  return value >= 1 ? value : null;
}

String? _arg(DialogueToken token, int index) =>
    index < token.args.length ? token.args[index] : null;

bool isKnownDialogueCondition(DialogueToken token) => _arityOk(token, dialogueConditionArity);

bool isKnownDialogueAction(DialogueToken token) =>
    !token.negated && _arityOk(token, dialogueActionArity);

String _itemName(GameDatabase db, String itemId) =>
    db.items.firstWhereOrNull((row) => row.itemId == itemId)?.displayName ?? itemId;

String _questName(GameDatabase db, String questId) {
  final name = getQuest(db, questId)?['Display Name'];
  return name is String ? name : questId;
}

String _skillName(GameDatabase db, String skillId) {
  final name = db.skills
      .firstWhereOrNull((row) => row.raw['Skill ID'] == skillId)
      ?.raw['Display Name'];
  return name is String ? name : skillId;
}

String _bookName(GameDatabase db, String bookId) => bookById(db, bookId)?.displayName ?? bookId;

String _countLabel(num count, String name) =>
    count == 1 ? name : '${jsNumberToString(count)} $name';

bool _hasFlag(PlayerSave save, String key) => save.dialogueFlags.contains(key);

PlayerSave _withFlag(PlayerSave save, String key, bool on) {
  final current = save.dialogueFlags;
  if (current.contains(key) == on) return save;
  final next = on ? [...current, key] : current.where((flag) => flag != key).toList();
  return save.copyWith(dialogueFlags: next..sort());
}

bool _isCurrentStep(GameDatabase db, PlayerSave save, String questId, String stepId) {
  final quest = getQuest(db, questId);
  if (quest == null || getQuestProgress(save, questId).status != 'active') return false;
  return getCurrentStepId(db, save, quest) == stepId;
}

num _handInRemaining(PlayerSave save, String questId, String stepId, String itemId, num need) {
  final kept = getQuestProgress(save, questId).counters?[handInCounterKey(stepId, itemId)] ?? 0;
  return math.max(0, need - kept);
}

/// First player-facing reason a Show/HandIn step cannot be done now, or null.
String? _stepNotReadyReason(GameDatabase db, PlayerSave save, String questId, String stepId) {
  if (!_isCurrentStep(db, save, questId, stepId)) {
    return 'Needs the right step of ${_questName(db, questId)}';
  }
  final step = getQuestStep(db, questId, stepId);
  final type = dialogueStepType(step);
  final needs = parseStepItems(step?.raw['Step Items']);
  if (type == 'Show') {
    for (final need in needs) {
      final have = bagCount(save, need.itemId);
      if (have < need.quantity) {
        return 'Needs ${_countLabel(need.quantity, _itemName(db, need.itemId))} (you have ${jsNumberToString(have)})';
      }
    }
    return null;
  }
  if (type == 'HandIn') {
    final wanted = needs
        .where((need) => _handInRemaining(save, questId, stepId, need.itemId, need.quantity) > 0)
        .toList();
    if (wanted.any((need) => bagCount(save, need.itemId) > 0)) return null;
    return 'Bring ${wanted.map((need) => _itemName(db, need.itemId)).join(' or ')}';
  }
  return null;
}

/// True/false for a well-formed token, null for an unknown or malformed one.
bool? _positiveHolds(GameDatabase db, PlayerSave save, DialogueToken token) {
  if (!isKnownDialogueCondition(token)) return null;
  final a = _arg(token, 0) ?? '';
  final b = _arg(token, 1);
  switch (token.name) {
    case 'quest_active':
      return getQuestProgress(save, a).status == 'active';
    case 'quest_done':
      return getQuestProgress(save, a).status == 'completed';
    case 'quest_step':
      return _isCurrentStep(db, save, a, b ?? '');
    case 'dialogue_done':
      return save.completedDialogueIds.contains(a);
    case 'has_item':
      final need = _parseCount(b);
      return need == null ? null : bagCount(save, a) >= need;
    case 'total_level':
      final need = _parseCount(a);
      return need == null ? null : totalLevel(save) >= need;
    case 'skill':
      final need = _parseCount(b);
      return need == null ? null : getSkillProgress(save, a).level >= need;
    case 'flag':
      return _hasFlag(save, a);
    case 'step_ready':
      return _stepNotReadyReason(db, save, a, b ?? '') == null;
    case 'has_book':
      return isBookUnlocked(save, a);
  }
  return null;
}

String _failedReason(GameDatabase db, PlayerSave save, DialogueToken token) {
  final a = _arg(token, 0) ?? '';
  final b = _arg(token, 1) ?? '';
  if (token.negated) {
    return switch (token.name) {
      'quest_active' => 'Not while ${_questName(db, a)} is in progress',
      'quest_done' => 'Already completed ${_questName(db, a)}',
      'quest_step' => 'Not at this step of ${_questName(db, a)}',
      'dialogue_done' => 'Already talked about this',
      'has_item' => 'Not while carrying ${_itemName(db, a)}',
      'total_level' => 'Only below total level $a',
      'skill' => 'Only below ${_skillName(db, a)} $b',
      'flag' => 'Already done',
      'step_ready' => 'Already ready',
      'has_book' => 'Already have ${_bookName(db, a)}',
      _ => 'Not available',
    };
  }
  return switch (token.name) {
    'quest_active' => 'Needs ${_questName(db, a)} in progress',
    'quest_done' => 'Needs ${_questName(db, a)} completed',
    'quest_step' => 'Needs the right step of ${_questName(db, a)}',
    'dialogue_done' => 'Needs an earlier conversation',
    'has_item' => 'Needs ${_countLabel(_parseCount(_arg(token, 1)) ?? 1, _itemName(db, a))}',
    'total_level' => 'Needs total level $a',
    'skill' => 'Needs ${_skillName(db, a)} $b',
    'flag' => 'Not available yet',
    'step_ready' => _stepNotReadyReason(db, save, a, b) ?? 'Not available',
    'has_book' => 'Needs ${_bookName(db, a)}',
    _ => 'Not available',
  };
}

class DialogueConditionCheck {
  const DialogueConditionCheck({required this.holds, this.reason});

  final bool holds;

  /// Player-facing reason when the condition fails.
  final String? reason;

  Map<String, Object?> toJson() => <String, Object?>{'holds': holds, 'reason': reason};
}

/// One condition token. Unknown tokens never hold, negated or not.
DialogueConditionCheck checkDialogueCondition(
  GameDatabase db,
  PlayerSave save,
  DialogueToken token,
) {
  final positive = _positiveHolds(db, save, token);
  if (positive == null) return const DialogueConditionCheck(holds: false, reason: 'Not available');
  final holds = token.negated ? !positive : positive;
  return holds
      ? const DialogueConditionCheck(holds: true)
      : DialogueConditionCheck(holds: false, reason: _failedReason(db, save, token));
}

/// All tokens of a Condition cell (AND); the first failure's reason.
DialogueConditionCheck checkDialogueConditions(
  GameDatabase db,
  PlayerSave save,
  String? condition,
) {
  for (final token in parseDialogueTokens(condition)) {
    final check = checkDialogueCondition(db, save, token);
    if (!check.holds) return check;
  }
  return const DialogueConditionCheck(holds: true);
}

class DialogueChoiceView {
  const DialogueChoiceView({
    required this.choiceId,
    required this.label,
    this.enabled = true,
    this.reason,
    this.hidden = false,
    this.questMarked = false,
  });

  final String choiceId;
  final String label;
  final bool enabled;

  /// First failed condition, worded for players; null when enabled.
  final String? reason;
  final bool hidden;

  /// Starts, advances or completes a quest (or the row sets QuestMarker).
  final bool questMarked;

  Map<String, Object?> toJson() => <String, Object?>{
    'choiceId': choiceId,
    'label': label,
    'enabled': enabled,
    'reason': reason,
    'hidden': hidden,
    'questMarked': questMarked,
  };
}

class DialogueView {
  const DialogueView({
    required this.dialogueId,
    required this.nodeId,
    required this.speakerName,
    required this.npcId,
    required this.line,
    required this.choices,
    required this.finished,
    this.stepProgress = const <StepProgressGroup>[],
  });

  final String dialogueId;
  final String nodeId;
  final String speakerName;
  final String npcId;
  final String line;
  final List<DialogueChoiceView> choices;

  /// Show / HandIn steps the listed choices check or act on.
  final List<StepProgressGroup> stepProgress;
  final bool finished;

  Map<String, Object?> toJson() => <String, Object?>{
    'dialogueId': dialogueId,
    'nodeId': nodeId,
    'speakerName': speakerName,
    'npcId': npcId,
    'line': line,
    'choices': [for (final choice in choices) choice.toJson()],
    'stepProgress': [for (final group in stepProgress) group.toJson()],
    'finished': finished,
  };
}

class DialogueItemDelta {
  const DialogueItemDelta({required this.itemId, required this.qty});

  final String itemId;

  /// Positive when granted, negative when taken or handed in.
  final num qty;

  Map<String, Object?> toJson() => <String, Object?>{'itemId': itemId, 'qty': qty};
}

class DialogueNoRoom {
  const DialogueNoRoom({required this.slotsNeeded, required this.slotsFree});

  /// New bag slots the remaining grants need; stacks already in the bag cost none.
  final int slotsNeeded;
  final int slotsFree;

  Map<String, Object?> toJson() => <String, Object?>{
    'slotsNeeded': slotsNeeded,
    'slotsFree': slotsFree,
  };
}

class DialogueMissingItem {
  const DialogueMissingItem({required this.itemId, required this.have, required this.need});

  final String itemId;
  final num have;
  final num need;

  Map<String, Object?> toJson() => <String, Object?>{'itemId': itemId, 'have': have, 'need': need};
}

class DialogueResult {
  const DialogueResult({
    required this.ok,
    required this.reason,
    required this.save,
    required this.view,
    required this.completed,
    required this.message,
    this.code,
    this.itemDeltas = const <DialogueItemDelta>[],
    this.bookDeltas = const <String>[],
    this.stepProgress = const <StepProgressGroup>[],
    this.noRoom,
    this.missing = const <DialogueMissingItem>[],
  });

  final bool ok;
  final String reason;

  /// Machine-readable failure (`no_room`, `missing_items`, `nothing_to_hand_in`,
  /// `not_available`, `not_found`, `invalid`, `action_failed`), null on success.
  final String? code;
  final PlayerSave save;
  final DialogueView? view;

  /// True when the conversation ended on this step.
  final bool completed;
  final String? message;
  final List<DialogueItemDelta> itemDeltas;

  /// Books newly added to the Library.
  final List<String> bookDeltas;

  /// Show / HandIn progress touched by this choice (after it applied, or as it stood when it failed).
  final List<StepProgressGroup> stepProgress;
  final DialogueNoRoom? noRoom;
  final List<DialogueMissingItem> missing;

  Map<String, Object?> toJson() => <String, Object?>{
    'ok': ok,
    'reason': reason,
    'code': code,
    'save': save.toJson(),
    'view': view?.toJson(),
    'completed': completed,
    'message': message,
    'itemDeltas': [for (final delta in itemDeltas) delta.toJson()],
    'bookDeltas': bookDeltas,
    'stepProgress': [for (final group in stepProgress) group.toJson()],
    'noRoom': noRoom?.toJson(),
    'missing': [for (final line in missing) line.toJson()],
  };
}

class _ActionFailure {
  const _ActionFailure(
    this.code,
    this.reason, {
    this.noRoom,
    this.missing = const <DialogueMissingItem>[],
    this.stepProgress = const <StepProgressGroup>[],
  });

  final String code;
  final String reason;
  final DialogueNoRoom? noRoom;
  final List<DialogueMissingItem> missing;
  final List<StepProgressGroup> stepProgress;
}

DialogueResult _failed(PlayerSave save, String code, String reason, [_ActionFailure? extra]) {
  return DialogueResult(
    ok: false,
    reason: reason,
    code: code,
    save: save,
    view: null,
    completed: false,
    message: null,
    stepProgress: extra?.stepProgress ?? const <StepProgressGroup>[],
    noRoom: extra?.noRoom,
    missing: extra?.missing ?? const <DialogueMissingItem>[],
  );
}

DialogueRow? _dialogue(GameDatabase db, String dialogueId) =>
    db.dialogues.firstWhereOrNull((row) => row.dialogueId == dialogueId);

DialogueNodeRow? _node(GameDatabase db, String nodeId) =>
    db.dialogueNodes.firstWhereOrNull((row) => row.nodeId == nodeId);

List<DialogueChoiceRow> _choicesForNode(GameDatabase db, String nodeId) {
  final rows = [
    for (final row in db.dialogueChoices)
      if (row.nodeId == nodeId) row,
  ];
  rows.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return rows;
}

num _priorityOf(DialogueRow row) {
  final raw = row.raw['Priority'];
  return raw is num && raw.isFinite ? raw : 0;
}

String? _dialogueCondition(DialogueRow row) {
  final raw = row.raw['Condition'];
  return raw is String ? raw : null;
}

/// Whether a dialogue can be opened now: one-time state and its Condition.
bool dialogueAvailable(GameDatabase db, PlayerSave save, String dialogueId) {
  final dialogue = _dialogue(db, dialogueId);
  if (dialogue == null) return false;
  if (!dialogue.repeatable && save.completedDialogueIds.contains(dialogueId)) return false;
  return checkDialogueConditions(db, save, _dialogueCondition(dialogue)).holds;
}

/// Available dialogues for an NPC, highest Priority first, then by Dialogue ID.
List<String> dialoguesForNpc(GameDatabase db, PlayerSave save, String npcId) {
  final rows = [
    for (final row in db.dialogues)
      if (row.npcId == npcId && dialogueAvailable(db, save, row.dialogueId)) row,
  ];
  rows.sort((a, b) {
    final byPriority = _priorityOf(b).compareTo(_priorityOf(a));
    if (byPriority != 0) return byPriority;
    return a.dialogueId.compareTo(b.dialogueId);
  });
  return [for (final row in rows) row.dialogueId];
}

bool _flagCell(DbRow row, String column) => row.raw[column] == true;

/// Show / HandIn steps a choice row checks (`step_ready`) or acts on.
List<(String, String)> _referencedSteps(DialogueChoiceRow row) {
  final refs = <(String, String)>[];
  for (final token in parseDialogueTokens(row.condition)) {
    if (token.name == 'step_ready' && token.args.length == 2) {
      refs.add((token.args[0], token.args[1]));
    }
  }
  for (final token in parseDialogueTokens(row.action)) {
    if ((token.name == 'show_items' || token.name == 'hand_in') && token.args.length == 2) {
      refs.add((token.args[0], token.args[1]));
    }
  }
  return refs;
}

List<StepProgressGroup> _progressFor(
  GameDatabase db,
  PlayerSave save,
  Iterable<(String, String)> refs,
) {
  final groups = <StepProgressGroup>[];
  final seen = <(String, String)>{};
  for (final ref in refs) {
    if (!seen.add(ref)) continue;
    final group = stepProgressGroup(db, save, ref.$1, ref.$2);
    if (group != null) groups.add(group);
  }
  return groups;
}

DialogueChoiceView? _choiceView(GameDatabase db, PlayerSave save, DialogueChoiceRow row) {
  final check = checkDialogueConditions(db, save, row.condition);
  final hidden = _flagCell(row, 'Hidden');
  if (!check.holds && hidden) return null;
  return DialogueChoiceView(
    choiceId: row.choiceId,
    label: row.label,
    enabled: check.holds,
    reason: check.reason,
    hidden: hidden,
    questMarked:
        _flagCell(row, 'QuestMarker') ||
        parseDialogueTokens(row.action).any((token) => _questActions.contains(token.name)),
  );
}

DialogueView? _viewFor(GameDatabase db, PlayerSave save, String dialogueId, String nodeId) {
  final dialogue = _dialogue(db, dialogueId);
  final node = _node(db, nodeId);
  if (dialogue == null || node == null || node.dialogueId != dialogueId) return null;
  final rows = <DialogueChoiceRow>[];
  final choices = <DialogueChoiceView>[];
  for (final row in _choicesForNode(db, nodeId)) {
    final view = _choiceView(db, save, row);
    if (view == null) continue;
    rows.add(row);
    choices.add(view);
  }
  return DialogueView(
    dialogueId: dialogueId,
    nodeId: nodeId,
    speakerName: dialogue.displayName,
    npcId: dialogue.npcId,
    line: node.line,
    choices: choices,
    stepProgress: _progressFor(db, save, rows.expand(_referencedSteps)),
    finished: choices.isEmpty,
  );
}

/// Read-only view of a node for a save (the `dialogue_view` command).
DialogueView? viewDialogueNode(
  GameDatabase db,
  PlayerSave save,
  String dialogueId,
  String nodeId,
) => _viewFor(db, save, dialogueId, nodeId);

PlayerSave _markCompleted(GameDatabase db, PlayerSave save, String dialogueId) {
  final dialogue = _dialogue(db, dialogueId);
  if (dialogue == null || dialogue.repeatable) return save;
  if (save.completedDialogueIds.contains(dialogueId)) return save;
  return save.copyWith(completedDialogueIds: [...save.completedDialogueIds, dialogueId]);
}

/// Opens a dialogue at its start node.
DialogueResult startDialogue(GameDatabase db, PlayerSave save, String dialogueId) {
  final dialogue = _dialogue(db, dialogueId);
  if (dialogue == null) return _failed(save, 'not_found', 'That conversation was not found.');
  if (!dialogue.repeatable && save.completedDialogueIds.contains(dialogueId)) {
    return _failed(save, 'not_available', 'You have already finished that conversation.');
  }
  final gate = checkDialogueConditions(db, save, _dialogueCondition(dialogue));
  if (!gate.holds) return _failed(save, 'not_available', gate.reason ?? 'Not available');
  final view = _viewFor(db, save, dialogueId, dialogue.startNodeId);
  if (view == null) return _failed(save, 'invalid', 'That conversation has no opening line.');
  return DialogueResult(
    ok: true,
    reason: '',
    save: save,
    view: view,
    completed: false,
    message: null,
  );
}

class _Working {
  _Working(this.original) : save = original;

  /// The save the choice started from; no-room counts are reported against it.
  final PlayerSave original;
  PlayerSave save;
  final List<String> messages = <String>[];
  final List<DialogueItemDelta> itemDeltas = <DialogueItemDelta>[];
  final List<String> bookDeltas = <String>[];
  final List<StepProgressGroup> stepProgress = <StepProgressGroup>[];
}

/// New bag slots every grant in [tokens] needs against [save].
int _slotsNeededForGrants(GameDatabase db, PlayerSave save, List<DialogueToken> tokens) {
  final seen = <String>{};
  var needed = 0;
  for (final token in tokens) {
    if (token.name != 'grant_item' || !isKnownDialogueAction(token)) continue;
    final itemId = token.args[0];
    if (isGoldCurrencyItem(itemId, db) || !seen.add(itemId)) continue;
    if (mergeableStackIndex(save.inventory, itemId) >= 0) continue;
    needed += 1;
  }
  return needed;
}

/// Checks the quest is active, the step belongs to it with [type], and is current.
_ActionFailure? _guardStep(
  GameDatabase db,
  PlayerSave save,
  String questId,
  String stepId,
  String type,
) {
  final step = getQuestStep(db, questId, stepId);
  if (getQuest(db, questId) == null || step == null || dialogueStepType(step) != type) {
    return const _ActionFailure('invalid', 'That quest step cannot be done here.');
  }
  if (getQuestProgress(save, questId).status != 'active') {
    return const _ActionFailure('action_failed', 'That quest is not active.');
  }
  if (!_isCurrentStep(db, save, questId, stepId)) {
    return const _ActionFailure('action_failed', 'That step is not current.');
  }
  return null;
}

PlayerSave _latchAndUnlock(GameDatabase db, PlayerSave save, String questId, String stepId) {
  return applyQuestStepUnlocks(db, latchStep(save, questId, stepId));
}

/// Unenchanted bag counts that changed, sorted by item ID.
List<DialogueItemDelta> _bagDiff(PlayerSave before, PlayerSave after) {
  final ids = <String>{
    for (final stack in [...before.inventory, ...after.inventory])
      if (isBlank(stack.enchantmentId)) stack.itemId,
  }.toList()..sort();
  return [
    for (final itemId in ids)
      if (bagCount(after, itemId) - bagCount(before, itemId) != 0)
        DialogueItemDelta(itemId: itemId, qty: bagCount(after, itemId) - bagCount(before, itemId)),
  ];
}

_ActionFailure? _applyAction(
  GameDatabase db,
  _Working work,
  List<DialogueToken> tokens,
  int index,
) {
  final token = tokens[index];
  if (!isKnownDialogueAction(token)) {
    return _ActionFailure('invalid', 'Unknown dialogue action: ${token.raw}');
  }
  final save = work.save;
  final a = _arg(token, 0) ?? '';
  final b = _arg(token, 1) ?? '';
  switch (token.name) {
    case 'grant_item':
      final qty = _parseCount(_arg(token, 1));
      if (qty == null || db.items.every((row) => row.itemId != a)) {
        return const _ActionFailure('invalid', 'That gift is missing from the database.');
      }
      final added = addItemsToInventory(save, a, qty, null, false, db);
      if (added.added < qty) {
        final slotsNeeded = math.max(1, _slotsNeededForGrants(db, work.original, tokens));
        final slotsFree = inventorySlotsFree(work.original);
        final short = math.max(1, slotsNeeded - slotsFree);
        return _ActionFailure(
          'no_room',
          'No room in your bag. Free $short slot${short == 1 ? '' : 's'} and try again.',
          noRoom: DialogueNoRoom(slotsNeeded: slotsNeeded, slotsFree: slotsFree),
        );
      }
      work.save = added.save;
      work.itemDeltas.add(DialogueItemDelta(itemId: a, qty: qty));
      final name = _itemName(db, a);
      work.messages.add(qty == 1 ? 'Received $name.' : 'Received $qty $name.');
      return null;
    case 'take_item':
      final qty = _parseCount(_arg(token, 1));
      if (qty == null) return _ActionFailure('invalid', 'Unknown dialogue action: ${token.raw}');
      final taken = takeFromBag(save, a, qty);
      if (taken == null) {
        return _ActionFailure(
          'missing_items',
          'Needs ${_countLabel(qty, _itemName(db, a))}',
          missing: [DialogueMissingItem(itemId: a, have: bagCount(save, a), need: qty)],
        );
      }
      work.save = taken;
      work.itemDeltas.add(DialogueItemDelta(itemId: a, qty: -qty));
      return null;
    case 'start_quest':
      final accepted = acceptQuest(db, save, a);
      if (!accepted.ok) return _ActionFailure('action_failed', accepted.reason!);
      work.save = accepted.save!;
      work.messages.add('Quest started: ${_questName(db, a)}.');
      return null;
    case 'talk_flag':
      final guard = _guardStep(db, save, a, b, 'Talk');
      if (guard != null) return guard;
      work.save = _latchAndUnlock(db, save, a, b);
      return null;
    case 'show_items':
      final guard = _guardStep(db, save, a, b, 'Show');
      if (guard != null) return guard;
      final needs = parseStepItems(getQuestStep(db, a, b)?.raw['Step Items']);
      final missing = [
        for (final need in needs)
          if (bagCount(save, need.itemId) < need.quantity)
            DialogueMissingItem(
              itemId: need.itemId,
              have: bagCount(save, need.itemId),
              need: need.quantity,
            ),
      ];
      if (missing.isNotEmpty) {
        final first = missing.first;
        return _ActionFailure(
          'missing_items',
          'Needs ${_countLabel(first.need, _itemName(db, first.itemId))} (you have ${jsNumberToString(first.have)})',
          missing: missing,
          stepProgress: _progressFor(db, save, [(a, b)]),
        );
      }
      work.save = _latchAndUnlock(db, save, a, b);
      work.stepProgress.addAll(_progressFor(db, work.save, [(a, b)]));
      return null;
    case 'hand_in':
      final guard = _guardStep(db, save, a, b, 'HandIn');
      if (guard != null) return guard;
      final needs = parseStepItems(getQuestStep(db, a, b)?.raw['Step Items']);
      var next = save;
      final counters = <String, num>{...?getQuestProgress(save, a).counters};
      num moved = 0;
      var complete = true;
      final parts = <String>[];
      for (final need in needs) {
        final key = handInCounterKey(b, need.itemId);
        final kept = counters[key] ?? 0;
        final move = math.min(bagCount(next, need.itemId), math.max(0, need.quantity - kept));
        if (move > 0) {
          next = takeFromBag(next, need.itemId, move)!;
          counters[key] = kept + move;
          moved += move;
          work.itemDeltas.add(DialogueItemDelta(itemId: need.itemId, qty: -move));
          parts.add(_countLabel(move, _itemName(db, need.itemId)));
        }
        if (kept + move < need.quantity) complete = false;
      }
      if (moved == 0) {
        return _ActionFailure(
          'nothing_to_hand_in',
          'You have nothing they still need.',
          stepProgress: _progressFor(db, save, [(a, b)]),
        );
      }
      next = withQuestCounters(next, a, counters);
      if (complete) next = _latchAndUnlock(db, next, a, b);
      work.save = next;
      work.messages.add('Handed over ${parts.join(' and ')}.');
      work.stepProgress.addAll(_progressFor(db, next, [(a, b)]));
      return null;
    case 'complete_quest':
      final completed = completeQuest(db, save, a);
      if (!completed.ok) return _ActionFailure('action_failed', completed.reason!);
      work.itemDeltas.addAll(_bagDiff(save, completed.save!));
      work.bookDeltas.addAll(completed.booksGranted.map((grant) => grant.bookId));
      work.save = completed.save!;
      work.messages.add(completed.message!);
      return null;
    case 'grant_book':
      final book = bookById(db, a);
      if (book == null) {
        return const _ActionFailure('invalid', 'That book is missing from the database.');
      }
      final granted = grantBook(save, a);
      if (granted.granted) {
        work.save = granted.save;
        work.bookDeltas.add(a);
        work.messages.add('Added ${book.displayName} to your Library.');
      }
      return null;
    case 'set_flag':
      work.save = _withFlag(save, a, true);
      return null;
    case 'clear_flag':
      work.save = _withFlag(save, a, false);
      return null;
  }
  return _ActionFailure('invalid', 'Unknown dialogue action: ${token.raw}');
}

/// Takes a choice on the current node.
///
/// The client sends the node it is looking at; the server re-checks that the
/// choice belongs to that node and that its conditions hold on the server save.
DialogueResult chooseDialogue(
  GameDatabase db,
  PlayerSave save,
  String dialogueId,
  String nodeId,
  String choiceId,
) {
  final dialogue = _dialogue(db, dialogueId);
  if (dialogue == null) return _failed(save, 'not_found', 'That conversation was not found.');
  // Mid-conversation choices stay allowed even after one-time completion was
  // recorded by a parallel tab; only starting is gated. Ending still marks once.
  final node = _node(db, nodeId);
  if (node == null || node.dialogueId != dialogueId) {
    return _failed(save, 'invalid', 'That line is not part of this conversation.');
  }
  final choice = _choicesForNode(db, nodeId).firstWhereOrNull((row) => row.choiceId == choiceId);
  if (choice == null) return _failed(save, 'not_available', 'That reply is not available.');
  final gate = checkDialogueConditions(db, save, choice.condition);
  if (!gate.holds) {
    return _failed(save, 'not_available', gate.reason ?? 'That reply is not available.');
  }

  final tokens = parseDialogueTokens(choice.action);
  final work = _Working(save);
  for (var index = 0; index < tokens.length; index++) {
    final failure = _applyAction(db, work, tokens, index);
    if (failure != null) return _failed(save, failure.code, failure.reason, failure);
  }

  var nextSave = work.save;
  final message = work.messages.isNotEmpty ? work.messages.join(' ') : null;
  final nextNodeId = choice.nextNodeId;
  if (nextNodeId == null || nextNodeId.isEmpty) {
    nextSave = _markCompleted(db, nextSave, dialogueId);
    return DialogueResult(
      ok: true,
      reason: '',
      save: nextSave,
      view: null,
      completed: true,
      message: message,
      itemDeltas: work.itemDeltas,
      bookDeltas: work.bookDeltas,
      stepProgress: work.stepProgress,
    );
  }
  final view = _viewFor(db, nextSave, dialogueId, nextNodeId);
  if (view == null) return _failed(save, 'invalid', 'That conversation leads nowhere.');
  return DialogueResult(
    ok: true,
    reason: '',
    save: nextSave,
    view: view,
    completed: false,
    message: message,
    itemDeltas: work.itemDeltas,
    bookDeltas: work.bookDeltas,
    stepProgress: work.stepProgress,
  );
}
