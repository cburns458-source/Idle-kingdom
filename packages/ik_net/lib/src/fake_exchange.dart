import 'market.dart';
import 'remote.dart';
import 'remote_transport.dart';

/// The Bazaar exchange held in memory, standing in for the hosted one.
///
/// It mirrors the two files that actually run: `supabase/functions/bazaar` for
/// the escrow and the refusals, and the routines in
/// `supabase/migrations/024_bazaar_market.sql` for the book. The same escrow out
/// of the stored save, the same price-and-then-time matching with the resting
/// order setting the price, the same 1% above 100 gold an item, the same
/// collection box. What it deliberately does not model is concurrency, which is
/// the one thing the SQL cannot be checked for from here; the scripts under
/// `supabase/tests/` cover that against a real Postgres.
///
/// It reads and writes the same save rows the transport stores, because that is
/// the whole point of the exchange: an offer costs the copy of the save the
/// backend holds, not the one the device is holding.
class FakeExchange {
  FakeExchange({required this.saves, required this.stamp});

  /// The transport's `player_saves` rows, held by reference so an offer taken
  /// out of a save is visible to the next read the way the real one would be.
  final List<RemoteRow> saves;

  /// A fresh timestamp, so `order by created_at` means something.
  final String Function() stamp;

  final List<FakeExchangeOrder> orders = <FakeExchangeOrder>[];
  final List<FakeExchangeFill> fills = <FakeExchangeFill>[];
  final List<FakeExchangeCollect> box = <FakeExchangeCollect>[];
  final Map<String, FakeExchangePrice> prices = <String, FakeExchangePrice>{};

  int _ids = 0;

  String _nextId(String prefix) => '${prefix}_${(_ids += 1).toString().padLeft(4, '0')}';

  /// Answers the `bazaar` function the way the deployed one does, refusals and
  /// all: a reason the player is meant to read comes back as a successful call
  /// carrying `error`, because `functions.invoke` throws on a 4xx and hands the
  /// caller the body as a string rather than the reason inside it.
  RemoteInvokeResult call({
    required String userId,
    required String username,
    required RemoteRow body,
  }) {
    final action = body['action'];
    switch (action) {
      case 'read':
        return RemoteInvokeResult.ok(_read(userId, body['itemId']));
      case 'place':
        return _place(userId, username, body);
      case 'cancel':
        return _cancel(userId, body['orderId']);
      case 'collect':
        return _collect(userId);
      default:
        return _refused('Unknown Bazaar action.');
    }
  }

  static RemoteInvokeResult _refused(String message) =>
      RemoteInvokeResult.ok(<String, Object?>{'ok': false, 'error': message});

  // --- Reads -----------------------------------------------------------------

