/// All-or-nothing room checks for rewards (dialogue `grant_item`, legacy quest
/// rewards, the bribe purse). A reward that does not fully fit is refused with
/// `no_room` and nothing is granted. Ported from `src/game/inventory/fit.ts`.
library;

import 'dart:math' as math;

import 'package:ik_content/ik_content.dart';

import '../save/generated/save_models.dart';
import 'add_items.dart';
import 'capacity.dart';
import 'gold.dart';

class NoRoom {
  const NoRoom({required this.slotsNeeded, required this.slotsFree});

  /// New bag slots the grants need; stacks already in the bag cost none.
  final int slotsNeeded;
  final int slotsFree;

  Map<String, Object?> toJson() => <String, Object?>{
    'slotsNeeded': slotsNeeded,
    'slotsFree': slotsFree,
  };
}

class ItemGrant {
  const ItemGrant({required this.itemId, required this.quantity});

  final String itemId;
  final num quantity;
}

class RewardsFit {
  const RewardsFit({required this.fits, required this.noRoom});

  final bool fits;
  final NoRoom noRoom;
}

/// New bag slots [itemIds] need against [save]: one per distinct non-gold item
/// without a pile to grow.
int slotsNeededForItems(GameDatabase? db, PlayerSave save, Iterable<String> itemIds) {
  final seen = <String>{};
  var needed = 0;
  for (final itemId in itemIds) {
    if (isGoldCurrencyItem(itemId, db) || !seen.add(itemId)) continue;
    if (mergeableStackIndex(save.inventory, itemId) >= 0) continue;
    needed += 1;
  }
  return needed;
}

/// `No room in your bag. Free N slot(s) and try again.`
String noRoomReason(NoRoom noRoom) {
  final short = math.max(1, noRoom.slotsNeeded - noRoom.slotsFree);
  return 'No room in your bag. Free $short slot${short == 1 ? '' : 's'} and try again.';
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
      null,
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
  final slotsNeeded = slotsNeededForItems(db, save, wanted.map((grant) => grant.itemId));
  return RewardsFit(
    fits: fits,
    noRoom: NoRoom(
      slotsNeeded: fits ? slotsNeeded : math.max(1, slotsNeeded),
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
  return fit.fits ? null : fit.noRoom;
}
