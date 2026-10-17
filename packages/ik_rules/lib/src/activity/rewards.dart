import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../cosmetics/cosmetics.dart';
import '../critters/critters.dart';
import '../inventory/add_items.dart';
import '../inventory/gold.dart';
import '../js_compat.dart';
import '../library/books.dart';
import '../loot/drop_chance.dart';
import '../religion/religion.dart';
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

/// One row per itemId, quantities summed, first displayName kept, then sorted.
List<LootGrant> mergeLeftBehind(Iterable<LootGrant> grants) {
  final byId = <String, LootGrant>{};
  for (final grant in grants) {
    if (grant.quantity <= 0) continue;
    final existing = byId[grant.itemId];
    if (existing != null) {
      byId[grant.itemId] = LootGrant(
        itemId: existing.itemId,
        quantity: existing.quantity + grant.quantity,
        displayName: existing.displayName,
      );
    } else {
      byId[grant.itemId] = grant;
    }
  }
  final merged = byId.values.toList()..sort((left, right) => left.itemId.compareTo(right.itemId));
  return merged;
}

class ActionCosmeticGrant {
  const ActionCosmeticGrant({required this.cosmeticId, required this.isFirstEver});

  final String cosmeticId;
  final bool isFirstEver;

  Map<String, Object?> toJson() => <String, Object?>{
    'cosmeticId': cosmeticId,
    'isFirstEver': isFirstEver,
  };
}

/// A Library book unlocked by a `Book` reward entry. Never enters the bag.
class ActionBookGrant {
  const ActionBookGrant({required this.bookId, required this.isFirstEver});

  final String bookId;
  final bool isFirstEver;

  Map<String, Object?> toJson() => <String, Object?>{'bookId': bookId, 'isFirstEver': isFirstEver};
}

class ActionRewards {
  const ActionRewards({
    required this.save,
    required this.loot,
    required this.goldGained,
    this.cosmeticsGranted = const <ActionCosmeticGrant>[],
    this.booksGranted = const <ActionBookGrant>[],
    this.leftBehind = const <LootGrant>[],
  });

  final PlayerSave save;
  final List<LootGrant> loot;
  final num goldGained;
  final List<ActionCosmeticGrant> cosmeticsGranted;
  final List<ActionBookGrant> booksGranted;

  /// Drops that rolled but did not fit in the bag. Same shape as [loot].
  final List<LootGrant> leftBehind;
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
  RandomFn random, [
  num dropChanceScale = 1,
]) {
  var next = save;
  final loot = <LootGrant>[];
  final leftBehind = <LootGrant>[];
  final cosmeticsGranted = <ActionCosmeticGrant>[];
  final booksGranted = <ActionBookGrant>[];
  final scale = dropChanceScale.isFinite ? math.max(0, dropChanceScale) : 1;
  var goldGained = jsNumber(action.raw['Guaranteed Gold'] ?? 0) * scale;
  final skillDropBonus = alignmentSkillDropChanceBonusPercent(
    db,
    save,
    jsString(action.raw['Relevant Skill ID']),
  );

  void rollTable(Object? tableIdValue, Object? chanceValue) {
    final tableId = tableIdValue is String ? tableIdValue : null;
    if (isBlank(tableId)) return;
    final dropChance = applyFlatDropChanceBonus(
      applyRelativeDropChance(
        (chanceValue is num ? chanceValue : 0) * scale,
        totalRelativeDropChanceBonusPercent(db, save) +
            equippedSkillRelativeDropChanceBonusPercent(
              db,
              save,
              jsString(action.raw['Relevant Skill ID']),
            ),
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
      final rawName = db.items
          .firstWhereOrNull((item) => item.raw['Item ID'] == rewardValue)
          ?.raw['Display Name'];
      final displayName = rawName is String ? rawName : rewardValue;
      if (granted.added > 0) {
        loot.add(LootGrant(itemId: rewardValue, quantity: granted.added, displayName: displayName));
      }
      if (granted.added < quantity) {
        leftBehind.add(
          LootGrant(
            itemId: rewardValue,
            quantity: quantity - granted.added,
            displayName: displayName,
          ),
        );
      }
    } else if (rewardType == 'Gold' || rewardType == 'Currency') {
      goldGained += _rollQuantity(picked, random);
    } else if (rewardType == 'Critter' && rewardValue is String && rewardValue.isNotEmpty) {
      final granted = grantCritterToCollection(next, rewardValue);
      if (granted.ok) {
        next = granted.save!;
        loot.add(
          LootGrant(itemId: rewardValue, quantity: 1, displayName: granted.critter!.displayName),
        );
      }
    } else if (rewardType == 'Cosmetic' && rewardValue is String && rewardValue.isNotEmpty) {
      final cosmeticId = rewardValue;
      final granted = grantCosmetic(next, cosmeticId);
      if (granted.granted) {
        next = granted.save;
        cosmeticsGranted.add(
          ActionCosmeticGrant(cosmeticId: cosmeticId, isFirstEver: granted.isFirstEver),
        );
        final itemId = db.cosmetics
            .firstWhereOrNull((row) => row.raw['Cosmetic ID'] == cosmeticId)
            ?.raw['Item ID'];
        final displayName = itemId is String
            ? (db.items
                      .firstWhereOrNull((item) => item.raw['Item ID'] == itemId)
                      ?.raw['Display Name'] ??
                  cosmeticId)
            : cosmeticId;
        loot.add(
          LootGrant(
            itemId: cosmeticId,
            quantity: 1,
            displayName: displayName is String ? displayName : cosmeticId,
          ),
        );
      }
    } else if (rewardType == 'Book' && rewardValue is String && rewardValue.isNotEmpty) {
      // One-time find: once the book is in the Library the roll grants nothing.
      final granted = grantBook(next, rewardValue);
      if (granted.granted) {
        next = granted.save;
        booksGranted.add(ActionBookGrant(bookId: rewardValue, isFirstEver: granted.isFirstEver));
      }
    }
  }

  rollTable(action.raw['Reward Table ID'], action.raw['Drop Chance']);
  rollTable(action.raw['Secondary Reward Table ID'], action.raw['Secondary Drop Chance']);
  rollTable(action.raw['Tertiary Reward Table ID'], action.raw['Tertiary Drop Chance']);

  goldGained = applyAlignmentGoldGain(db, save, goldGained);
  if (goldGained > 0) {
    next = next.copyWith(
      gold: next.gold + goldGained,
      statistics: PlayerStatistics(
        values: {
          ...next.statistics.values,
          'gold_earned': jsNumber(next.statistics.values['gold_earned'] ?? 0) + goldGained,
        },
      ),
    );
  }

  return ActionRewards(
    save: next,
    loot: loot,
    goldGained: goldGained,
    cosmeticsGranted: cosmeticsGranted,
    booksGranted: booksGranted,
    leftBehind: leftBehind,
  );
}
