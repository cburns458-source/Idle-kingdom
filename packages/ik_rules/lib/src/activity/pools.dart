import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../rng/mulberry32.dart';
import '../save/generated/save_models.dart';
import 'gathering.dart';

/// A pool entry paired with the action it selects.
class PoolCandidate {
  const PoolCandidate({required this.entry, required this.action});

  final PoolEntryRow entry;
  final ActionRow action;
}

/// Gathering or Combat actions with complete runtime data.
bool isSelectableAction(ActionRow action) {
  if (action.raw['Status'] == 'Needs Data') return false;
  final category = action.raw['Category'];
  if (category == 'Gathering') {
    return action.raw['Base Duration Seconds'] is num && action.raw['XP Reward'] is num;
  }
  if (category == 'Combat') {
    final targetId = action.raw['Target ID'];
    return targetId is String && targetId.isNotEmpty;
  }
  return false;
}

List<PoolCandidate> eligiblePoolEntries(GameDatabase db, String poolId) {
  final pairs = <PoolCandidate>[];
  for (final entry in db.poolEntries) {
    if (entry.raw['Pool ID'] != poolId) continue;
    if (entry.raw['Status'] == 'Needs Data') continue;
    final weight = entry.raw['Weight'];
    if (weight is! num || weight <= 0) continue;
    final action = db.actions.firstWhereOrNull(
      (row) => row.raw['Action ID'] == entry.raw['Action ID'],
    );
    if (action == null || !isSelectableAction(action)) continue;
    pairs.add(PoolCandidate(entry: entry, action: action));
  }
  return pairs;
}

/// Pool actions the player can do at full speed, or the whole pool if none.
///
/// Mixed gathering pools (rare wood, rare ore) include high-proficiency actions
/// that take tens of minutes below level. Rolling those first looks like the
/// activity dropped nothing.
List<PoolCandidate> preferredPoolEntries(GameDatabase db, PlayerSave save, String poolId) {
  final all = eligiblePoolEntries(db, poolId);
  final ready = [
    for (final pair in all)
      if (!isBelowProficiency(save, pair.action)) pair,
  ];
  return ready.isNotEmpty ? ready : all;
}

/// Picks one action, weighted by entry weight.
///
/// The TypeScript version defaults to `Math.random`; here the source of
/// randomness is always passed in so a run can be replayed.
ActionRow? pickWeightedAction(List<PoolCandidate> entries, RandomFn random) {
  if (entries.isEmpty) return null;
  final total = entries.fold<num>(0, (sum, pair) => sum + (pair.entry.weight ?? 0));
  if (total <= 0) return null;
  var roll = random() * total;
  for (final pair in entries) {
    roll -= pair.entry.weight ?? 0;
    if (roll <= 0) return pair.action;
  }
  return entries.last.action;
}
