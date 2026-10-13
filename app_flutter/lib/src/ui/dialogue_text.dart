import 'dart:math' as math;

import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

/// Every player-facing string on the dialogue screen.
///
/// Built from the engine's result codes and counts, never from its `reason` or
/// `message`, which are placeholders. Counts are the bag only.
class DialogueText {
  const DialogueText(this.db);

  final GameDatabase db;

  static const String favouritesPrompt =
      'Some items are favourited. Do you still want to use them?';

  static String bagFull(int slotsNeeded) {
    final n = math.max(1, slotsNeeded);
    return 'Your bag is full. Make room for $n more item${n == 1 ? '' : 's'} and try again.';
  }

  String itemName(String itemId) =>
      _first(db.items, (row) => row.itemId == itemId)?.displayName ?? 'Unknown item';

  String _questName(String questId) {
    final name = getQuest(db, questId)?['Display Name'];
    return name is String ? name : 'a quest';
  }

  String _bookName(String bookId) => bookById(db, bookId)?.displayName ?? 'a book';

  /// "Baked Potato 6/10 handed in", "Baked Potato: you have 3/5", "Baked Potato: Shown ✓".
  String progressLine(StepProgressGroup group, StepProgressLine line) {
    final name = itemName(line.itemId);
    if (line.mode == 'handIn') {
      return '$name ${_count(line.handedIn)}/${_count(line.need)} handed in';
    }
    if (group.done) return '$name: Shown ✓';
    return '$name: you have ${_count(line.have)}/${_count(line.need)}';
  }

  /// Label for a choice that shows or hands in a step's items; null keeps the content label.
  String? choiceLabel(DialogueChoiceView choice, List<StepProgressGroup> groups) {
    final row = _first(db.dialogueChoices, (row) => row.choiceId == choice.choiceId);
    if (row == null) return null;
    for (final token in parseDialogueTokens(row.action)) {
      if (token.negated || token.args.length != 2) continue;
      if (token.name != 'show_items' && token.name != 'hand_in') continue;
      final group = _first(
        groups,
        (group) => group.questId == token.args[0] && group.stepId == token.args[1],
      );
      if (group == null) return null;
      return token.name == 'show_items' ? _showLabel(group) : _handInLabel(group);
    }
    return null;
  }

  String _showLabel(StepProgressGroup group) {
    if (group.done) return 'Shown ✓';
    return 'Show ${_amounts(group.items, (line) => line.need)}';
  }

  String _handInLabel(StepProgressGroup group) {
    if (group.done) return 'Handed in ✓';
    final movable = group.items.where((line) => _movable(line) > 0).toList();
    if (movable.isNotEmpty) return 'Hand in ${_amounts(movable, _movable)}';
    final wanted = group.items.where((line) => _remaining(line) > 0);
    final parts = [
      for (final line in wanted)
        '${itemName(line.itemId)} (${_count(line.handedIn)}/${_count(line.need)} handed in)',
    ];
    return 'Bring ${parts.join(' and ')}';
  }

  /// Inline text for a failed choice. `no_room` and `confirm_favourites` are popups instead.
  String failure(DialogueResult result) {
    switch (result.code) {
      case 'missing_items' when result.missing.isNotEmpty:
        final parts = [
          for (final line in result.missing)
            'You need ${_count(line.need)} ${itemName(line.itemId)} (you have ${_count(line.have)})',
        ];
        return '${parts.join('. ')}.';
      case 'nothing_to_hand_in':
        final names = [
          for (final group in result.stepProgress)
            for (final line in group.items)
              if (_remaining(line) > 0) itemName(line.itemId),
        ];
        if (names.isEmpty) return 'You have nothing left to hand in.';
        return 'You have no ${names.join(' or ')} to hand in.';
      case 'no_room':
        return bagFull(result.noRoom?.slotsNeeded ?? 1);
      case 'not_available':
        return 'That isn’t available right now.';
      case 'action_failed' || 'confirm_favourites':
        return 'That can’t be done right now.';
      default:
        return 'That conversation can’t go on right now.';
    }
  }

  String startFailure(String? code) => code == 'not_available'
      ? 'They have nothing to say right now.'
      : 'That conversation could not be started.';

  /// "Baked Potato x4, Cooked Perch x2" — every entry, in the engine's order.
  String favouritesList(List<DialogueItemDelta> favourites) =>
      [for (final line in favourites) '${itemName(line.itemId)} x${_count(line.qty)}'].join(', ');

  /// What a successful choice did, for the shared announcement line; null when nothing visible changed.
  String? notice(PlayerSave before, DialogueResult result) {
    final after = result.save;
    final parts = <String>[];
    final handedInItems = <String>{};
    for (final group in result.stepProgress) {
      if (group.mode == 'show') {
        if (group.done) parts.add('Shown ✓');
        continue;
      }
      for (final line in group.items) {
        handedInItems.add(line.itemId);
        parts.add(progressLine(group, line));
      }
    }
    for (final delta in result.itemDeltas) {
      if (delta.qty > 0) {
        parts.add('Received ${_count(delta.qty)} ${itemName(delta.itemId)}');
      } else if (delta.qty < 0 && !handedInItems.contains(delta.itemId)) {
        parts.add('Gave ${_count(-delta.qty)} ${itemName(delta.itemId)}');
      }
    }
    final gold = after.gold - before.gold;
    if (gold > 0) parts.add('Received ${_count(gold)} gold');
    for (final bookId in result.bookDeltas) {
      parts.add('Added ${_bookName(bookId)} to your Library');
    }
    for (final quest in after.quests) {
      final was = getQuestProgress(before, quest.questId).status;
      if (was == quest.status) continue;
      if (quest.status == 'active') parts.add('Quest started: ${_questName(quest.questId)}');
      if (quest.status == 'completed') parts.add('Quest complete: ${_questName(quest.questId)}');
    }
    for (final completion in result.questCompletions) {
      parts.addAll(completion.rewards);
    }
    if (parts.isEmpty) return null;
    final text = parts.join('. ');
    return text.endsWith('✓') ? text : '$text.';
  }

  String _amounts(List<StepProgressLine> lines, num Function(StepProgressLine) count) =>
      [for (final line in lines) '${_count(count(line))} ${itemName(line.itemId)}'].join(' and ');

  static num _remaining(StepProgressLine line) => math.max(0, line.need - line.handedIn);

  static num _movable(StepProgressLine line) => math.min(line.have, _remaining(line));

  static String _count(num value) => jsNumberToString(value);
}

T? _first<T>(Iterable<T> rows, bool Function(T row) test) {
  for (final row in rows) {
    if (test(row)) return row;
  }
  return null;
}