  RemoteRow _read(String userId, Object? itemId) {
    final own = orders.where((order) => order.userId == userId && order.isOpen).toList()
      ..sort((a, b) => a.slot.compareTo(b.slot));
    final resting = orders.where((order) => order.isOpen && order.remaining > 0).toList();
    final finishedIds = <String>{
      for (final order in orders)
        if (order.userId == userId && !order.isOpen) order.id,
    };
    final mine = fills
        .where((fill) {
          final orderId = fill.buyerId == userId ? fill.buyOrderId : fill.sellOrderId;
          return (fill.buyerId == userId || fill.sellerId == userId) &&
              finishedIds.contains(orderId);
        })
        .map((fill) => fill.toJson(userId))
        .toList();
    final cancelled = orders
        .where(
          (order) => order.userId == userId && order.status == 'cancelled' && order.filled == 0,
        )
        .map((order) => order.toCancelTradeJson())
        .toList();
    final history = <RemoteRow>[...mine, ...cancelled]
      ..sort((a, b) => (b['createdAt']! as String).compareTo(a['createdAt']! as String));
    final waiting = box.where((entry) => entry.userId == userId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final guides = prices.values.toList()..sort((a, b) => b.volume.compareTo(a.volume));

    return <String, Object?>{
      'ok': true,
      'orders': own.map((order) => order.toJson()).toList(),
      'offers': _depth(resting, itemId is String ? itemId : null),
      'market': _summaries(resting),
      'trades': history.take(bazaarHistoryLength).toList(),
      'collect': waiting.map((entry) => entry.toJson()).toList(),
      'prices': guides.map((price) => price.toJson()).toList(),
    };
  }

  /// Resting quantity at each price on both sides of one item's book, which is
  /// all a client is told: who is selling is nobody's business.
  List<RemoteRow> _depth(List<FakeExchangeOrder> resting, String? itemId) {
    if (itemId == null) return const <RemoteRow>[];
    final totals = <String, RemoteRow>{};
    for (final order in resting) {
      if (order.itemId != itemId) continue;
      final key = '${order.side}:${order.unitPrice}';
      final held = totals[key];
      if (held == null) {
        totals[key] = <String, Object?>{
          'itemId': itemId,
          'side': order.side,
          'unitPrice': order.unitPrice,
          'quantity': order.remaining,
          'orders': 1,
        };
      } else {
        held['quantity'] = (held['quantity']! as int) + order.remaining;
        held['orders'] = (held['orders']! as int) + 1;
      }
    }
    return totals.values.toList()..sort((a, b) {
      if (a['side'] != b['side']) return (a['side']! as String).compareTo(b['side']! as String);
      return (b['unitPrice']! as int).compareTo(a['unitPrice']! as int);
    });
  }

  List<RemoteRow> _summaries(List<FakeExchangeOrder> resting) {
    final rows = <String, RemoteRow>{};
    for (final order in resting) {
      final held = rows.putIfAbsent(
        order.itemId,
        () => <String, Object?>{
          'itemId': order.itemId,
          'bestBid': 0,
          'bestAsk': 0,
          'buyQuantity': 0,
          'sellQuantity': 0,
        },
      );
      if (order.isBuy) {
        held['buyQuantity'] = (held['buyQuantity']! as int) + order.remaining;
        final best = held['bestBid']! as int;
        held['bestBid'] = order.unitPrice > best ? order.unitPrice : best;
      } else {
        held['sellQuantity'] = (held['sellQuantity']! as int) + order.remaining;
        final best = held['bestAsk']! as int;
        held['bestAsk'] = best == 0 || order.unitPrice < best ? order.unitPrice : best;
      }
    }
    return rows.values.toList()
      ..sort((a, b) => (a['itemId']! as String).compareTo(b['itemId']! as String));
  }

  // --- Placing ---------------------------------------------------------------

  RemoteInvokeResult _place(String userId, String username, RemoteRow body) {
    final side = body['side'];
    if (side != bazaarBuy && side != bazaarSell) return _refused('Choose to buy or to sell.');
    final itemId = body['itemId'];
    if (itemId is! String || !fakeExchangeItemId.hasMatch(itemId)) {
      return _refused('That is not a tradable item.');
    }
    final unitPrice = _whole(body['unitPrice']);
    final quantity = _whole(body['quantity']);
    if (unitPrice == null || unitPrice < 1) {
      return _refused('Choose a price of at least 1 gold an item.');
    }
    if (quantity == null || quantity < 1) return _refused('Choose how many.');
    if (unitPrice * quantity > bazaarOfferValueCap) return _refused(bazaarOfferTooLarge);

    final row = _saveRow(userId);
    if (row == null) return _refused('Play a little and let the game save before trading.');
    final stored = _payload(row);
    if (stored == null) return _refused('Play a little and let the game save before trading.');

    if (orders.where((order) => order.userId == userId && order.isOpen).length >=
        bazaarOfferSlots) {
      return _refused(bazaarNoSlots);
    }

    final Map<String, Object?>? escrowed;
    if (side == bazaarSell) {
      escrowed = fakeExchangeTakeItems(stored, itemId, quantity);
      if (escrowed == null) {
        final held = fakeExchangeTradable(stored, itemId);
        return _refused('You are carrying $held of those. Withdraw more from the bank first.');
      }
    } else {
      escrowed = fakeExchangeTakeGold(stored, unitPrice * quantity);
      if (escrowed == null) {
        return _refused('That offer costs ${unitPrice * quantity} gold.');
      }
    }

    final order = FakeExchangeOrder(
      id: _nextId('bzo'),
      userId: userId,
      username: username,
      side: side as String,
      itemId: itemId,
      unitPrice: unitPrice,
      quantity: quantity,
      goldEscrow: side == bazaarBuy ? unitPrice * quantity : 0,
      slot: _freeSlot(userId),
      createdAt: stamp(),
    );
    orders.add(order);

    final traded = _match(order);
    _writeSave(row, escrowed);

    return RemoteInvokeResult.ok(<String, Object?>{
      'ok': true,
      'save': escrowed,
      'order': order.toJson(),
      'traded': traded,
      'message': _placedMessage(order, traded),
    });
  }

  int _freeSlot(String userId) {
    final used = orders
        .where((order) => order.userId == userId && order.isOpen)
        .map((order) => order.slot)
        .toSet();
    for (var slot = 0; slot < bazaarOfferSlots; slot += 1) {
      if (!used.contains(slot)) return slot;
    }
    return 0;
  }

  /// Fills the incoming order against the book, best price first and oldest
  /// first at the same price. The resting order names the price, which is what
  /// makes an overpriced buy refund and an underpriced sell paid properly.
  int _match(FakeExchangeOrder incoming) {
    final book =
        orders
            .where(
              (order) =>
                  order.isOpen &&
                  order.id != incoming.id &&
                  order.itemId == incoming.itemId &&
                  order.userId != incoming.userId &&
                  order.isBuy != incoming.isBuy &&
                  (incoming.isBuy
                      ? order.unitPrice <= incoming.unitPrice
                      : order.unitPrice >= incoming.unitPrice),
            )
            .toList()
          ..sort((a, b) {
            final byPrice = incoming.isBuy
                ? a.unitPrice.compareTo(b.unitPrice)
                : b.unitPrice.compareTo(a.unitPrice);
            return byPrice != 0 ? byPrice : a.createdAt.compareTo(b.createdAt);
          });

    var refund = 0;
    for (final resting in book) {
      if (incoming.remaining <= 0) break;
      final quantity = incoming.remaining < resting.remaining
          ? incoming.remaining
          : resting.remaining;
      if (quantity <= 0) continue;
      final price = resting.unitPrice;
      final tax = bazaarTax(price, quantity).toInt();
      final buyer = incoming.isBuy ? incoming : resting;
      final seller = incoming.isBuy ? resting : incoming;

      _addBox(
        FakeExchangeCollect(
          id: _nextId('bzc'),
          userId: buyer.userId,
          itemId: incoming.itemId,
          quantity: quantity,
          gold: 0,
          reason: bazaarCollectBought,
          createdAt: stamp(),
        ),
      );
      _addBox(
        FakeExchangeCollect(
          id: _nextId('bzc'),
          userId: seller.userId,
          itemId: null,
          quantity: 0,
          gold: price * quantity - tax,
          reason: bazaarCollectSold,
          createdAt: stamp(),
        ),
      );
      fills.add(
        FakeExchangeFill(
          id: _nextId('bzf'),
          itemId: incoming.itemId,
          unitPrice: price,
          quantity: quantity,
          tax: tax,
          buyerId: buyer.userId,
          sellerId: seller.userId,
          buyOrderId: buyer.id,
          sellOrderId: seller.id,
          createdAt: stamp(),
        ),
      );
      if (incoming.isBuy) refund += (incoming.unitPrice - price) * quantity;

      resting.filled += quantity;
      if (resting.isBuy) resting.goldEscrow -= price * quantity;
      if (resting.remaining <= 0) {
        resting.status = 'filled';
        resting.updatedAt = stamp();
      }
      incoming.filled += quantity;
      _notePrice(incoming.itemId, price, quantity);
    }

    if (refund > 0) {
      _addBox(
        FakeExchangeCollect(
          id: _nextId('bzc'),
          userId: incoming.userId,
          itemId: null,
          quantity: 0,
          gold: refund,
          reason: bazaarCollectRefund,
          createdAt: stamp(),
        ),
      );
    }
    incoming.goldEscrow = incoming.isBuy ? incoming.unitPrice * incoming.remaining : 0;
    if (incoming.remaining <= 0) {
      incoming.status = 'filled';
      incoming.updatedAt = stamp();
    }
    return incoming.filled;
  }

  void _addBox(FakeExchangeCollect entry) {
    if (entry.itemId == null && entry.gold <= 0) return;
    if (entry.itemId != null && entry.quantity <= 0) return;
    box.add(entry);
  }

  /// Quantity-weighted, so one small deal at a silly price barely moves a guide.
  void _notePrice(String itemId, int unitPrice, int quantity) {
    final held = prices[itemId];
    if (held == null) {
      prices[itemId] = FakeExchangePrice(
        itemId: itemId,
        averagePrice: unitPrice.toDouble(),
        lastPrice: unitPrice,
        volume: quantity,
        trades: 1,
      );
      return;
    }
    held.averagePrice += (unitPrice - held.averagePrice) * (quantity / (quantity + 100));
    held.lastPrice = unitPrice;
    held.volume += quantity;
    held.trades += 1;
  }

  String _placedMessage(FakeExchangeOrder order, int traded) {
    final verb = order.isBuy ? 'Buying' : 'Selling';
    if (traded <= 0) return '$verb offer placed.';
    if (order.status == 'filled') {
      return order.isBuy
          ? 'Bought at once. Collect it from the box.'
          : 'Sold at once. Collect the gold from the box.';
    }
    return '$verb offer placed; $traded traded straight away.';
  }

  // --- Cancelling ------------------------------------------------------------

  RemoteInvokeResult _cancel(String userId, Object? orderId) {
    if (orderId is! String || orderId.isEmpty) return _refused('Choose an offer to cancel.');
    FakeExchangeOrder? order;
    for (final candidate in orders) {
      if (candidate.id == orderId && candidate.userId == userId) order = candidate;
    }
    if (order == null) return _refused('That offer is not yours.');
    if (!order.isOpen) return _refused('That offer has already closed.');

    final remaining = order.remaining;
    final gold = order.isBuy ? order.goldEscrow : 0;
    if (!order.isBuy && remaining > 0) {
      _addBox(
        FakeExchangeCollect(
          id: _nextId('bzc'),
          userId: userId,
          itemId: order.itemId,
          quantity: remaining,
          gold: 0,
          reason: bazaarCollectCancelled,
          createdAt: stamp(),
        ),
      );
    } else if (gold > 0) {
      _addBox(
        FakeExchangeCollect(
          id: _nextId('bzc'),
          userId: userId,
          itemId: null,
          quantity: 0,
          gold: gold,
          reason: bazaarCollectCancelled,
          createdAt: stamp(),
        ),
      );
    }
    order.status = 'cancelled';
    order.goldEscrow = 0;
    order.updatedAt = stamp();

    return RemoteInvokeResult.ok(<String, Object?>{
      'ok': true,
      'order': order.toJson(),
      'returnedQuantity': order.isBuy ? 0 : remaining,
      'returnedGold': gold,
      'message': remaining > 0 || gold > 0
          ? 'Offer cancelled. What was left is in the collection box.'
          : 'Offer cancelled.',
    });
  }

  // --- Collecting ------------------------------------------------------------

  RemoteInvokeResult _collect(String userId) {
    final row = _saveRow(userId);
    if (row == null) return _refused('Play a little and let the game save before trading.');
    final stored = _payload(row);
    if (stored == null) return _refused('Play a little and let the game save before trading.');

    final waiting = box.where((entry) => entry.userId == userId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (waiting.isEmpty) return _refused(bazaarEmptyCollection);

    var payload = stored;
    final taken = <FakeExchangeCollect>[];
    var items = 0;
    var gold = 0;
    var left = 0;
    for (final entry in waiting) {
      final applied = entry.isGold
          ? fakeExchangeGiveGold(payload, entry.gold)
          : fakeExchangeGiveItems(payload, entry.itemId!, entry.quantity);
      if (applied == null) {
        left += 1;
        continue;
      }
      payload = applied;
      taken.add(entry);
      if (entry.isGold) {
        gold += entry.gold;
      } else {
        items += entry.quantity;
      }
    }
    if (taken.isEmpty) return _refused('Your bag is full. Make room and collect again.');

    box.removeWhere(taken.contains);
    _writeSave(row, payload);

    return RemoteInvokeResult.ok(<String, Object?>{
      'ok': true,
      'save': payload,
      'items': items,
      'gold': gold,
      'left': left,
      'message': _collectedMessage(items, gold, left),
    });
  }

  String _collectedMessage(int items, int gold, int left) {
    final parts = <String>[
      if (items > 0) '$items item${items == 1 ? '' : 's'}',
      if (gold > 0) '$gold gold',
    ];
    final took = parts.isEmpty ? 'Collected.' : 'Collected ${parts.join(' and ')}.';
    return left > 0 ? '$took $left more would not fit.' : took;
  }

  // --- The stored save -------------------------------------------------------

  RemoteRow? _saveRow(String userId) {
    for (final row in saves) {
      if (row['user_id'] == userId) return row;
    }
    return null;
  }

  Map<String, Object?>? _payload(RemoteRow row) {
    final payload = row['payload'];
    if (payload is! Map) return null;
    return <String, Object?>{for (final pair in payload.entries) pair.key.toString(): pair.value};
  }

  void _writeSave(RemoteRow row, Map<String, Object?> payload) {
    final at = stamp();
    row['payload'] = <String, Object?>{...payload, 'updatedAt': at};
    row['updated_at'] = at;
  }

  static int? _whole(Object? value) {
    final parsed = value is num ? value : num.tryParse('$value');
    if (parsed == null || !parsed.isFinite) return null;
    return parsed.floor();
  }
}

/// Item ids as the game database writes them, matching the server's own check.
final RegExp fakeExchangeItemId = RegExp(r'^ITEM-\d{3,6}$');

/// One offer on the book.
class FakeExchangeOrder {
  FakeExchangeOrder({
    required this.id,
    required this.userId,
    required this.username,
    required this.side,
    required this.itemId,
    required this.unitPrice,
    required this.quantity,
    required this.goldEscrow,
    required this.slot,
    required this.createdAt,
    String? updatedAt,
    this.filled = 0,
    this.status = 'open',
  }) : updatedAt = updatedAt ?? createdAt;

  final String id;
  final String userId;
  final String username;
  final String side;
  final String itemId;
  final int unitPrice;
  final int quantity;
  final String createdAt;
  String updatedAt;

  int filled;
  int goldEscrow;
  int slot;
  String status;

  bool get isBuy => side == bazaarBuy;

  bool get isOpen => status == 'open';

  int get remaining => quantity - filled;

  RemoteRow toJson() => <String, Object?>{
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

  RemoteRow toCancelTradeJson() => <String, Object?>{
    'id': id,
    'itemId': itemId,
    'unitPrice': unitPrice,
    'quantity': quantity,
    'tax': 0,
    'side': side,
    'status': 'cancelled',
    'createdAt': updatedAt,
  };
}

/// One completed trade.
class FakeExchangeFill {
  FakeExchangeFill({
    required this.id,
    required this.itemId,
    required this.unitPrice,
    required this.quantity,
    required this.tax,
    required this.buyerId,
    required this.sellerId,
    required this.buyOrderId,
    required this.sellOrderId,
    required this.createdAt,
  });

  final String id;
  final String itemId;
  final int unitPrice;
  final int quantity;
  final int tax;
  final String buyerId;
  final String sellerId;
  final String buyOrderId;
  final String sellOrderId;
  final String createdAt;

  RemoteRow toJson(String userId) => <String, Object?>{
    'id': id,
    'itemId': itemId,
    'unitPrice': unitPrice,
    'quantity': quantity,
    'tax': tax,
    'side': buyerId == userId ? bazaarBuy : bazaarSell,
    'status': 'filled',
    'createdAt': createdAt,
  };
}

/// One thing the exchange owes a player.
class FakeExchangeCollect {
  FakeExchangeCollect({
    required this.id,
    required this.userId,
    required this.itemId,
    required this.quantity,
    required this.gold,
    required this.reason,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String? itemId;
  final int quantity;
  final int gold;
  final String reason;
  final String createdAt;

  bool get isGold => itemId == null;

  RemoteRow toJson() => <String, Object?>{
    'id': id,
    'itemId': itemId,
    'quantity': quantity,
    'gold': gold,
    'reason': reason,
    'createdAt': createdAt,
  };
}

/// An item's guide price.
class FakeExchangePrice {
  FakeExchangePrice({
    required this.itemId,
    required this.averagePrice,
    required this.lastPrice,
    required this.volume,
    required this.trades,
  });

  final String itemId;
  double averagePrice;
  int lastPrice;
  int volume;
  int trades;

  RemoteRow toJson() => <String, Object?>{
    'itemId': itemId,
    'averagePrice': averagePrice.round(),
    'lastPrice': lastPrice,
    'volume': volume,
    'trades': trades,
  };
}

// --- Inventory arithmetic on a stored payload --------------------------------
//
// The same handful of operations as `supabase/functions/_shared/save_items.ts`,
// against the same shape: the save as it is stored, not a parsed one. Kept here
// rather than reusing the typed helpers in `market.dart` on purpose — the server
// works on raw JSON, and a stand-in that parsed first would not notice a field
// the real one drops.

const int _fakeSlotLimit = 180;
const String _fakeGoldItemId = 'ITEM-0001';

List<Map<String, Object?>> fakeExchangeInventory(Map<String, Object?> payload) {
  final raw = payload['inventory'];
  if (raw is! List) return <Map<String, Object?>>[];
  return <Map<String, Object?>>[
    for (final entry in raw)
      if (entry is Map && entry['itemId'] is String && entry['quantity'] is num)
        <String, Object?>{for (final pair in entry.entries) pair.key.toString(): pair.value},
  ];
}

int fakeExchangeGold(Map<String, Object?> payload) {
  final gold = payload['gold'];
  return gold is num && gold.isFinite ? gold.floor() : 0;
}

/// Whether a stack may be listed: not gold, not enchanted, not favourited.
bool fakeExchangeTradableStack(Map<String, Object?> stack) {
  if (stack['itemId'] == _fakeGoldItemId) return false;
  final enchantment = stack['enchantmentId'];
  if (enchantment is String && enchantment.trim().isNotEmpty) return false;
  if (stack['favorite'] == true) return false;
  return (stack['quantity']! as num) > 0;
}

int fakeExchangeTradable(Map<String, Object?> payload, String itemId) {
  var total = 0;
  for (final stack in fakeExchangeInventory(payload)) {
    if (stack['itemId'] == itemId && fakeExchangeTradableStack(stack)) {
      total += (stack['quantity']! as num).floor();
    }
  }
  return total;
}

Map<String, Object?>? fakeExchangeTakeItems(
  Map<String, Object?> payload,
  String itemId,
  int quantity,
) {
  if (quantity <= 0) return null;
  if (fakeExchangeTradable(payload, itemId) < quantity) return null;

  var left = quantity;
  final kept = <Map<String, Object?>>[];
  for (final stack in fakeExchangeInventory(payload)) {
    if (left <= 0 || stack['itemId'] != itemId || !fakeExchangeTradableStack(stack)) {
      kept.add(stack);
      continue;
    }
    final held = (stack['quantity']! as num).floor();
    final taken = left < held ? left : held;
    left -= taken;
    final remaining = (stack['quantity']! as num) - taken;
    if (remaining > 0) kept.add(<String, Object?>{...stack, 'quantity': remaining});
  }
  if (left > 0) return null;
  return <String, Object?>{...payload, 'inventory': kept};
}

/// All or nothing: the box hands over a row at a time, and half a row taken
/// would need somewhere to remember the other half.
Map<String, Object?>? fakeExchangeGiveItems(
  Map<String, Object?> payload,
  String itemId,
  int quantity,
) {
  if (quantity <= 0) return null;
  final inventory = fakeExchangeInventory(payload);
  var index = -1;
  for (var at = 0; at < inventory.length; at += 1) {
    final stack = inventory[at];
    if (stack['itemId'] != itemId) continue;
    final enchantment = stack['enchantmentId'];
    if (enchantment is String && enchantment.trim().isNotEmpty) continue;
    if (stack['favorite'] == true) {
      index = at;
      break;
    }
    if (index < 0) index = at;
  }
  if (index < 0) {
    if (inventory.length >= _fakeSlotLimit) return null;
    return <String, Object?>{
      ...payload,
      'inventory': <Map<String, Object?>>[
        ...inventory,
        <String, Object?>{'itemId': itemId, 'quantity': quantity},
      ],
    };
  }
  final next = <Map<String, Object?>>[...inventory];
  next[index] = <String, Object?>{
    ...inventory[index],
    'quantity': (inventory[index]['quantity']! as num) + quantity,
  };
  return <String, Object?>{...payload, 'inventory': next};
}

Map<String, Object?>? fakeExchangeTakeGold(Map<String, Object?> payload, int amount) {
  if (amount <= 0) return null;
  final gold = fakeExchangeGold(payload);
  if (gold < amount) return null;
  return <String, Object?>{...payload, 'gold': gold - amount};
}

Map<String, Object?>? fakeExchangeGiveGold(Map<String, Object?> payload, int amount) {
  if (amount <= 0) return null;
  final gold = fakeExchangeGold(payload);
  if (gold + amount > bazaarOfferValueCap) return null;
  return <String, Object?>{...payload, 'gold': gold + amount};
}
