/// The Bazaar exchange: offers, trades, guide prices, and the collection box.
///
/// Separate from `bazaar.dart`, which is the Citadel notice board and stays what
/// it is. Nothing in this file talks to a backend and nothing in it holds state;
/// it is the shapes the exchange is read in and the handful of rules both the
/// screen and the server have to agree on.
///
/// The exchange itself is server-decided, which nothing else in the game is.
/// That is not a change of heart about client-resolved play: it is that an
/// invented sell order is gold in somebody else's purse, so the offer has to
/// cost a save the server can see. What that means here is that these types are
/// read-only records of what the server did, and the one thing the client
/// computes is what it is about to ask for.
library;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'cloud_save.dart';

typedef BazaarSide = String;

const BazaarSide bazaarBuy = 'buy';
const BazaarSide bazaarSell = 'sell';

/// Offers a player may have open at once. Each one is a buy or a sell.
const int bazaarOfferSlots = 6;

/// Trades of their own a player can look back over.
const int bazaarHistoryLength = 10;

/// Above this much per item, a sale is taxed. Per item, not per offer: a
/// thousand of something cheap is not a hundred thousand gold of taxable trade.
const int bazaarTaxThreshold = 100;

/// The cut taken from a taxed sale, as a percentage.
const int bazaarTaxPercent = 1;

/// The most an offer may be worth, matching the gold a cloud save may hold.
/// Without it a filled order could owe somebody more gold than a save can keep.
const int bazaarOfferValueCap = 1000000000;

/// Gold taken from the seller on a trade of [quantity] at [unitPrice].
num bazaarTax(num unitPrice, num quantity) {
  final price = unitPrice.floor();
  final count = quantity.floor();
  if (price <= bazaarTaxThreshold || count <= 0) return 0;
  return (price * count * bazaarTaxPercent / 100).floor();
}

/// What a seller is paid for [quantity] at [unitPrice], after tax.
num bazaarSellerReceives(num unitPrice, num quantity) =>
    unitPrice.floor() * quantity.floor() - bazaarTax(unitPrice, quantity);

/// True when a sale at [unitPrice] is taxed at all.
bool bazaarTaxApplies(num unitPrice) => unitPrice.floor() > bazaarTaxThreshold;

/// Why [stack] cannot be listed, or null when it can.
///
/// Gold is the currency rather than a good. An enchanted item is one of a kind
/// and would lose that in a pile. A favourite is the flag a player sets on the
/// things they do not want sold, and the exchange honours it the way the shops
/// already do. The server checks all six again against its own copy of the
/// save; this is so the screen does not offer what would only be refused.
String? bazaarStackRefusal(InventoryStack stack, [GameDatabase? db]) {
  if (isGoldCurrencyItem(stack.itemId, db)) return bazaarGoldNotTraded;
  if (isNotBlank(stack.enchantmentId)) return bazaarEnchantedNotTraded;
  if (isFavoriteStack(stack)) return bazaarFavoriteNotTraded;
  if (stack.quantity < 1) return bazaarNothingToSell;
  return null;
}

/// True when [itemId] is something the exchange will carry at all.
///
/// Derived rather than declared: an item the shops price is an item the players
/// can price. There is no tradable column in the game database, and adding one
/// would mean every new item having to remember to set it.
bool bazaarItemTradable(GameDatabase db, String itemId) {
  if (isGoldCurrencyItem(itemId, db)) return false;
  final item = db.items.firstWhereOrNull((row) => row.itemId == itemId);
  final value = baseSellValue(item);
  return value != null && value > 0;
}

const String bazaarGoldNotTraded = 'Gold is what you trade with, not what you trade.';
const String bazaarEnchantedNotTraded = 'Enchanted items cannot be listed.';
const String bazaarFavoriteNotTraded = 'Unfavourite the stack to sell it.';
const String bazaarNothingToSell = 'There is nothing there to sell.';
const String bazaarUntradableItem = 'Nobody at the Bazaar deals in that.';

/// Local play has no other players in it, so there is no book to read.
const String bazaarHostedOnly = 'The Bazaar opens once you are playing on an account.';

const String bazaarSignInToTrade = 'Sign in to trade at the Bazaar.';

