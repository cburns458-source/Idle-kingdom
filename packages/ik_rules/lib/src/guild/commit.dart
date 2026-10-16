import '../save/generated/save_models.dart';
import 'achievements.dart';
import 'hall.dart';

const String _keySep = '\u001f';

/// How much gold the hosted save actually lost. Never a client-sent total.
num goldTakenFromPlayerSaves(num previousGold, num nextGold) {
  final before = previousGold.isFinite ? previousGold.floor() : 0;
  final after = nextGold.isFinite ? nextGold.floor() : 0;
  final taken = before - after;
  return taken < 0 ? 0 : taken;
}

/// A hall write the client (or a buggy caller) asked for. Gold totals and
/// completed tiers on this object are ignored.
class GuildHallCommitProposal {
  const GuildHallCommitProposal({
    this.goldContributed,
    this.completedTiers,
    this.storehouse = const <InventoryStack>[],
    this.bankItems = const <InventoryStack>[],
  });

  final num? goldContributed;
  final List<String>? completedTiers;
  final List<InventoryStack> storehouse;
  final List<InventoryStack> bankItems;
}

const String guildHallBankMismatchRefusal = 'The guild bank change did not match the save.';
const String _goldCapRefusal = 'The gold total is already at its cap.';
const String _goldOverpayRefusal = 'That would go past the gold cap.';

class GuildHallCommitResult {
  const GuildHallCommitResult({
    this.ok = true,
    this.reason,
    required this.goldTaken,
    required this.goldContributed,
    required this.goldContributedBy,
    this.donatedBy = const <String, bool>{},
    required this.storehouse,
    required this.completedTiers,
    required this.bankItems,
    required this.finishedNow,
  });

  factory GuildHallCommitResult.failed(String reason) => GuildHallCommitResult(
    ok: false,
    reason: reason,
    goldTaken: 0,
    goldContributed: 0,
    goldContributedBy: const <String, num>{},
    storehouse: const <InventoryStack>[],
    completedTiers: const <String>[],
    bankItems: const <InventoryStack>[],
    finishedNow: const <String>[],
  );

  final bool ok;
  final String? reason;
  final num goldTaken;
  final num goldContributed;
  final Map<String, num> goldContributedBy;
  final Map<String, bool> donatedBy;
  final List<InventoryStack> storehouse;
  final List<String> completedTiers;
  final List<InventoryStack> bankItems;
  final List<String> finishedNow;
}

String stackQtyKey(InventoryStack stack) => '${stack.itemId}$_keySep${stack.enchantmentId ?? ''}';

Map<String, num> qtyByKey(List<InventoryStack> stacks) {
  final map = <String, num>{};
  for (final stack in stacks) {
    if (stack.itemId.isEmpty) continue;
    final qty = stack.quantity.isFinite ? stack.quantity.floor() : 0;
    if (qty <= 0) continue;
    final key = stackQtyKey(stack);
    map[key] = (map[key] ?? 0) + qty;
  }
  return map;
}

({String itemId, String? enchantmentId}) _parseQtyKey(String key) {
  final at = key.indexOf(_keySep);
  if (at < 0) return (itemId: key, enchantmentId: null);
  final enchantment = key.substring(at + 1);
  return (itemId: key.substring(0, at), enchantmentId: enchantment.isEmpty ? null : enchantment);
}

num _qtyOf(Map<String, num> map, String key) => map[key] ?? 0;

Set<String> _allKeys(List<Map<String, num>> maps) {
  final keys = <String>{};
  for (final map in maps) {
    keys.addAll(map.keys);
  }
  return keys;
}

List<InventoryStack> addToGuildHallStorehouse(
  List<InventoryStack> storehouse,
  String itemId,
  num quantity, [
  String? enchantmentId,
]) {
  final want = quantity.isFinite ? quantity.floor() : 0;
  if (want <= 0) return storehouse;
  if (enchantmentId != null && enchantmentId.isNotEmpty) {
    return <InventoryStack>[
      ...storehouse,
      InventoryStack(itemId: itemId, quantity: want, enchantmentId: enchantmentId),
    ];
  }
  final at = storehouse.indexWhere(
    (stack) => stack.itemId == itemId && (stack.enchantmentId == null),
  );
  if (at < 0) {
    return <InventoryStack>[...storehouse, InventoryStack(itemId: itemId, quantity: want)];
  }
  final next = <InventoryStack>[...storehouse];
  next[at] = next[at].copyWith(quantity: next[at].quantity + want);
  return next;
}

List<InventoryStack> takeFromGuildHallStorehouse(
  List<InventoryStack> storehouse,
  String itemId,
  num quantity, [
  String? enchantmentId,
]) {
  num owed = quantity.isFinite ? quantity.floor() : 0;
  if (owed <= 0) return storehouse;
  final left = <InventoryStack>[];
  for (final stack in storehouse) {
    final sameEnchant = (stack.enchantmentId ?? '') == (enchantmentId ?? '');
    if (owed <= 0 || stack.itemId != itemId || !sameEnchant) {
      left.add(stack);
      continue;
    }
    if (owed >= stack.quantity) {
      owed = owed - stack.quantity;
      continue;
    }
    left.add(stack.copyWith(quantity: stack.quantity - owed));
    owed = 0;
  }
  return left;
}

