import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../inventory/add_items.dart';
import '../save/generated/save_models.dart';

const String kingswoodsLocationId = 'LOC-0008';
const String bolaItemId = 'ITEM-0109';
const String slingItemId = bolaItemId;
const String kingswoodsBolaFoundMessage = 'You found a Bola among the trees.';
const String kingswoodsSlingFoundMessage = kingswoodsBolaFoundMessage;

bool saveOwnsBola(PlayerSave save) {
  if (save.inventory.any((stack) => stack.itemId == bolaItemId)) return true;
  return save.equipment.slots.values.any((stack) => stack?.itemId == bolaItemId);
}

bool saveOwnsSling(PlayerSave save) => saveOwnsBola(save);

class KingswoodsBolaGrant {
  const KingswoodsBolaGrant({required this.save, required this.granted, this.message});

  final PlayerSave save;
  final bool granted;
  final String? message;
}

typedef KingswoodsSlingGrant = KingswoodsBolaGrant;

/// First visit to the Kingswoods grants a Bola once, if the bag has room.
KingswoodsBolaGrant maybeGrantKingswoodsBola(GameDatabase db, PlayerSave save) {
  if (save.currentLocationId != kingswoodsLocationId) {
    return KingswoodsBolaGrant(save: save, granted: false);
  }
  if (save.claimedKingswoodsSling) {
    return KingswoodsBolaGrant(save: save, granted: false);
  }
  if (saveOwnsBola(save)) {
    return KingswoodsBolaGrant(save: save.copyWith(claimedKingswoodsSling: true), granted: false);
  }
  final added = addItemToInventoryExact(save, bolaItemId, 1);
  if (!added.ok) {
    return KingswoodsBolaGrant(save: save, granted: false);
  }
  final name = db.items
      .where((item) => item.raw['Item ID'] == bolaItemId)
      .map((item) => item.raw['Display Name'])
      .whereType<String>()
      .firstOrNull;
  return KingswoodsBolaGrant(
    save: added.save!.copyWith(claimedKingswoodsSling: true),
    granted: true,
    message: 'You found a ${name ?? 'Bola'} among the trees.',
  );
}

KingswoodsBolaGrant maybeGrantKingswoodsSling(GameDatabase db, PlayerSave save) {
  return maybeGrantKingswoodsBola(db, save);
}