const String bazaarBlurbMarket =
    'Buy and sell with every other player. Six offers at a time; '
    'sales over 100 gold an item pay 1%.';

const String bazaarEmptyBook = 'Nothing is on offer yet.';

const String bazaarEmptyOffers = 'No offers open. Six slots are yours to use.';

const String bazaarEmptyHistory = 'No trades yet.';

const String bazaarEmptyCollection = 'The collection box is empty.';

const String bazaarWithdrawFirst = 'Withdraw items from the bank before listing them.';

/// One of a player's own offers.
class MarketOrder {
  const MarketOrder({
    required this.id,
    required this.side,
    required this.itemId,
    required this.unitPrice,
    required this.quantity,
    required this.filled,
    required this.goldEscrow,
    required this.slot,
    required this.status,
    required this.createdAt,
  });

  factory MarketOrder.fromJson(Map<String, Object?> json) => MarketOrder(
    id: _str(json['id']),
    side: _str(json['side']),
    itemId: _str(json['itemId']),
    unitPrice: _num(json['unitPrice']),
    quantity: _num(json['quantity']),
    filled: _num(json['filled']),
    goldEscrow: _num(json['goldEscrow']),
    slot: _num(json['slot']).toInt(),
    status: _str(json['status']),
    createdAt: _str(json['createdAt']),
  );

  final String id;
  final BazaarSide side;
  final String itemId;
  final num unitPrice;

  /// What was offered. This never moves; [filled] is what has traded of it.
  final num quantity;
  final num filled;

  /// Gold the exchange still holds for a buy order.
  final num goldEscrow;

  /// Which of the six boxes this offer sits in.
  final int slot;

  /// `open`, `filled`, or `cancelled`.
  final String status;
  final String createdAt;

  bool get isBuy => side == bazaarBuy;

  num get remaining => quantity - filled;

  /// 0 to 1, for the bar across an offer box.
  double get progress => quantity <= 0 ? 0 : (filled / quantity).clamp(0, 1).toDouble();

  bool get isPartlyFilled => filled > 0 && filled < quantity;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'side': side,
    'itemId': itemId,
    'unitPrice': unitPrice,
    'quantity': quantity,
    'filled': filled,
    'goldEscrow': goldEscrow,
    'slot': slot,
    'status': status,
    'createdAt': createdAt,
  };
}

/// Resting quantity at one price on one side of an item's book.
///
/// Added up by the server: who is selling is nobody's business, only what is on
/// offer and at what.
class MarketOffer {
  const MarketOffer({
    required this.itemId,
    required this.side,
    required this.unitPrice,
    required this.quantity,
    required this.orders,
  });

  factory MarketOffer.fromJson(Map<String, Object?> json) => MarketOffer(
    itemId: _str(json['itemId']),
    side: _str(json['side']),
    unitPrice: _num(json['unitPrice']),
    quantity: _num(json['quantity']),
    orders: _num(json['orders']).toInt(),
  );

  final String itemId;
  final BazaarSide side;
  final num unitPrice;
  final num quantity;
  final int orders;

  bool get isBuy => side == bazaarBuy;

  Map<String, Object?> toJson() => <String, Object?>{
    'itemId': itemId,
    'side': side,
    'unitPrice': unitPrice,
    'quantity': quantity,
    'orders': orders,
  };
}

/// One line an item for the browse list: what it can be sold and bought for now.
class MarketSummary {
  const MarketSummary({
    required this.itemId,
    required this.bestBid,
    required this.bestAsk,
    required this.buyQuantity,
    required this.sellQuantity,
  });

  factory MarketSummary.fromJson(Map<String, Object?> json) => MarketSummary(
    itemId: _str(json['itemId']),
    bestBid: _num(json['bestBid']),
    bestAsk: _num(json['bestAsk']),
    buyQuantity: _num(json['buyQuantity']),
    sellQuantity: _num(json['sellQuantity']),
  );

  final String itemId;

  /// The most anybody is offering to pay, or 0 when nobody is.
  final num bestBid;

  /// The least anybody is asking, or 0 when nobody is selling.
  final num bestAsk;
  final num buyQuantity;
  final num sellQuantity;

