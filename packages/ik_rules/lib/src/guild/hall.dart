import 'package:ik_content/ik_content.dart';

import '../save/generated/save_models.dart';
import '../world/constants.dart';

bool locationHasGuildHall(LocationRow? location) {
  if (location == null) return false;
  return location.locationId == guildHallLocationId;
}

/// Recruits cannot chip in gold. Member and every rank above can.
bool canChipInGuildGold(String role) {
  return role == 'leader' || role == 'officer' || role == 'veteran' || role == 'member';
}

/// Recruits cannot chip in gold. Member and every rank above can.
bool canPayGuildDebt(String role) => canChipInGuildGold(role);

/// Running gold total members chip into. Caps chip-ins; never a stored coffer.
const num guildHallGoldCap = 1000000;

/// The old 1M debt is the same cap as the running gold total.
const num guildHallDebtGold = guildHallGoldCap;

const List<num> guildHallGoldMarks = <num>[10000, 40000, 130000, 400000, 1000000];

/// What a guild owes for one step of its hall, and what that step opens.
///
/// The materials are read out of the storehouse, so a donation is a deposit
/// that happens to count. Finishing a tier spends them. Gold uses one running
/// total; a room tier also needs that total to have reached [goldThreshold].
class GuildHallTier {
  const GuildHallTier({
    required this.id,
    required this.name,
    required this.blurb,
    required this.cost,
    this.goldThreshold = 0,
    this.goldCost = 0,
    this.unlock,
  });

  final String id;
  final String name;

  /// One line for the tier card, saying what the guild gets out of it.
  final String blurb;

  /// Item id to the quantity the guild must put in, in listing order.
  final List<GuildHallTierCost> cost;

  /// Cumulative gold the guild must have chipped in before this tier can finish.
  final num goldThreshold;

