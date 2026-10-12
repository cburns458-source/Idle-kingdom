/// Show / HandIn progress for the UI ("6/10 Baked Potato handed in", "You have 3/5").
///
/// Counts read the bag only, never the bank. Enchanted stacks do not count.
/// Hearted (favourited) stacks count everywhere; taking from one needs the
/// player's confirmation (see `confirm_favourites` in the engine).
/// Ported from `src/game/dialogue/stepProgress.ts`.
library;

import 'dart:math' as math;

import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../quests/quests.dart';
import '../quests/steps.dart';
import '../save/generated/save_models.dart';

class StepProgressLine {
  const StepProgressLine({
    required this.itemId,
    required this.have,
    required this.handedIn,
    required this.need,
    required this.mode,
  });

  final String itemId;

  /// Unenchanted bag count right now, hearted stacks included.
  final num have;

  /// Already kept by the NPC (HandIn); always 0 for Show.
  final num handedIn;
  final num need;

  /// `show` or `handIn`.
  final String mode;

  Map<String, Object?> toJson() => <String, Object?>{
    'itemId': itemId,
    'have': have,
    'handedIn': handedIn,
    'need': need,
    'mode': mode,
  };
}

class StepProgressGroup {
  const StepProgressGroup({
    required this.questId,
    required this.stepId,
    required this.mode,
    required this.done,
    required this.items,
  });

  final String questId;
  final String stepId;
  final String mode;

  /// The step is latched.
  final bool done;
  final List<StepProgressLine> items;

  Map<String, Object?> toJson() => <String, Object?>{
    'questId': questId,
    'stepId': stepId,
    'mode': mode,
    'done': done,
    'items': [for (final item in items) item.toJson()],
  };
}

/// Unenchanted bag quantity of [itemId].
num bagCount(PlayerSave save, String itemId) {
  num total = 0;
  for (final stack in save.inventory) {
    if (stack.itemId == itemId && isBlank(stack.enchantmentId)) total += stack.quantity;
  }
  return total;
}

/// Unenchanted bag quantity of [itemId] outside hearted (favourited) stacks.
num unfavouriteCount(PlayerSave save, String itemId) {
  num total = 0;
  for (final stack in save.inventory) {
    if (stack.itemId == itemId && isBlank(stack.enchantmentId) && stack.favorite != true) {
      total += stack.quantity;
    }
  }
  return total;
}

/// Removes [quantity] unenchanted [itemId] from the bag, unhearted stacks first.
/// Returns null when the bag holds fewer.
PlayerSave? takeFromBag(PlayerSave save, String itemId, num quantity) {
  if (quantity <= 0) return save;
  if (bagCount(save, itemId) < quantity) return null;
  final inventory = [...save.inventory];
  var remaining = quantity;
  for (final favoritePass in const <bool>[false, true]) {
    for (var index = 0; index < inventory.length; index++) {
      if (remaining <= 0) break;
      final stack = inventory[index];
      if (stack.itemId != itemId || isNotBlank(stack.enchantmentId)) continue;
      if ((stack.favorite == true) != favoritePass) continue;
      final taken = math.min(stack.quantity, remaining);
      inventory[index] = stack.copyWith(quantity: stack.quantity - taken);
      remaining -= taken;
    }
  }
  return save.copyWith(inventory: inventory.where((stack) => stack.quantity > 0).toList());
}

/// Per-item lines for a Show or HandIn step; empty for any other step.
List<StepProgressLine> stepProgressView(
  GameDatabase db,
  PlayerSave save,
  String questId,
  String stepId,
) {
  return stepProgressGroup(db, save, questId, stepId)?.items ?? const <StepProgressLine>[];
}

StepProgressGroup? stepProgressGroup(
  GameDatabase db,
  PlayerSave save,
  String questId,
  String stepId,
) {
  final step = getQuestStep(db, questId, stepId);
  final type = dialogueStepType(step);
  if (type != 'Show' && type != 'HandIn') return null;
  final mode = type == 'Show' ? 'show' : 'handIn';
  final done = isStepLatched(save, questId, stepId);
  final counters = getQuestProgress(save, questId).counters ?? const <String, num>{};
  final items = [
    for (final need in parseStepItems(step?.raw['Step Items']))
      StepProgressLine(
        itemId: need.itemId,
        have: bagCount(save, need.itemId),
        handedIn: mode == 'show'
            ? 0
            : done
            ? need.quantity
            : math.min(counters[handInCounterKey(stepId, need.itemId)] ?? 0, need.quantity),
        need: need.quantity,
        mode: mode,
      ),
  ];
  return StepProgressGroup(questId: questId, stepId: stepId, mode: mode, done: done, items: items);
}