  Map<String, Object?> toJson() => <String, Object?>{
    'itemId': itemId,
    'bestBid': bestBid,
    'bestAsk': bestAsk,
    'buyQuantity': buyQuantity,
    'sellQuantity': sellQuantity,
  };
}

/// One of the player's own completed trades.
class MarketTrade {
  const MarketTrade({
    required this.id,
    required this.itemId,
    required this.unitPrice,
    required this.quantity,
    required this.tax,
    required this.side,
    required this.createdAt,
    this.status = 'filled',
  });

  factory MarketTrade.fromJson(Map<String, Object?> json) => MarketTrade(
    id: _str(json['id']),
    itemId: _str(json['itemId']),
    unitPrice: _num(json['unitPrice']),
    quantity: _num(json['quantity']),
    tax: _num(json['tax']),
    side: _str(json['side']),
    createdAt: _str(json['createdAt']),
    status: _str(json['status']).isEmpty ? 'filled' : _str(json['status']),
  );

  final String id;
  final String itemId;

  /// What the resting order asked, which is what both sides dealt at.
  final num unitPrice;
  final num quantity;

  /// Taken from the seller. Zero on the buying side of the same trade.
  final num tax;

  /// Which side of it the player was on.
  final BazaarSide side;
  final String createdAt;

  /// `filled` after the offer closed by trading, or `cancelled`.
  final String status;

  bool get isBuy => side == bazaarBuy;

  bool get isCancelled => status == 'cancelled';

  num get total => unitPrice * quantity;

  /// Gold that changed hands for the player: paid out on a buy, taken in on a
  /// sale after tax.
  num get net => isBuy ? total : total - tax;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'itemId': itemId,
    'unitPrice': unitPrice,
    'quantity': quantity,
    'tax': tax,
    'side': side,
    'status': status,
    'createdAt': createdAt,
  };
}

const String bazaarCollectBought = 'bought';
const String bazaarCollectSold = 'sold';
const String bazaarCollectCancelled = 'cancelled';
const String bazaarCollectRefund = 'refund';

/// Something the exchange owes the player, waiting to be taken.
class MarketCollectEntry {
  const MarketCollectEntry({
    required this.id,
    required this.itemId,
    required this.quantity,
    required this.gold,
    required this.reason,
    required this.createdAt,
  });

  factory MarketCollectEntry.fromJson(Map<String, Object?> json) => MarketCollectEntry(
    id: _str(json['id']),
    itemId: json['itemId'] is String ? json['itemId']! as String : null,
    quantity: _num(json['quantity']),
    gold: _num(json['gold']),
    reason: _str(json['reason']),
    createdAt: _str(json['createdAt']),
  );

  final String id;

  /// Null when the entry is gold.
  final String? itemId;
  final num quantity;
  final num gold;

  /// `bought`, `sold`, `cancelled`, or `refund`.
  final String reason;
  final String createdAt;

  bool get isGold => itemId == null;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'itemId': itemId,
    'quantity': quantity,
    'gold': gold,
    'reason': reason,
    'createdAt': createdAt,
  };
}

/// What an item has been trading at.
class MarketPrice {
  const MarketPrice({
    required this.itemId,
    required this.averagePrice,
    required this.lastPrice,
    required this.volume,
    required this.trades,
  });

  factory MarketPrice.fromJson(Map<String, Object?> json) => MarketPrice(
    itemId: _str(json['itemId']),
    averagePrice: _num(json['averagePrice']),
    lastPrice: _num(json['lastPrice']),
    volume: _num(json['volume']),
    trades: _num(json['trades']),
  );

  final String itemId;

  /// The rolling average, weighted by how much each trade moved. One small deal
  /// barely shifts it, which is what stops a single silly price being a guide.
  final num averagePrice;
  final num lastPrice;
  final num volume;
  final num trades;

  Map<String, Object?> toJson() => <String, Object?>{
    'itemId': itemId,
    'averagePrice': averagePrice,
    'lastPrice': lastPrice,
    'volume': volume,
    'trades': trades,
  };
}

/// Everything the Bazaar screen draws, as one read.
class MarketSnapshot {
  const MarketSnapshot({
    this.orders = const <MarketOrder>[],
    this.offers = const <MarketOffer>[],
    this.market = const <MarketSummary>[],
    this.trades = const <MarketTrade>[],
    this.collect = const <MarketCollectEntry>[],
    this.prices = const <MarketPrice>[],
  });

