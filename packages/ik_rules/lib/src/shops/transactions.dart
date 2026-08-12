import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../cosmetics/cosmetics.dart';
import '../inventory/add_items.dart';
import '../inventory/capacity.dart';
import '../inventory/favorites.dart';
import '../js_compat.dart';
import '../save/generated/save_models.dart';
import 'shops.dart';

/// A cosmetic a purchase unlocked, for the wardrobe-unlock popup.
class ShopCosmeticGrant {
  const ShopCosmeticGrant({required this.cosmeticId, required this.isFirstEver});

  final String cosmeticId;
  final bool isFirstEver;

  Map<String, Object?> toJson() => <String, Object?>{
    'cosmeticId': cosmeticId,
    'isFirstEver': isFirstEver,
  };
}

class ShopOfferLine {
  const ShopOfferLine({required this.itemId, required this.quantity});

  final String itemId;
  final num quantity;

  Map<String, Object?> toJson() => <String, Object?>{'itemId': itemId, 'quantity': quantity};
}

/// A pending trade: [buys] move shop to player, [sells] move player to shop.
class ShopOffer {
  const ShopOffer({this.buys = const <ShopOfferLine>[], this.sells = const <ShopOfferLine>[]});

  final List<ShopOfferLine> buys;
  final List<ShopOfferLine> sells;

  Map<String, Object?> toJson() => <String, Object?>{
    'buys': buys.map((line) => line.toJson()).toList(),
    'sells': sells.map((line) => line.toJson()).toList(),
  };
}

class ShopTransactionResult {
  const ShopTransactionResult.ok({
    required this.save,
    required this.goldDelta,
    required this.message,
    required this.cosmeticsGranted,
  }) : reason = null;

  const ShopTransactionResult.failed(this.reason)
    : save = null,
      goldDelta = 0,
      message = null,
      cosmeticsGranted = const <ShopCosmeticGrant>[];

  bool get ok => reason == null;
  final PlayerSave? save;
  final num goldDelta;
  final String? message;
  final List<ShopCosmeticGrant> cosmeticsGranted;
  final String? reason;

  Map<String, Object?> toJson() => ok
      ? <String, Object?>{
          'ok': true,
          'save': save!.toJson(),
          'goldDelta': goldDelta,
          'message': message,
          'cosmeticsGranted': cosmeticsGranted.map((grant) => grant.toJson()).toList(),
        }
      : <String, Object?>{'ok': false, 'reason': reason};
}

class _LineTotal {
  const _LineTotal.ok(this.total) : reason = null;

  const _LineTotal.failed(this.reason) : total = 0;

  bool get ok => reason == null;
  final num total;
  final String? reason;
}

_LineTotal _lineTotal(List<ShopOfferLine> lines, num? Function(String itemId) unitPrice) {
  num total = 0;
  for (final line in lines) {
    final qty = line.quantity.floor();
    if (qty <= 0) return const _LineTotal.failed('Offer quantities must be at least 1.');
    final price = unitPrice(line.itemId);
    if (price == null) return const _LineTotal.failed('That item cannot be traded here.');
    total += price * qty;
  }
  return _LineTotal.ok(total);
}

