/// Standalone dialogue graphs (Dialogues / DialogueNodes / DialogueChoices).
///
/// Pure rules: no randomness. One-time completion is stored on the save.
/// QuestDialogue / NpcPanel stay untouched.
library;

import 'package:ik_content/ik_content.dart';

import '../inventory/add_items.dart';
import '../save/generated/save_models.dart';

class DialogueChoiceView {
  const DialogueChoiceView({required this.choiceId, required this.label});

  final String choiceId;
  final String label;

  Map<String, Object?> toJson() => <String, Object?>{'choiceId': choiceId, 'label': label};
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
  });

  final String dialogueId;
  final String nodeId;
  final String speakerName;
  final String npcId;
  final String line;
  final List<DialogueChoiceView> choices;
  final bool finished;

  Map<String, Object?> toJson() => <String, Object?>{
    'dialogueId': dialogueId,
    'nodeId': nodeId,
    'speakerName': speakerName,
    'npcId': npcId,
    'line': line,
    'choices': [for (final choice in choices) choice.toJson()],
    'finished': finished,
  };
}

class DialogueResult {
  const DialogueResult({
    required this.ok,
    required this.reason,
    required this.save,
    required this.view,
    required this.completed,
    required this.message,
  });

  final bool ok;
  final String reason;
  final PlayerSave save;
  final DialogueView? view;
  final bool completed;
  final String? message;

  Map<String, Object?> toJson() => <String, Object?>{
    'ok': ok,
    'reason': reason,
    'save': save.toJson(),
    'view': view?.toJson(),
    'completed': completed,
    'message': message,
  };
}

DialogueResult _failed(PlayerSave save, String reason) => DialogueResult(
  ok: false,
  reason: reason,
  save: save,
  view: null,
  completed: false,
  message: null,
);

DialogueRow? _dialogue(GameDatabase db, String dialogueId) {
  for (final row in db.dialogues) {
    if (row.dialogueId == dialogueId) return row;
  }
  return null;
}

DialogueNodeRow? _node(GameDatabase db, String nodeId) {
  for (final row in db.dialogueNodes) {
    if (row.nodeId == nodeId) return row;
  }
  return null;
}

List<DialogueChoiceRow> _choicesForNode(GameDatabase db, String nodeId) {
  final rows = [
    for (final row in db.dialogueChoices)
      if (row.nodeId == nodeId) row,
  ];
  rows.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return rows;
}

/// Whether a one-time dialogue is still available to start.
bool dialogueAvailable(GameDatabase db, PlayerSave save, String dialogueId) {
  final dialogue = _dialogue(db, dialogueId);
  if (dialogue == null) return false;
  if (dialogue.repeatable) return true;
  return !save.completedDialogueIds.contains(dialogueId);
}

/// Dialogues still available for an NPC.
List<String> dialoguesForNpc(GameDatabase db, PlayerSave save, String npcId) {
  return [
    for (final row in db.dialogues)
      if (row.npcId == npcId && dialogueAvailable(db, save, row.dialogueId)) row.dialogueId,
  ];
}

bool _conditionHolds(PlayerSave save, String? condition) {
  if (condition == null || condition.trim().isEmpty) return true;
  final trimmed = condition.trim();
  if (trimmed.startsWith('has_item:')) {
    final itemId = trimmed.substring('has_item:'.length);
    return save.inventory.any((stack) => stack.itemId == itemId && stack.quantity > 0);
  }
  return false;
}

