import '../inventory/add_items.dart';
import '../js_compat.dart';
import '../save/generated/save_models.dart';
import '../world/constants.dart';

import 'package:ik_content/ik_content.dart';

/// Ranked PvP win purse. Replaces the old 1,000 gold payout.
const num rankedPvpWinPoints = 25;

const String plazaShopId = 'SHP-0011';
const String plazaShopKey = 'hearthguard_shop';

const String hearthguardHelmId = 'ITEM-0427';
const String hearthguardCuirassId = 'ITEM-0428';
const String hearthguardGreavesId = 'ITEM-0429';
const String hearthguardGauntletsId = 'ITEM-0430';
const String hearthguardBootsId = 'ITEM-0431';

const int hearthguardSetSize = 5;
const num hearthguardSetMaxHpPercent = 10;

/// Exact set-bonus copy when all five pieces are worn.
const String hearthguardSetBonusTextExact = 'Hearthguard (5/5): +10% max HP.';

const String plazaShopInsufficientPoints = 'Not enough plaza points.';
const String plazaShopUnknownItem = 'The plaza shop does not sell that item.';
const String plazaShopTravelFirst = 'Travel to the Citadel Plaza first.';

class PlazaShopStockEntry {
  const PlazaShopStockEntry({required this.itemId, required this.points});

  final String itemId;
  final num points;
}

/// Server catalog. Client-supplied prices are ignored.
const List<PlazaShopStockEntry> plazaShopStock = <PlazaShopStockEntry>[
  PlazaShopStockEntry(itemId: hearthguardCuirassId, points: 210),
  PlazaShopStockEntry(itemId: hearthguardGreavesId, points: 170),
  PlazaShopStockEntry(itemId: hearthguardHelmId, points: 150),
  PlazaShopStockEntry(itemId: hearthguardGauntletsId, points: 120),
  PlazaShopStockEntry(itemId: hearthguardBootsId, points: 120),
];

const List<String> hearthguardItemIds = <String>[
  hearthguardHelmId,
  hearthguardCuirassId,
  hearthguardGreavesId,
  hearthguardGauntletsId,
  hearthguardBootsId,
];

num plazaPointsOf(PlayerSave save) {
  final raw = jsNumber(save.plazaPoints);
  return raw < 0 ? 0 : raw.floor();
}

num? plazaShopPrice(String itemId) {
  for (final row in plazaShopStock) {
    if (row.itemId == itemId) return row.points;
  }
  return null;
}

List<String> equippedItemIds(PlayerSave save) {
  final ids = <String>[];
  for (final stack in save.equipment.slots.values) {
    final itemId = stack?.itemId;
    if (itemId != null && itemId.isNotEmpty) ids.add(itemId);
  }
  return ids;
}

num hearthguardEquippedCount(PlayerSave save) {
  final worn = equippedItemIds(save).toSet();
  var count = 0;
  for (final itemId in hearthguardItemIds) {
    if (worn.contains(itemId)) count += 1;
  }
  return count;
}

String? hearthguardSetBonusText(PlayerSave save) =>
    hearthguardEquippedCount(save) >= hearthguardSetSize ? hearthguardSetBonusTextExact : null;

num hearthguardSetMaxHpBonusPercent(PlayerSave save) =>
    hearthguardEquippedCount(save) >= hearthguardSetSize ? hearthguardSetMaxHpPercent : 0;

class PlazaShopPurchaseResult {
  const PlazaShopPurchaseResult.ok({
    required this.save,
    required this.pointsSpent,
    required this.plazaPoints,
  }) : reason = null;

  const PlazaShopPurchaseResult.failed(this.reason)
    : save = null,
      pointsSpent = null,
      plazaPoints = null;

  final PlayerSave? save;
  final num? pointsSpent;
  final num? plazaPoints;
  final String? reason;

  bool get ok => reason == null;
}

/// Buy one Hearthguard piece. Catalog price wins; any client amount is ignored.
PlazaShopPurchaseResult purchasePlazaShopItem(
  GameDatabase db,
  PlayerSave save,
  String itemId, [
  Object? clientAmount,
]) {
  final price = plazaShopPrice(itemId);
  if (price == null) return const PlazaShopPurchaseResult.failed(plazaShopUnknownItem);
  if (save.currentLocationId != citadelPlazaId) {
    return const PlazaShopPurchaseResult.failed(plazaShopTravelFirst);
  }
  final points = plazaPointsOf(save);
  if (points < price) return const PlazaShopPurchaseResult.failed(plazaShopInsufficientPoints);
  final added = addItemToInventoryExact(save, itemId, 1, null, false, db);
  if (!added.ok) return PlazaShopPurchaseResult.failed(added.reason!);
  final nextPoints = points - price;
  return PlazaShopPurchaseResult.ok(
    save: added.save!.copyWith(plazaPoints: nextPoints),
    pointsSpent: price,
    plazaPoints: nextPoints,
  );
}
