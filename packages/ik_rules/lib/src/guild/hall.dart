import 'package:ik_content/ik_content.dart';

import '../save/generated/save_models.dart';
import '../world/constants.dart';

bool locationHasGuildHall(LocationRow? location) {
  if (location == null) return false;
  return location.locationId == guildHallLocationId;
}

/// Recruits cannot pay the hall debt. Member and every rank above can.
bool canPayGuildDebt(String role) {
  return role == 'leader' || role == 'officer' || role == 'veteran' || role == 'member';
}

const num guildHallDebtGold = 1000000;

/// What a guild owes for one step of its hall, and what that step opens.
///
/// The materials are read out of the storehouse, so a donation is a deposit
/// that happens to count. Finishing a tier spends them.
class GuildHallTier {
  const GuildHallTier({
    required this.id,
    required this.name,
    required this.blurb,
    required this.cost,
    this.unlock,
  });

  final String id;
  final String name;

  /// One line for the tier card, saying what the guild gets out of it.
  final String blurb;

  /// Item id to the quantity the guild must put in, in listing order.
  final List<GuildHallTierCost> cost;

  /// What opens in the hall when the tier is finished, or null when the tier
  /// is only the building itself.
  final String? unlock;
}

class GuildHallTierCost {
  const GuildHallTierCost({required this.itemId, required this.quantity});

  final String itemId;
  final num quantity;
}

/// Reading of one material against what a tier asks for.
class GuildHallTierNeed {
  const GuildHallTierNeed({required this.itemId, required this.needed, required this.have});

  final String itemId;
  final num needed;
  final num have;

  bool get met => have >= needed;

  /// Capped at [needed], so a card never reads past full.
  num get counted => have < needed ? have : needed;
}

const String guildHallTierBuild = 'build_the_hall';
const String guildHallTierBank = 'hall_bank';
const String guildHallTierBoxing = 'hall_boxing_ring';

const String guildHallUnlockBank = 'bank';
const String guildHallUnlockBoxing = 'boxing_ring';

/// The three steps of a hall, finished in this order.
const List<GuildHallTier> guildHallTiers = <GuildHallTier>[
  GuildHallTier(
    id: guildHallTierBuild,
    name: 'Build the Hall',
    blurb: 'Raise the hall itself. Nothing opens yet.',
    cost: <GuildHallTierCost>[
      GuildHallTierCost(itemId: 'ITEM-0015', quantity: 1000),
      GuildHallTierCost(itemId: 'ITEM-0095', quantity: 100),
    ],
  ),
  GuildHallTier(
    id: guildHallTierBank,
    name: 'Counting Room',
    blurb: 'Opens a bank in the hall.',
    cost: <GuildHallTierCost>[
      GuildHallTierCost(itemId: 'ITEM-0017', quantity: 1000),
      GuildHallTierCost(itemId: 'ITEM-0002', quantity: 200),
      GuildHallTierCost(itemId: 'ITEM-0006', quantity: 100),
    ],
    unlock: guildHallUnlockBank,
  ),
  GuildHallTier(
    id: guildHallTierBoxing,
    name: 'Boxing Ring',
    blurb: 'Opens the ring, where guildmates spar.',
    cost: <GuildHallTierCost>[
      GuildHallTierCost(itemId: 'ITEM-0002', quantity: 300),
      GuildHallTierCost(itemId: 'ITEM-0095', quantity: 300),
      GuildHallTierCost(itemId: 'ITEM-0017', quantity: 300),
    ],
    unlock: guildHallUnlockBoxing,
  ),
];

/// The tier a guild is working on, or null once the hall is finished.
GuildHallTier? nextGuildHallTier(List<String> completedTiers) {
  for (final tier in guildHallTiers) {
    if (!completedTiers.contains(tier.id)) return tier;
  }
  return null;
}

/// How far the storehouse gets a tier, material by material.
List<GuildHallTierNeed> guildHallTierNeeds(GuildHallTier tier, List<InventoryStack> storehouse) {
  return tier.cost.map((cost) {
    num have = 0;
    for (final stack in storehouse) {
      if (stack.itemId == cost.itemId) have += stack.quantity;
    }
    return GuildHallTierNeed(itemId: cost.itemId, needed: cost.quantity, have: have);
  }).toList();
}

bool guildHallTierMet(GuildHallTier tier, List<InventoryStack> storehouse) {
  return guildHallTierNeeds(tier, storehouse).every((need) => need.met);
}

/// The storehouse once a finished tier has taken its materials out of it.
///
/// Stacks are drawn down in the order they sit in, and an emptied stack goes.
List<InventoryStack> spendGuildHallTier(GuildHallTier tier, List<InventoryStack> storehouse) {
  final owed = <String, num>{};
  for (final cost in tier.cost) {
    owed[cost.itemId] = (owed[cost.itemId] ?? 0) + cost.quantity;
  }
  final left = <InventoryStack>[];
  for (final stack in storehouse) {
    final due = owed[stack.itemId] ?? 0;
    if (due <= 0) {
      left.add(stack);
      continue;
    }
    if (due >= stack.quantity) {
      owed[stack.itemId] = due - stack.quantity;
      continue;
    }
    owed[stack.itemId] = 0;
    left.add(stack.copyWith(quantity: stack.quantity - due));
  }
  return left;
}

/// A storehouse deposit settled against the tiers it just paid for.
class GuildHallTierSettlement {
  const GuildHallTierSettlement({
    required this.storehouse,
    required this.completedTiers,
    required this.finishedNow,
  });

  final List<InventoryStack> storehouse;
  final List<String> completedTiers;

  /// The tiers this settlement finished, in the order they were finished.
  final List<GuildHallTier> finishedNow;
}

/// Finishes every tier the storehouse now covers, spending its materials.
///
/// Runs in a loop because one large donation can cover more than one tier.
GuildHallTierSettlement settleGuildHallTiers(
  List<InventoryStack> storehouse,
  List<String> completedTiers,
) {
  var store = storehouse;
  final done = <String>[...completedTiers];
  final finished = <GuildHallTier>[];
  while (true) {
    final tier = nextGuildHallTier(done);
    if (tier == null || !guildHallTierMet(tier, store)) break;
    store = spendGuildHallTier(tier, store);
    done.add(tier.id);
    finished.add(tier);
  }
  return GuildHallTierSettlement(storehouse: store, completedTiers: done, finishedNow: finished);
}

bool guildHallHasUnlock(List<String> completedTiers, String unlock) {
  for (final tier in guildHallTiers) {
    if (tier.unlock == unlock && completedTiers.contains(tier.id)) return true;
  }
  return false;
}

bool guildHallBankUnlocked(List<String> completedTiers) =>
    guildHallHasUnlock(completedTiers, guildHallUnlockBank);

bool guildHallBoxingUnlocked(List<String> completedTiers) =>
    guildHallHasUnlock(completedTiers, guildHallUnlockBoxing);
