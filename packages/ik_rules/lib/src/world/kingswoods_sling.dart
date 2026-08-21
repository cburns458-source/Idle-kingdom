import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../inventory/add_items.dart';
import '../save/generated/save_models.dart';

const String kingswoodsLocationId = 'LOC-0008';
const String slingItemId = 'ITEM-0109';
const String kingswoodsSlingFoundMessage = 'You found a Sling among the trees.';

bool saveOwnsSling(PlayerSave save) {
  if (save.inventory.any((stack) => stack.itemId == slingItemId)) return true;
  return save.equipment.slots.values.any((stack) => stack?.itemId == slingItemId);
}

class KingswoodsSlingGrant {
  const KingswoodsSlingGrant({required this.save, required this.granted, this.message});

  final PlayerSave save;
  final bool granted;
  final String? message;
}

/// First visit to the Kingswoods grants a Sling once, if the bag has room.
KingswoodsSlingGrant maybeGrantKingswoodsSling(GameDatabase db, PlayerSave save) {
  if (save.currentLocationId != kingswoodsLocationId) {
    return KingswoodsSlingGrant(save: save, granted: false);
  }
  if (save.claimedKingswoodsSling) {
    return KingswoodsSlingGrant(save: save, granted: false);
  }
  if (saveOwnsSling(save)) {
    return KingswoodsSlingGrant(save: save.copyWith(claimedKingswoodsSling: true), granted: false);
  }
  final added = addItemToInventoryExact(save, slingItemId, 1);
  if (!added.ok) {
    return KingswoodsSlingGrant(save: save, granted: false);
  }
  final name = db.items
      .where((item) => item.raw['Item ID'] == slingItemId)
      .map((item) => item.raw['Display Name'])
      .whereType<String>()
      .firstOrNull;
  return KingswoodsSlingGrant(
    save: added.save!.copyWith(claimedKingswoodsSling: true),
    granted: true,
    message: 'You found a ${name ?? 'Sling'} among the trees.',
  );
}