  factory MarketSnapshot.fromJson(Map<String, Object?> json) => MarketSnapshot(
    orders: _rows(json['orders']).map(MarketOrder.fromJson).toList(),
    offers: _rows(json['offers']).map(MarketOffer.fromJson).toList(),
    market: _rows(json['market']).map(MarketSummary.fromJson).toList(),
    trades: _rows(json['trades']).map(MarketTrade.fromJson).toList(),
    collect: _rows(json['collect']).map(MarketCollectEntry.fromJson).toList(),
    prices: _rows(json['prices']).map(MarketPrice.fromJson).toList(),
  );

  /// The player's own open offers, at most [bazaarOfferSlots] of them.
  final List<MarketOrder> orders;

  /// Depth for whichever item was asked about, both sides.
  final List<MarketOffer> offers;

  /// One row an item that has anything on offer, for browsing.
  final List<MarketSummary> market;

  /// The player's own last [bazaarHistoryLength] trades, newest first.
  final List<MarketTrade> trades;
  final List<MarketCollectEntry> collect;
  final List<MarketPrice> prices;

  /// The book with nothing in it: local play, and signed-out play.
  static const MarketSnapshot empty = MarketSnapshot();

  int get slotsFree => bazaarOfferSlots - orders.length;

  /// Guide prices keyed by item, for a list that shows one against each row.
  Map<String, MarketPrice> get pricesByItem => <String, MarketPrice>{
    for (final price in prices) price.itemId: price,
  };

  /// Everything the box owes, item entries and gold entries together.
  num get collectGold => collect.fold<num>(0, (total, entry) => total + entry.gold);

  num get collectItems => collect.fold<num>(0, (total, entry) => total + entry.quantity);

  Map<String, Object?> toJson() => <String, Object?>{
    'orders': orders.map((row) => row.toJson()).toList(),
    'offers': offers.map((row) => row.toJson()).toList(),
    'market': market.map((row) => row.toJson()).toList(),
    'trades': trades.map((row) => row.toJson()).toList(),
    'collect': collect.map((row) => row.toJson()).toList(),
    'prices': prices.map((row) => row.toJson()).toList(),
  };
}

/// What placing, cancelling, or collecting did.
///
/// [save] is the copy the server wrote, not one the client worked out. An action
/// that returns one has already had the escrow taken or the box paid out, and
/// the client's job is to adopt it rather than to apply anything itself.
class MarketActionResult {
  const MarketActionResult.ok({this.save, this.message, this.order}) : reason = null;

  const MarketActionResult.failed(this.reason) : save = null, message = null, order = null;

  final PlayerSave? save;

  /// What to tell the player, when there is something worth saying.
  final String? message;
  final MarketOrder? order;
  final String? reason;

  bool get ok => reason == null;

  Map<String, Object?> toJson() => ok
      ? <String, Object?>{
          'ok': true,
          if (save != null) 'save': save!.toJson(),
          if (message != null) 'message': message,
          if (order != null) 'order': order!.toJson(),
        }
      : <String, Object?>{'ok': false, 'reason': reason};
}

/// One of the six offer boxes, filled or empty.
class MarketSlotView {
  const MarketSlotView({required this.slot, this.order});

  final int slot;
  final MarketOrder? order;

  bool get isEmpty => order == null;

  Map<String, Object?> toJson() => <String, Object?>{
    'slot': slot,
    if (order != null) 'order': order!.toJson(),
  };
}

/// The six boxes in slot order, so the screen draws the same shape either way.
List<MarketSlotView> bazaarSlotViews(List<MarketOrder> orders) {
  final bySlot = <int, MarketOrder>{
    for (final order in orders)
      if (order.slot >= 0 && order.slot < bazaarOfferSlots) order.slot: order,
  };
  return <MarketSlotView>[
    for (var slot = 0; slot < bazaarOfferSlots; slot += 1)
      MarketSlotView(slot: slot, order: bySlot[slot]),
  ];
}