/// Confirms a buy/sell offer against a shop.
ShopTransactionResult confirmShopOffer(
  GameDatabase db,
  PlayerSave save,
  String shopId,
  ShopOffer offer,
) {
  final shop = getShop(db, shopId);
  if (shop == null) return const ShopTransactionResult.failed('Shop not found.');

  final access = canAccessShop(db, save, shop);
  if (!access.ok) return ShopTransactionResult.failed(access.reason);

  if (offer.buys.isEmpty && offer.sells.isEmpty) {
    return const ShopTransactionResult.failed('Add items to the offer first.');
  }

  for (final line in offer.buys) {
    if (!shopSellsItem(shop, line.itemId)) {
      return const ShopTransactionResult.failed('The shop does not sell that item.');
    }
  }

  final buyCost = _lineTotal(offer.buys, (itemId) => playerBuyPrice(db, shop, itemId));
  if (!buyCost.ok) return ShopTransactionResult.failed(buyCost.reason);
  final sellCredit = _lineTotal(offer.sells, (itemId) => playerSellPrice(db, shop, itemId));
  if (!sellCredit.ok) return ShopTransactionResult.failed(sellCredit.reason);

  final goldDelta = sellCredit.total - buyCost.total;
  if (save.gold + goldDelta < 0) {
    return const ShopTransactionResult.failed('Not enough gold for this purchase.');
  }

  var next = save;
  if (offer.sells.isNotEmpty) {
    final removed = _removeSellableInventory(next, offer.sells);
    if (removed == null) {
      return const ShopTransactionResult.failed(
        'Missing items to sell (favorited items cannot be sold).',
      );
    }
    next = removed;
  }

  next = next.copyWith(gold: next.gold + goldDelta);

  // Bag space is checked after sells free slots and before buys commit.
  // Cosmetics bypass the bag entirely: they unlock into the wardrobe's
  // always-owned collection, so they never need inventory space.
  var staging = next;
  final cosmeticGrants = <ShopCosmeticGrant>[];
  for (final line in offer.buys) {
    final qty = line.quantity.floor();
    final cosmetic = db.cosmetics.firstWhereOrNull((row) => row.raw['Item ID'] == line.itemId);
    if (cosmetic != null) {
      final granted = grantCosmetic(staging, jsString(cosmetic.raw['Cosmetic ID']));
      staging = granted.save;
      if (granted.granted) {
        cosmeticGrants.add(
          ShopCosmeticGrant(
            cosmeticId: jsString(cosmetic.raw['Cosmetic ID']),
            isFirstEver: granted.isFirstEver,
          ),
        );
      }
      continue;
    }
    if (!canFitItemQuantity(staging, line.itemId, qty)) {
      return const ShopTransactionResult.failed('Not enough inventory space (180 slots).');
    }
    final added = addItemToInventoryExact(staging, line.itemId, qty);
    if (!added.ok) return ShopTransactionResult.failed(added.reason);
    staging = added.save!;
  }
  next = staging;

  if (sellCredit.total > 0) {
    next = next.copyWith(
      statistics: PlayerStatistics(
        values: {
          ...next.statistics.values,
          'gold_earned': jsNumber(next.statistics.values['gold_earned'] ?? 0) + sellCredit.total,
        },
      ),
    );
  }

  final parts = <String>[
    if (buyCost.total > 0) 'spent ${jsLocaleNumber(buyCost.total)} gold',
    if (sellCredit.total > 0) 'received ${jsLocaleNumber(sellCredit.total)} gold',
  ];
  return ShopTransactionResult.ok(
    save: next,
    goldDelta: goldDelta,
    message: parts.isNotEmpty ? 'Trade complete — ${parts.join(', ')}.' : 'Trade complete.',
    cosmeticsGranted: cosmeticGrants,
  );
}

/// Removes sold quantities from non-favorite, non-enchanted bag stacks only.
PlayerSave? _removeSellableInventory(PlayerSave save, List<ShopOfferLine> sells) {
  final inventory = save.inventory.toList();
  for (final line in sells) {
    num need = line.quantity.floor();
    if (need <= 0) return null;
    for (var index = 0; index < inventory.length; index += 1) {
      if (need <= 0) break;
      final stack = inventory[index];
      if (stack.itemId != line.itemId) continue;
      if (isFavoriteStack(stack) || isNotBlank(stack.enchantmentId)) continue;
      final take = stack.quantity < need ? stack.quantity : need;
      inventory[index] = stack.copyWith(quantity: stack.quantity - take);
      need -= take;
    }
    if (need > 0) return null;
  }
  return save.copyWith(inventory: inventory.where((stack) => stack.quantity > 0).toList());
}