  /// Gold shown on the tier card as this step's cost (10k / 30k / 90k / 270k / 600k).
  final num goldCost;

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
const String guildHallTierGarden = 'hall_indoor_garden';
const String guildHallTierArcana = 'hall_arcana_station';
const String guildHallTierCage = 'hall_monster_cage';

const String guildHallUnlockBank = 'bank';
const String guildHallUnlockBoxing = 'boxing_ring';
const String guildHallUnlockGarden = 'indoor_garden';
const String guildHallUnlockArcana = 'arcana_station';
const String guildHallUnlockCage = 'monster_cage';

const Map<String, String> guildHallTierFinishLines = <String, String>{
  guildHallTierBank: 'The counting room is open for business.',
  guildHallTierBoxing: 'The ring is roped off. Settle your differences in there.',
  guildHallTierGarden: "Soil's in, and the hall smells of earth now.",
  guildHallTierArcana: 'The Arcana station hums to life in the corner.',
  guildHallTierCage: 'Something big is rattling the cage. Mind your fingers.',
};

const String _poplarLog = 'ITEM-0017';
const String _clay = 'ITEM-0002';
const String _coal = 'ITEM-0006';
const String _thread = 'ITEM-0095';
const String _oakLog = 'ITEM-0016';
const String _compost = 'ITEM-0377';
const String _essence = 'ITEM-0011';
const String _mapleLog = 'ITEM-0018';
const String _steelBar = 'ITEM-0077';
const String _ironBar = 'ITEM-0076';
const String _cedarLog = 'ITEM-0015';

/// Build the Hall, then the five rooms, finished in this order.
const List<GuildHallTier> guildHallTiers = <GuildHallTier>[
  GuildHallTier(
    id: guildHallTierBuild,
    name: 'Build the Hall',
    blurb: 'Raise the hall itself. Nothing opens yet.',
    cost: <GuildHallTierCost>[
      GuildHallTierCost(itemId: _cedarLog, quantity: 1000),
      GuildHallTierCost(itemId: _thread, quantity: 100),
    ],
  ),
  GuildHallTier(
    id: guildHallTierBank,
    name: 'Counting Room',
    blurb: 'Opens a bank in the hall.',
    cost: <GuildHallTierCost>[
      GuildHallTierCost(itemId: _poplarLog, quantity: 24000),
      GuildHallTierCost(itemId: _clay, quantity: 10000),
      GuildHallTierCost(itemId: _coal, quantity: 6320),
    ],
    goldThreshold: 10000,
    goldCost: 10000,
    unlock: guildHallUnlockBank,
  ),
  GuildHallTier(
    id: guildHallTierBoxing,
    name: 'Boxing Ring',
    blurb: 'Opens the ring, where guildmates spar.',
    cost: <GuildHallTierCost>[
      GuildHallTierCost(itemId: _clay, quantity: 14000),
      GuildHallTierCost(itemId: _thread, quantity: 13160),
      GuildHallTierCost(itemId: _poplarLog, quantity: 13160),
    ],
    goldThreshold: 40000,
    goldCost: 30000,
    unlock: guildHallUnlockBoxing,
  ),
  GuildHallTier(
    id: guildHallTierGarden,
    name: 'Indoor Garden',
    blurb: 'Opens a garden patch in the hall.',
    cost: <GuildHallTierCost>[
      GuildHallTierCost(itemId: _oakLog, quantity: 20000),
      GuildHallTierCost(itemId: _clay, quantity: 8320),
      GuildHallTierCost(itemId: _compost, quantity: 12000),
    ],
    goldThreshold: 130000,
    goldCost: 90000,
    unlock: guildHallUnlockGarden,
  ),
  GuildHallTier(
    id: guildHallTierArcana,
    name: 'Arcana Station',
    blurb: 'Opens an Arcana station in the hall.',
    cost: <GuildHallTierCost>[
      GuildHallTierCost(itemId: _essence, quantity: 16000),
      GuildHallTierCost(itemId: _mapleLog, quantity: 16000),
      GuildHallTierCost(itemId: _clay, quantity: 8320),
    ],
    goldThreshold: 400000,
    goldCost: 270000,
    unlock: guildHallUnlockArcana,
  ),
  GuildHallTier(
    id: guildHallTierCage,
    name: 'Monster Cage',
    blurb: 'Opens a training cage. XP only — no loot.',
    cost: <GuildHallTierCost>[
      GuildHallTierCost(itemId: _steelBar, quantity: 10000),
      GuildHallTierCost(itemId: _ironBar, quantity: 12000),
      GuildHallTierCost(itemId: _coal, quantity: 18320),
    ],
    goldThreshold: 1000000,
    goldCost: 600000,
    unlock: guildHallUnlockCage,
  ),
];

/// Paid gold from the old 1M debt, used when loading halls that still store remaining.
num goldContributedFromDebtRemaining(num debtRemaining) {
  final remaining = debtRemaining;
  final paid = guildHallGoldCap - remaining;
  if (paid < 0) return 0;
  if (paid > guildHallGoldCap) return guildHallGoldCap;
  return paid;
}

num guildHallGoldRemaining(num goldContributed) {
  final left = guildHallGoldCap - goldContributed;
  return left < 0 ? 0 : left;
}

/// How much of a chip-in the running total will still take.
num guildHallGoldChipInCap(num goldContributed) => guildHallGoldRemaining(goldContributed);

/// How many of [itemId] the next unfinished step will still take.
///
/// Zero when the hall is finished, when the item is not on that step, or when
/// the storehouse already holds enough. A donation uses this as a cap so extra
/// stays in the bag.
num guildHallDonationCap(
  List<String> completedTiers,
  List<InventoryStack> storehouse,
  String itemId,
) {
  final tier = nextGuildHallTier(completedTiers);
  if (tier == null) return 0;
  for (final need in guildHallTierNeeds(tier, storehouse)) {
    if (need.itemId == itemId) return need.needed - need.counted;
  }
  return 0;
}

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

bool guildHallTierGoldMet(GuildHallTier tier, num goldContributed) {
  return goldContributed >= tier.goldThreshold;
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

/// Finishes every tier the storehouse and gold total now cover, spending materials.
///
/// A room tier unlocks only when its gold threshold is passed AND its materials
/// are in. Tiers finish in order, never twice. Build the Hall has no gold gate.
GuildHallTierSettlement settleGuildHallTiers(
  List<InventoryStack> storehouse,
  List<String> completedTiers, [
  num goldContributed = 0,
]) {
  var store = storehouse;
  final done = <String>[...completedTiers];
  final finished = <GuildHallTier>[];
  while (true) {
    final tier = nextGuildHallTier(done);
    if (tier == null ||
        !guildHallTierGoldMet(tier, goldContributed) ||
        !guildHallTierMet(tier, store)) {
      break;
    }
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

bool guildHallGardenUnlocked(List<String> completedTiers) =>
    guildHallHasUnlock(completedTiers, guildHallUnlockGarden);

bool guildHallArcanaUnlocked(List<String> completedTiers) =>
    guildHallHasUnlock(completedTiers, guildHallUnlockArcana);

bool guildHallCageUnlocked(List<String> completedTiers) =>
    guildHallHasUnlock(completedTiers, guildHallUnlockCage);

String? guildHallTierFinishLine(String tierId) => guildHallTierFinishLines[tierId];