({PlayerSave save, String? message, String? reason}) _applyAction(
  GameDatabase db,
  PlayerSave save,
  String? action,
) {
  if (action == null || action.trim().isEmpty) {
    return (save: save, message: null, reason: null);
  }
  final trimmed = action.trim();
  if (trimmed.startsWith('grant_item:')) {
    final parts = trimmed.split(':');
    final itemId = parts.length > 1 ? parts[1] : '';
    final qty = parts.length > 2 ? (num.tryParse(parts[2]) ?? 1).floor().clamp(1, 999999) : 1;
    if (itemId.isEmpty || db.items.every((row) => row.itemId != itemId)) {
      return (save: save, message: null, reason: 'That gift is missing from the database.');
    }
    final added = addItemsToInventory(save, itemId, qty, null, false, db);
    if (added.added <= 0) {
      return (save: save, message: null, reason: 'Your bag is full.');
    }
    String name = itemId;
    for (final row in db.items) {
      if (row.itemId == itemId) {
        name = row.displayName;
        break;
      }
    }
    return (
      save: added.save,
      message: added.added == 1 ? 'Received $name.' : 'Received ${added.added} $name.',
      reason: null,
    );
  }
  return (save: save, message: null, reason: 'Unknown dialogue action: $trimmed');
}

DialogueView? _viewFor(GameDatabase db, PlayerSave save, String dialogueId, String nodeId) {
  final dialogue = _dialogue(db, dialogueId);
  final node = _node(db, nodeId);
  if (dialogue == null || node == null || node.dialogueId != dialogueId) return null;
  final choices = [
    for (final row in _choicesForNode(db, nodeId))
      if (_conditionHolds(save, row.condition))
        DialogueChoiceView(choiceId: row.choiceId, label: row.label),
  ];
  return DialogueView(
    dialogueId: dialogueId,
    nodeId: nodeId,
    speakerName: dialogue.displayName,
    npcId: dialogue.npcId,
    line: node.line,
    choices: choices,
    finished: choices.isEmpty,
  );
}

PlayerSave _markCompleted(GameDatabase db, PlayerSave save, String dialogueId) {
  final dialogue = _dialogue(db, dialogueId);
  if (dialogue == null || dialogue.repeatable) return save;
  if (save.completedDialogueIds.contains(dialogueId)) return save;
  return save.copyWith(completedDialogueIds: [...save.completedDialogueIds, dialogueId]);
}

/// Opens a dialogue at its start node.
DialogueResult startDialogue(GameDatabase db, PlayerSave save, String dialogueId) {
  final dialogue = _dialogue(db, dialogueId);
  if (dialogue == null) return _failed(save, 'That conversation was not found.');
  if (!dialogueAvailable(db, save, dialogueId)) {
    return _failed(save, 'You have already finished that conversation.');
  }
  final view = _viewFor(db, save, dialogueId, dialogue.startNodeId);
  if (view == null) return _failed(save, 'That conversation has no opening line.');
  return DialogueResult(
    ok: true,
    reason: '',
    save: save,
    view: view,
    completed: false,
    message: null,
  );
}

/// Takes a choice on the current node.
DialogueResult chooseDialogue(
  GameDatabase db,
  PlayerSave save,
  String dialogueId,
  String nodeId,
  String choiceId,
) {
  final dialogue = _dialogue(db, dialogueId);
  if (dialogue == null) return _failed(save, 'That conversation was not found.');
  final node = _node(db, nodeId);
  if (node == null || node.dialogueId != dialogueId) {
    return _failed(save, 'That line is not part of this conversation.');
  }
  DialogueChoiceRow? choice;
  for (final row in _choicesForNode(db, nodeId)) {
    if (row.choiceId == choiceId) {
      choice = row;
      break;
    }
  }
  if (choice == null || !_conditionHolds(save, choice.condition)) {
    return _failed(save, 'That reply is not available.');
  }

  final applied = _applyAction(db, save, choice.action);
  if (applied.reason != null) return _failed(save, applied.reason!);
  var nextSave = applied.save;
  final nextNodeId = choice.nextNodeId;
  if (nextNodeId == null || nextNodeId.isEmpty) {
    nextSave = _markCompleted(db, nextSave, dialogueId);
    return DialogueResult(
      ok: true,
      reason: '',
      save: nextSave,
      view: null,
      completed: true,
      message: applied.message,
    );
  }
  final view = _viewFor(db, nextSave, dialogueId, nextNodeId);
  if (view == null) return _failed(save, 'That conversation leads nowhere.');
  return DialogueResult(
    ok: true,
    reason: '',
    save: nextSave,
    view: view,
    completed: false,
    message: applied.message,
  );
}