/// Hall gold, storehouse, and finished tiers from the save immediately before
/// the hall command versus after it. Catch-up must already be applied to the
/// previous gold and inventory. Over-cap gold and a mismatched bank are refused.
///
/// [proposal.goldContributed] and [proposal.completedTiers] are never written.
GuildHallCommitResult commitGuildHallFromPlayerSaves({
  required num previousGold,
  required num nextGold,
  required List<InventoryStack> previousInventory,
  required List<InventoryStack> nextInventory,
  required num hallGoldContributed,
  Map<String, num> hallGoldContributedBy = const <String, num>{},
  Map<String, bool> hallDonatedBy = const <String, bool>{},
  List<InventoryStack> hallStorehouse = const <InventoryStack>[],
  List<String> hallCompletedTiers = const <String>[],
  List<InventoryStack> previousBankItems = const <InventoryStack>[],
  GuildHallCommitProposal proposal = const GuildHallCommitProposal(),
  String userId = '',
}) {
  final room = guildHallGoldRemaining(hallGoldContributed);
  final goldDelta = goldTakenFromPlayerSaves(previousGold, nextGold);
  if (goldDelta > room) {
    return GuildHallCommitResult.failed(room <= 0 ? _goldCapRefusal : _goldOverpayRefusal);
  }
  final goldTaken = goldDelta;
  final goldContributed = hallGoldContributed + goldTaken;
  final goldContributedBy = <String, num>{...hallGoldContributedBy};
  if (goldTaken > 0 && userId.isNotEmpty) {
    goldContributedBy[userId] = (goldContributedBy[userId] ?? 0) + goldTaken;
  }

  final previousInv = qtyByKey(previousInventory);
  final nextInv = qtyByKey(nextInventory);
  final oldBank = qtyByKey(previousBankItems);
  final proposedBank = qtyByKey(proposal.bankItems);
  final oldStore = qtyByKey(hallStorehouse);
  final proposedStore = qtyByKey(proposal.storehouse);

  var storehouse = <InventoryStack>[...hallStorehouse];
  var donatedAny = goldTaken > 0;
  var donatedBy = Map<String, bool>.from(hallDonatedBy);
  for (final key in _allKeys(<Map<String, num>>[
    previousInv,
    nextInv,
    oldBank,
    proposedBank,
    oldStore,
    proposedStore,
  ])) {
    final lost = _qtyOf(previousInv, key) - _qtyOf(nextInv, key);
    final gained = _qtyOf(nextInv, key) - _qtyOf(previousInv, key);
    final lostQty = lost < 0 ? 0 : lost;
    final gainedQty = gained < 0 ? 0 : gained;
    final bankGainRaw = _qtyOf(proposedBank, key) - _qtyOf(oldBank, key);
    final bankLossRaw = _qtyOf(oldBank, key) - _qtyOf(proposedBank, key);
    final bankGain = (bankGainRaw < 0 ? 0 : bankGainRaw) > lostQty
        ? lostQty
        : (bankGainRaw < 0 ? 0 : bankGainRaw);
    final bankLoss = (bankLossRaw < 0 ? 0 : bankLossRaw) > gainedQty
        ? gainedQty
        : (bankLossRaw < 0 ? 0 : bankLossRaw);
    final expectedBank = _qtyOf(oldBank, key) + bankGain - bankLoss;
    if (_qtyOf(proposedBank, key) != expectedBank) {
      return GuildHallCommitResult.failed(guildHallBankMismatchRefusal);
    }
    final donated = lostQty - bankGain;
    final proposedStoreLoss = _qtyOf(oldStore, key) - _qtyOf(proposedStore, key);
    final withdrawnCap = proposedStoreLoss < 0 ? 0 : proposedStoreLoss;
    final withdrawnWant = gainedQty - bankLoss;
    final withdrawn = withdrawnWant < withdrawnCap ? withdrawnWant : withdrawnCap;
    final parsed = _parseQtyKey(key);
    if (donated > 0) {
      donatedAny = true;
      storehouse = addToGuildHallStorehouse(
        storehouse,
        parsed.itemId,
        donated,
        parsed.enchantmentId,
      );
    }
    if (withdrawn > 0) {
      storehouse = takeFromGuildHallStorehouse(
        storehouse,
        parsed.itemId,
        withdrawn,
        parsed.enchantmentId,
      );
    }
  }

  final settled = settleGuildHallTiers(storehouse, hallCompletedTiers, goldContributed);
  if (donatedAny && userId.isNotEmpty) {
    donatedBy = withGuildHallDonor(donatedBy, userId);
  }
  return GuildHallCommitResult(
    goldTaken: goldTaken,
    goldContributed: goldContributed,
    goldContributedBy: goldContributedBy,
    donatedBy: donatedBy,
    storehouse: settled.storehouse,
    completedTiers: settled.completedTiers,
    bankItems: proposal.bankItems,
    finishedNow: settled.finishedNow.map((tier) => tier.id).toList(),
  );
}
