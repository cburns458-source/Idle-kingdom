import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../save/generated/save_models.dart';
import '../shops/shops.dart';
import 'favorites.dart';

/// Off-shop / field sale: half of Base Sell Value.
const num fieldSellMult = 0.5;

num? fieldSellPrice(GameDatabase db, String itemId) {
  if (itemId == currencyItemId(db)) return null;
  final item = db.items.firstWhereOrNull((row) => row.raw['Item ID'] == itemId);
  final base = baseSellValue(item);
  if (base == null || base <= 0) return null;
  return math.max(0, (base * fieldSellMult).round());
}

/// A unit price and the shop paying it, or null for a field sale.
class LocationSellPrice {
  const LocationSellPrice({required this.unitPrice, required this.shopId});

  final num unitPrice;
  final String? shopId;

  Map<String, Object?> toJson() => <String, Object?>{'unitPrice': unitPrice, 'shopId': shopId};
}

/// Best unit price for selling at the current location.
///
/// Uses an accessible shop when one will buy the item, otherwise the 50% field
/// price. Null means the item cannot be sold anywhere.
LocationSellPrice? sellPriceAtLocation(GameDatabase db, PlayerSave save, String itemId) {
  LocationSellPrice? best;
  for (final shop in shopsAtLocation(db, save.currentLocationId)) {
    if (!canAccessShop(db, save, shop).ok) continue;
    final price = playerSellPrice(db, shop, itemId);
    if (price == null) continue;
    if (best == null || price > best.unitPrice) {
      best = LocationSellPrice(unitPrice: price, shopId: shop.raw['Shop ID'] as String?);
    }
  }
  if (best != null) return best;

  final field = fieldSellPrice(db, itemId);
  if (field == null) return null;
  return LocationSellPrice(unitPrice: field, shopId: null);
}

/// Either the sale or the reason nothing was sold.
class SellInventoryResult {
  const SellInventoryResult.ok({
    required this.save,
    required this.goldEarned,
    required this.stacksSold,
    required this.message,
  }) : reason = null;

  const SellInventoryResult.failed(this.reason)
    : save = null,
      goldEarned = 0,
      stacksSold = 0,
      message = null;

  bool get ok => reason == null;
  final PlayerSave? save;
  final num goldEarned;
  final num stacksSold;
  final String? message;
  final String? reason;

  Map<String, Object?> toJson() => ok
      ? <String, Object?>{
          'ok': true,
          'save': save!.toJson(),
          'goldEarned': goldEarned,
          'stacksSold': stacksSold,
          'message': message,
        }
      : <String, Object?>{'ok': false, 'reason': reason};
}

/// Sells whole bag stacks at the current location's price.
SellInventoryResult sellInventoryIndexes(GameDatabase db, PlayerSave save, Iterable<num> indexes) {
  return sellInventoryQuantities(db, save, {
    for (final index in indexes)
      if (jsIsInteger(index) && index >= 0 && index < save.inventory.length)
        index.toInt(): save.inventory[index.toInt()].quantity,
  });
}

/// Sells a chosen quantity from each selected bag stack.
SellInventoryResult sellInventoryQuantities(
  GameDatabase db,
  PlayerSave save,
  Map<int, num> quantitiesByIndex,
) {
  final unique =
      quantitiesByIndex.keys.where((index) => index >= 0 && index < save.inventory.length).toList()
        ..sort((a, b) => b - a);

  if (unique.isEmpty) {
    return const SellInventoryResult.failed('Select at least one item to sell.');
  }

  num goldEarned = 0;
  var stacksSold = 0;
  final inventory = [...save.inventory];

  for (final index in unique) {
    final stack = inventory[index];
    final want = quantitiesByIndex[index] ?? 0;
    if (!jsIsInteger(want) || want < 1) {
      return const SellInventoryResult.failed('Choose how many to sell.');
    }
    final quantity = want.toInt();
    if (quantity > stack.quantity) {
      return const SellInventoryResult.failed('You do not have that many to sell.');
    }
    if (isFavoriteStack(stack)) {
      return const SellInventoryResult.failed(
        'Favorited items cannot be sold. Unfavorite them first.',
      );
    }
    if (isNotBlank(stack.enchantmentId)) {
      return const SellInventoryResult.failed('Enchanted items cannot be sold from the bag.');
    }
    final priced = sellPriceAtLocation(db, save, stack.itemId);
    if (priced == null) {
      final name = db.items
          .firstWhereOrNull((item) => item.raw['Item ID'] == stack.itemId)
          ?.raw['Display Name'];
      return SellInventoryResult.failed('${name is String ? name : 'That item'} cannot be sold.');
    }
    goldEarned += priced.unitPrice * quantity;
    stacksSold += 1;
    if (quantity >= stack.quantity) {
      inventory.removeAt(index);
    } else {
      inventory[index] = stack.copyWith(quantity: stack.quantity - quantity);
    }
  }

  final next = save.copyWith(
    inventory: inventory,
    gold: save.gold + goldEarned,
    statistics: PlayerStatistics(
      values: {
        ...save.statistics.values,
        'gold_earned': jsNumber(save.statistics.values['gold_earned'] ?? 0) + goldEarned,
      },
    ),
  );

  final shopsHere = shopsAtLocation(
    db,
    save.currentLocationId,
  ).any((shop) => canAccessShop(db, save, shop).ok);
  final rateNote = shopsHere ? 'shop rate' : '50% field rate';
  return SellInventoryResult.ok(
    save: next,
    goldEarned: goldEarned,
    stacksSold: stacksSold,
    message:
        'Sold $stacksSold stack${stacksSold == 1 ? '' : 's'} for '
        '${jsLocaleNumber(goldEarned)} gold ($rateNote).',
  );
}
