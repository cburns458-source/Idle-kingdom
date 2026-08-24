import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../inventory/add_items.dart';
import '../inventory/gold.dart';
import '../js_compat.dart';
import '../loot/drop_chance.dart';
import '../races/races.dart';
import '../rng/mulberry32.dart';
import '../save/generated/save_models.dart';
import '../spells/spells.dart';

/// One item stack granted by an action, with the name the reward UI shows.
class LootGrant {
  const LootGrant({required this.itemId, required this.quantity, required this.displayName});

  final String itemId;
  final num quantity;
  final String displayName;

  Map<String, Object?> toJson() => <String, Object?>{
    'itemId': itemId,
    'quantity': quantity,
    'displayName': displayName,
  };
}

class ActionRewards {
  const ActionRewards({required this.save, required this.loot, required this.goldGained});

  final PlayerSave save;
  final List<LootGrant> loot;
  final num goldGained;
}

num _rollQuantity(RewardEntryRow entry, RandomFn random) {
  final min = math.max(0, jsNumber(entry.raw['Minimum Quantity'] ?? 1));
  final max = math.max(min, jsNumber(entry.raw['Maximum Quantity'] ?? min));
  if (max == min) return min;
  return min + (random() * (max - min + 1)).floor();
}

RewardEntryRow? pickWeightedReward(List<RewardEntryRow> entries, RandomFn random) {
  final usable = entries.where((entry) {
    final weight = entry.raw['Weight'];
    return entry.raw['Status'] != 'Needs Data' && weight is num && weight > 0;
  }).toList();
  if (usable.isEmpty) return null;
  final total = usable.fold<num>(0, (sum, entry) => sum + jsNumber(entry.raw['Weight'] ?? 0));
  var roll = random() * total;
  for (final entry in usable) {
    roll -= jsNumber(entry.raw['Weight'] ?? 0);
    if (roll <= 0) return entry;
  }
  return usable.last;
}

/// Rolls an action's reward tables and grants what fits.
///
/// Gold-currency rewards bypass the bag and land in `save.gold`, and the race
/// gold bonus applies once to the total rather than per roll.
ActionRewards resolveActionRewards(
  GameDatabase db,
  PlayerSave save,
  ActionRow action,
  RandomFn random,
) {
  var next = save;
  final loot = <LootGrant>[];
  var goldGained = jsNumber(action.raw['Guaranteed Gold'] ?? 0);
  final skillDropBonus = raceSkillDropChanceBonusPercent(
    db,
    save,
    jsString(action.raw['Relevant Skill ID']),
  );

  void rollTable(Object? tableIdValue, Object? chanceValue) {
    final tableId = tableIdValue is String ? tableIdValue : null;
    if (isBlank(tableId)) return;
    final dropChance = applyFlatDropChanceBonus(
      applyRelativeDropChance(
        chanceValue is num ? chanceValue : 0,
        totalRelativeDropChanceBonusPercent(db, save),
      ),
      skillDropBonus,
    );
    if (dropChance == null || random() * 100 >= dropChance) return;
    final entries = db.rewardEntries.where((row) => row.raw['Reward Table ID'] == tableId).toList();
    final picked = pickWeightedReward(entries, random);
    if (picked == null) return;
    final rewardType = picked.raw['Reward Type'];
    final rewardValue = picked.raw['Reward ID / Value'];
    if (rewardType == 'Item' && rewardValue is String && rewardValue.isNotEmpty) {
      var quantity = _rollQuantity(picked, random);
      if (isGoldCurrencyItem(rewardValue, db)) {
        // Abundance doubles item drops only — gold currency item rewards stay single.
        goldGained += quantity;
        return;
      }
      final doubleChance = activeSpellItemDoubleChancePercent(db, save);
      if (doubleChance > 0 && random() * 100 < doubleChance) {
        quantity *= 2;
      }
      final granted = addItemsToInventory(next, rewardValue, quantity, null, false, db);
      next = granted.save;
      if (granted.added > 0) {
        final displayName = db.items
            .firstWhereOrNull((item) => item.raw['Item ID'] == rewardValue)
            ?.raw['Display Name'];
        loot.add(
          LootGrant(
            itemId: rewardValue,
            quantity: granted.added,
            displayName: displayName is String ? displayName : rewardValue,
          ),
        );
      }
    } else if (rewardType == 'Gold' || rewardType == 'Currency') {
      goldGained += _rollQuantity(picked, random);
    }
  }

  rollTable(action.raw['Reward Table ID'], action.raw['Drop Chance']);
  rollTable(action.raw['Secondary Reward Table ID'], action.raw['Secondary Drop Chance']);
  rollTable(action.raw['Tertiary Reward Table ID'], action.raw['Tertiary Drop Chance']);

  goldGained = applyRaceGoldGain(db, save, goldGained);
  if (goldGained > 0) {
    next = next.copyWith(gold: next.gold + goldGained);
  }

  return ActionRewards(save: next, loot: loot, goldGained: goldGained);
}
