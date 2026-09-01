import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/requirements.dart';
import '../activity/xp.dart';
import '../cosmetics/cosmetics.dart';
import '../inventory/gold.dart';
import '../js_compat.dart';
import '../races/races.dart';
import '../save/generated/save_models.dart';

const String essenceItemId = 'ITEM-0011';
const num shopBuyMult = 2;
const num essenceBuyMult = 100;
const num miningOreSellMult = 1.5;
const num generalSellMult = 1;

/// One line of a shop's stock. Only sell-to-player entries are listed.
class ShopStockEntry {
  const ShopStockEntry({required this.itemId});

  final String itemId;

  /// Always `Sell`: the shop sells this item to the player.
  String get mode => 'Sell';

  Map<String, Object?> toJson() => <String, Object?>{'itemId': itemId, 'mode': mode};
}

List<ShopStockEntry> shopStockEntries(ShopRow shop) {
  final out = <ShopStockEntry>[];
  for (var i = 1; i <= 40; i += 1) {
    final itemId = shop.raw['Entry $i Item ID'];
    final mode = shop.raw['Entry $i Mode'];
    if (itemId is! String || itemId.isEmpty) continue;
    if (mode is String && mode.toLowerCase() == 'buy') continue;
    out.add(ShopStockEntry(itemId: itemId));
  }
  return out;
}

ShopRow? getShop(GameDatabase db, String shopId) {
  return db.shops.firstWhereOrNull((shop) => shop.raw['Shop ID'] == shopId);
}

List<ShopRow> shopsAtLocation(GameDatabase db, String locationId) {
  return db.shops.where((shop) => shop.raw['Location ID'] == locationId).toList();
}

/// True when any shop counter is listed at [locationId].
bool locationHasShop(GameDatabase db, String locationId) {
  return shopsAtLocation(db, locationId).isNotEmpty;
}

FacilityRow? shopFacility(GameDatabase db, ShopRow shop) {
  return db.facilities.firstWhereOrNull(
    (facility) =>
        facility.raw['Location ID'] == shop.raw['Location ID'] &&
        facility.raw['Facility Type'] == 'Shop' &&
        (facility.raw['Internal Key'] == shop.raw['Internal Key'] ||
            facility.raw['Display Name'] == shop.raw['Display Name']),
  );
}

/// Either a green light or the reason the counter is closed to this player.
class ShopAccess {
  const ShopAccess.ok() : reason = null;

  const ShopAccess.failed(this.reason);

  bool get ok => reason == null;
  final String? reason;

  Map<String, Object?> toJson() => <String, Object?>{
    'ok': ok,
    if (reason != null) 'reason': reason,
  };
}

ShopAccess canAccessShop(GameDatabase db, PlayerSave save, ShopRow shop) {
  if (shop.raw['Location ID'] != save.currentLocationId) {
    return const ShopAccess.failed('Travel to this shop first.');
  }
  final facility = shopFacility(db, shop);
  if (facility == null) return const ShopAccess.ok();
  final unmet = unmetHardRequirements(
    db,
    save,
    requirementsForEntity(db, 'Facility', jsString(facility.raw['Facility ID'])),
  );
  if (unmet.isNotEmpty) {
    final mining = getSkillProgress(save, 'SKL-0002').level;
    if (facility.raw['Facility ID'] == dwarvenMiningStoreFacilityId) {
      final required = dwarvenMiningStoreRequiredLevel(save);
      if (mining >= required) return const ShopAccess.ok();
      return ShopAccess.failed(
        'Requires Mining level ${jsNumberToString(required)} (have ${jsNumberToString(mining)}).',
      );
    }
    return ShopAccess.failed(unmet.first);
  }
  return const ShopAccess.ok();
}

num? baseSellValue(ItemRow? item) {
  if (item == null) return null;
  final value = item.raw['Base Sell Value'];
  if (value is! num || !value.isFinite || value < 0) return null;
  return value;
}

ItemRow? _item(GameDatabase db, String itemId) {
  return db.items.firstWhereOrNull((row) => row.raw['Item ID'] == itemId);
}

/// Price the player pays to buy one unit from the shop.
num? playerBuyPrice(GameDatabase db, ShopRow shop, String itemId) {
  final base = baseSellValue(_item(db, itemId));
  if (base == null) return null;
  if (itemId == essenceItemId) return (base * essenceBuyMult).round();
  return (base * shopBuyMult).round();
}

bool isOreItem(ItemRow item) {
  final subtype = lowerOrEmpty(item.raw['Subtype']);
  final tags = jsString(item.raw['Functional / Source Tags'] ?? '').toLowerCase();
  final name = jsString(item.raw['Display Name']).toLowerCase();
  return subtype == 'ore' || tags.contains('ore') || name.endsWith(' ore');
}

/// Price the shop pays the player for one unit. Null means it will not buy it.
num? playerSellPrice(GameDatabase db, ShopRow shop, String itemId) {
  if (itemId == currencyItemId(db)) return null;
  final item = _item(db, itemId);
  final base = baseSellValue(item);
  if (base == null || base <= 0) return null;

  final key = shop.raw['Internal Key'];
  if (key == 'dwarven_mining_store') {
    if (item == null || !isOreItem(item)) return null;
    return (base * miningOreSellMult).round();
  }
  if (key == 'wizards_shop') return null;
  if (key == 'helges_forge') {
    if (item == null || isOreItem(item) || !isSmithingProjectOutput(db, itemId)) return null;
    return (base * generalSellMult).round();
  }
  // General store buys ordinary items at Base Sell Value.
  return (base * generalSellMult).round();
}

bool isSmithingProjectOutput(GameDatabase db, String itemId) {
  return db.projects.any(
    (project) =>
        project.raw['Skill ID'] == 'SKL-0011' && project.raw['Output Item / Target ID'] == itemId,
  );
}

bool shopSellsItem(ShopRow shop, String itemId) {
  return shopStockEntries(shop).any((entry) => entry.itemId == itemId);
}

/// Stock the player can still buy — owned cosmetics stay off the counter.
List<ShopStockEntry> shopStockForPlayer(GameDatabase db, PlayerSave save, ShopRow shop) {
  return shopStockEntries(shop).where((entry) {
    final cosmetic = cosmeticByItemId(db, entry.itemId);
    if (cosmetic == null) return true;
    final cosmeticId = cosmetic.raw['Cosmetic ID'];
    return cosmeticId is! String || !isCosmeticUnlocked(save, cosmeticId);
  }).toList();
}