/// Why an offer cannot be placed as described, or null when it can.
///
/// The server decides this again, against its own copy of the save. Checking it
/// here is so the keypad can refuse before the round trip, and so the reason
/// reads the same whichever side noticed.
String? bazaarOfferRefusal({
  required BazaarSide side,
  required num unitPrice,
  required num quantity,
  required int slotsFree,
}) {
  if (slotsFree <= 0) return bazaarNoSlots;
  if (side != bazaarBuy && side != bazaarSell) return 'Choose to buy or to sell.';
  final price = unitPrice.floor();
  final count = quantity.floor();
  if (price < 1) return 'Offer at least 1 gold an item.';
  if (count < 1) return 'Choose how many.';
  if (price * count > bazaarOfferValueCap) return bazaarOfferTooLarge;
  return null;
}

const String bazaarNoSlots = 'All six offer slots are in use.';

const String bazaarOfferTooLarge = 'An offer cannot be worth more than 1,000,000,000 gold.';

// --- What an offer costs a save ---------------------------------------------
//
// The server has its own copy of this arithmetic, in
// `supabase/functions/_shared/save_items.ts`, and its copy is the one that
// decides: it runs against the save the backend stores, which is the only one a
// player cannot edit. These are here so a keypad can cap itself and a refusal
// can be given before the round trip, and so the test stand-in for the exchange
// works the same way the real one does rather than approximately.

/// How much of [itemId] the bag holds in stacks the exchange will take.
///
/// The bank is deliberately not counted. Items have to be withdrawn before they
/// can be listed, and the server enforces that by only ever reading `inventory`.
num bazaarTradableOnHand(PlayerSave save, String itemId, [GameDatabase? db]) {
  var total = 0 as num;
  for (final stack in save.inventory) {
    if (stack.itemId != itemId) continue;
    if (bazaarStackRefusal(stack, db) != null) continue;
    total += stack.quantity.floor();
  }
  return total;
}

/// The save with [quantity] of [itemId] escrowed out of the bag, or null when
/// the bag does not hold that much in stacks the exchange will take.
PlayerSave? bazaarTakeItems(PlayerSave save, String itemId, num quantity, [GameDatabase? db]) {
  final want = quantity.floor();
  if (want <= 0) return null;
  if (bazaarTradableOnHand(save, itemId, db) < want) return null;

  var left = want;
  final kept = <InventoryStack>[];
  for (final stack in save.inventory) {
    if (left <= 0 || stack.itemId != itemId || bazaarStackRefusal(stack, db) != null) {
      kept.add(stack);
      continue;
    }
    final taken = left < stack.quantity.floor() ? left : stack.quantity.floor();
    left -= taken;
    final remaining = stack.quantity - taken;
    if (remaining > 0) kept.add(stack.copyWith(quantity: remaining));
  }
  if (left > 0) return null;
  return save.copyWith(inventory: kept);
}

/// The save with [quantity] of [itemId] put in, or null when it will not fit.
///
/// All or nothing: the collection box hands over a row at a time, and half a row
/// taken would need somewhere to remember the other half.
PlayerSave? bazaarGiveItems(PlayerSave save, String itemId, num quantity, [GameDatabase? db]) {
  final want = quantity.floor();
  if (want <= 0) return null;
  final added = addItemToInventoryExact(save, itemId, want, null, false, db);
  return added.ok ? added.save : null;
}

/// The save with [amount] gold escrowed, or null when the purse is short.
PlayerSave? bazaarTakeGold(PlayerSave save, num amount) {
  final want = amount.floor();
  if (want <= 0 || save.gold < want) return null;
  return save.copyWith(gold: save.gold - want);
}

/// The save with [amount] gold paid in, or null when it would break the ceiling
/// a cloud save is checked against.
PlayerSave? bazaarGiveGold(PlayerSave save, num amount) {
  final want = amount.floor();
  if (want <= 0) return null;
  if (save.gold + want > cloudSaveGoldCap) return null;
  return save.copyWith(gold: save.gold + want);
}

List<Map<String, Object?>> _rows(Object? value) {
  if (value is! List) return const <Map<String, Object?>>[];
  return <Map<String, Object?>>[
    for (final entry in value)
      if (entry is Map)
        <String, Object?>{for (final pair in entry.entries) pair.key.toString(): pair.value},
  ];
}

String _str(Object? value) => value is String ? value : (value?.toString() ?? '');

num _num(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? 0;
  return 0;
}
