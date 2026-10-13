/// All-or-nothing room checks for rewards (dialogue `grant_item`, legacy quest
/// rewards, the bribe purse). A reward that does not fully fit is refused with
/// `no_room` and nothing is granted. Ported from `src/game/inventory/fit.ts`.
library;

import 'dart:math' as math;

import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../save/generated/save_models.dart';
import 'add_items.dart';
import 'capacity.dart';
import 'gold.dart';

class NoRoom {
  const NoRoom({this.slotsNeeded, this.slotsFree, this.reason, this.target, this.npcLine});

  factory NoRoom.fromJson(Map<String, Object?> json) {
    final slotsNeeded = json['slotsNeeded'];
    final slotsFree = json['slotsFree'];
    final reason = json['reason'];
    final target = json['target'];
    final npcLine = json['npcLine'];
    return NoRoom(
      slotsNeeded: slotsNeeded is num ? slotsNeeded.toInt() : null,
      slotsFree: slotsFree is num ? slotsFree.toInt() : null,
      reason: reason is String && reason.isNotEmpty ? reason : null,
      target: target is String && target.isNotEmpty ? target : null,
      npcLine: npcLine is String && npcLine.isNotEmpty ? npcLine : null,
    );
  }

  /// New slots the grants need; stacks already in the container cost none.
  final int? slotsNeeded;
  final int? slotsFree;

  /// Set when a mergeable stack is at cap and free slots would not help.
  final String? reason;

  /// Which container is full. Omitted for the bag.
  final String? target;

  /// NPC make-room line. Set only on dialogue `no_room` when the choice has a
  /// `No Room Line`. Shop, bank, and mail refusals leave this unset.
  final String? npcLine;

  Map<String, Object?> toJson() => <String, Object?>{
    if (slotsNeeded != null) 'slotsNeeded': slotsNeeded,
    if (slotsFree != null) 'slotsFree': slotsFree,
    if (reason != null) 'reason': reason,
    if (target != null) 'target': target,
    if (npcLine != null) 'npcLine': npcLine,
  };
}

class ItemGrant {
  const ItemGrant({required this.itemId, required this.quantity, this.enchantmentId});

  final String itemId;
  final num quantity;
  final String? enchantmentId;
}

class RewardsFit {
  const RewardsFit({required this.fits, required this.noRoom});

  final bool fits;
  final NoRoom noRoom;
}

/// New slots [grants] need: one per distinct unenchanted non-gold pile, or one
/// per enchanted item.
int slotsNeededForGrants(GameDatabase? db, PlayerSave save, Iterable<ItemGrant> grants) {
  final seen = <String>{};
  var needed = 0;
  for (final grant in grants) {
    if (grant.quantity <= 0) continue;
    final enchantmentId = grant.enchantmentId;
    if (isGoldCurrencyItem(grant.itemId, db) && isBlank(enchantmentId)) continue;
    if (isNotBlank(enchantmentId)) {
      needed += grant.quantity.floor();
      continue;
    }
    if (!seen.add(grant.itemId)) continue;
    if (mergeableStackIndex(save.inventory, grant.itemId, enchantmentId) >= 0) continue;
    needed += 1;
  }
  return needed;
}

/// New bag slots [itemIds] need against [save]: one per distinct non-gold item
/// without a pile to grow.
int slotsNeededForItems(GameDatabase? db, PlayerSave save, Iterable<String> itemIds) {
  return slotsNeededForGrants(db, save, [
    for (final itemId in itemIds) ItemGrant(itemId: itemId, quantity: 1),
  ]);
}

/// Human-readable refusal for a `no_room` payload.
String noRoomReason(NoRoom noRoom) {
  if (noRoom.reason == 'stack_full') {
    return 'That stack cannot hold more of this item.';
  }
  final slotsNeeded = noRoom.slotsNeeded ?? 1;
  final slotsFree = noRoom.slotsFree ?? 0;
  final short = math.max(1, slotsNeeded - slotsFree);
  if (noRoom.target == 'bank') {
    return 'Your bank is full. Make room for $short slot${short == 1 ? '' : 's'} and try again.';
  }
  return 'No room in your bag. Free $short slot${short == 1 ? '' : 's'} and try again.';
}

NoRoom _noRoomFromFit({required bool fits, required int slotsNeeded, required int slotsFree}) {
  if (!fits && slotsNeeded == 0 && slotsFree > 0) {
    return const NoRoom(reason: 'stack_full');
  }
  return NoRoom(slotsNeeded: fits ? slotsNeeded : math.max(1, slotsNeeded), slotsFree: slotsFree);
}

/// Whether every grant fits in the bag together, added in order on a copy of [save].
RewardsFit rewardsFit(
  GameDatabase? db,
  PlayerSave save,
  List<ItemGrant> grants, [
  int slotLimit = inventorySlotLimit,
]) {
  final wanted = [
    for (final grant in grants)
      if (grant.quantity > 0) grant,
  ];
  var working = save;
  var fits = true;
  for (final grant in wanted) {
    final added = addItemsToInventory(
      working,
      grant.itemId,
      grant.quantity,
      grant.enchantmentId,
      false,
      db,
      slotLimit,
    );
    if (added.added < grant.quantity.floor()) {
      fits = false;
      break;
    }
    working = added.save;
  }
  final slotsNeeded = slotsNeededForGrants(db, save, wanted);
  return RewardsFit(
    fits: fits,
    noRoom: _noRoomFromFit(
      fits: fits,
      slotsNeeded: slotsNeeded,
      slotsFree: inventorySlotsFree(save, slotLimit),
    ),
  );
}

/// `null` when every grant fits together; otherwise the `no_room` counts for
/// the whole list. Paid and claimed paths use this before changing any state.
NoRoom? noRoomFor(
  PlayerSave save,
  List<ItemGrant> grants, [
  GameDatabase? db,
  int slotLimit = inventorySlotLimit,
]) {
  final fit = rewardsFit(db, save, grants, slotLimit);
  if (fit.fits) return null;
  return noRoomPayload(fit.noRoom);
}

/// The `no_room` fields only — never extra keys from a fit result.
NoRoom noRoomPayload(NoRoom noRoom) {
  if (noRoom.reason == 'stack_full') return const NoRoom(reason: 'stack_full');
  return NoRoom(
    slotsNeeded: noRoom.slotsNeeded,
    slotsFree: noRoom.slotsFree,
    target: noRoom.target,
  );
}
