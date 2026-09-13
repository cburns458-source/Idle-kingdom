import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

const num _nowMs = 1786568400000;
const String _ironOre = 'ITEM-0005';
const String _gold = 'ITEM-0001';

GameDatabase _database() => assertGameDatabaseShape(contentDatabaseJson());

PlayerSave _save(
  GameDatabase db, {
  List<InventoryStack> bag = const <InventoryStack>[],
  num gold = 0,
}) => createNewSave(db, _nowMs).copyWith(inventory: bag, gold: gold);

InventoryStack _stack(String itemId, num quantity, {String? enchantmentId, bool? favorite}) =>
    InventoryStack(
      itemId: itemId,
      quantity: quantity,
      enchantmentId: enchantmentId,
      favorite: favorite,
    );

MarketOrder _order({int slot = 0, num quantity = 10, num filled = 0}) => MarketOrder(
  id: 'o$slot',
  side: bazaarBuy,
  itemId: _ironOre,
  unitPrice: 30,
  quantity: quantity,
  filled: filled,
  goldEscrow: 30 * (quantity - filled),
  slot: slot,
  status: 'open',
  createdAt: '2026-09-13T00:00:00.000Z',
);

void main() {
  group('the tax', () {
    test('is 1% of the trade, and only above 100 gold an item', () {
      // The threshold is the price per item, so a big pile of something cheap
      // stays untaxed however much the offer is worth altogether.
      expect(bazaarTax(100, 10000), 0);
      expect(bazaarTaxApplies(100), isFalse);
      expect(bazaarTax(101, 1), 1);
      expect(bazaarTaxApplies(101), isTrue);
      expect(bazaarTax(500, 200), 1000);
    });

    test('rounds down, and comes off what the seller is paid', () {
      expect(bazaarTax(150, 1), 1);
      expect(bazaarSellerReceives(101, 1), 100);
      expect(bazaarSellerReceives(500, 200), 99000);
      expect(bazaarSellerReceives(50, 100), 5000);
    });

    test('ignores fractions of a price or a count', () {
      expect(bazaarTax(500.9, 10.9), bazaarTax(500, 10));
      expect(bazaarTax(500, 0), 0);
    });
  });

  group('what may be listed', () {
    test('refuses gold, enchanted stacks, and favourites, each for its own reason', () {
      final db = _database();
      expect(bazaarStackRefusal(_stack(_gold, 500), db), bazaarGoldNotTraded);
      expect(
        bazaarStackRefusal(_stack(_ironOre, 5, enchantmentId: 'ENCH-0001'), db),
        bazaarEnchantedNotTraded,
      );
      expect(bazaarStackRefusal(_stack(_ironOre, 5, favorite: true), db), bazaarFavoriteNotTraded);
      expect(bazaarStackRefusal(_stack(_ironOre, 0), db), bazaarNothingToSell);
      expect(bazaarStackRefusal(_stack(_ironOre, 5), db), isNull);
    });

    test('carries anything a shop would price, and nothing else', () {
      final db = _database();
      expect(bazaarItemTradable(db, _ironOre), isTrue);
      expect(bazaarItemTradable(db, _gold), isFalse);
      expect(bazaarItemTradable(db, 'ITEM-9999'), isFalse);
    });
  });

  group('what is on hand', () {
    test('counts the bag and not the bank, because listing needs a withdrawal', () {
      final db = _database();
      final save = _save(
        db,
        bag: <InventoryStack>[_stack(_ironOre, 40)],
      ).copyWith(bank: <InventoryStack>[_stack(_ironOre, 900)]);
      expect(bazaarTradableOnHand(save, _ironOre, db), 40);
    });

    test('leaves out the stacks the exchange will not take', () {
      final db = _database();
      final save = _save(
        db,
        bag: <InventoryStack>[
          _stack(_ironOre, 10),
          _stack(_ironOre, 5, favorite: true),
          _stack(_ironOre, 3, enchantmentId: 'ENCH-0001'),
          _stack(_ironOre, 7),
        ],
      );
      expect(bazaarTradableOnHand(save, _ironOre, db), 17);
    });
  });

  group('escrowing an offer', () {
    test('takes from the listable stacks and leaves the protected ones alone', () {
      final db = _database();
      final save = _save(
        db,
        bag: <InventoryStack>[
          _stack(_ironOre, 10),
          _stack(_ironOre, 5, favorite: true),
          _stack(_ironOre, 7),
        ],
      );
      final after = bazaarTakeItems(save, _ironOre, 15, db)!;
      expect(after.inventory.map((stack) => stack.quantity).toList(), <num>[5, 2]);
      expect(after.inventory.first.favorite, isTrue);
    });

    test('refuses rather than taking part of what was asked for', () {
      final db = _database();
      final save = _save(db, bag: <InventoryStack>[_stack(_ironOre, 9)]);
      expect(bazaarTakeItems(save, _ironOre, 10, db), isNull);
      expect(bazaarTakeItems(save, _ironOre, 0, db), isNull);
    });

    test('empties a stack out of the bag rather than leaving a zero behind', () {
      final db = _database();
      final save = _save(db, bag: <InventoryStack>[_stack(_ironOre, 10)]);
      expect(bazaarTakeItems(save, _ironOre, 10, db)!.inventory, isEmpty);
    });

    test('costs a buy offer its whole worth up front', () {
      final db = _database();
      final save = _save(db, gold: 1000);
      expect(bazaarTakeGold(save, 400)!.gold, 600);
      expect(bazaarTakeGold(save, 1001), isNull);
    });
  });

  group('paying the box out', () {
    test('merges into a stack already held', () {
      final db = _database();
      final save = _save(db, bag: <InventoryStack>[_stack(_ironOre, 10)]);
      expect(bazaarGiveItems(save, _ironOre, 25, db)!.inventory.single.quantity, 35);
    });

    test('will not pay out past the gold a save may hold', () {
      final db = _database();
      final save = _save(db, gold: cloudSaveGoldCap - 5);
      expect(bazaarGiveGold(save, 5)!.gold, cloudSaveGoldCap);
      expect(bazaarGiveGold(save, 6), isNull);
    });
  });

  group('the three slots', () {
    test('draw the same three boxes whatever is in them', () {
      final views = bazaarSlotViews(<MarketOrder>[_order(slot: 2)]);
      expect(views.map((view) => view.slot).toList(), <int>[0, 1, 2]);
      expect(views[0].isEmpty, isTrue);
      expect(views[2].order?.slot, 2);
    });

    test('ignore an order claiming a slot that does not exist', () {
      expect(bazaarSlotViews(<MarketOrder>[_order(slot: 7)]).every((view) => view.isEmpty), isTrue);
    });

    test('report how many are free, which is what refuses a fourth offer', () {
      final snapshot = MarketSnapshot(orders: <MarketOrder>[_order(slot: 0), _order(slot: 1)]);
      expect(snapshot.slotsFree, 1);
      expect(
        bazaarOfferRefusal(side: bazaarBuy, unitPrice: 5, quantity: 5, slotsFree: 0),
        bazaarNoSlots,
      );
      expect(bazaarOfferRefusal(side: bazaarBuy, unitPrice: 5, quantity: 5, slotsFree: 1), isNull);
    });
  });

  group('refusing an offer before the round trip', () {
    test('names the number that is wrong', () {
      expect(
        bazaarOfferRefusal(side: bazaarBuy, unitPrice: 0, quantity: 5, slotsFree: 3),
        'Offer at least 1 gold an item.',
      );
      expect(
        bazaarOfferRefusal(side: bazaarSell, unitPrice: 5, quantity: 0, slotsFree: 3),
        'Choose how many.',
      );
      expect(
        bazaarOfferRefusal(side: 'swap', unitPrice: 5, quantity: 5, slotsFree: 3),
        'Choose to buy or to sell.',
      );
    });

    test('caps an offer at the gold a save can hold, since a fill has to be paid', () {
      expect(
        bazaarOfferRefusal(
          side: bazaarBuy,
          unitPrice: 1000,
          quantity: bazaarOfferValueCap,
          slotsFree: 3,
        ),
        bazaarOfferTooLarge,
      );
      expect(bazaarOfferValueCap, cloudSaveGoldCap);
    });
  });

  group('an order', () {
    test('says how far along it is, for the bar across its box', () {
      final order = _order(quantity: 100, filled: 25);
      expect(order.remaining, 75);
      expect(order.progress, 0.25);
      expect(order.isPartlyFilled, isTrue);
      expect(_order(quantity: 100).isPartlyFilled, isFalse);
      expect(_order(quantity: 100, filled: 100).isPartlyFilled, isFalse);
    });

    test('survives a round trip through JSON', () {
      final order = _order(quantity: 40, filled: 10, slot: 1);
      expect(MarketOrder.fromJson(order.toJson()).toJson(), order.toJson());
    });
  });

  group('a trade', () {
    test('nets what the player actually gained or paid', () {
      const bought = MarketTrade(
        id: 't1',
        itemId: _ironOre,
        unitPrice: 500,
        quantity: 10,
        tax: 0,
        side: bazaarBuy,
        createdAt: '2026-09-13T00:00:00.000Z',
      );
      expect(bought.total, 5000);
      expect(bought.net, 5000);

      const sold = MarketTrade(
        id: 't2',
        itemId: _ironOre,
        unitPrice: 500,
        quantity: 10,
        tax: 50,
        side: bazaarSell,
        createdAt: '2026-09-13T00:00:00.000Z',
      );
      expect(sold.net, 4950);
      expect(sold.net, bazaarSellerReceives(500, 10));
    });
  });

  group('the snapshot', () {
    test('is empty for local and signed-out play', () {
      expect(MarketSnapshot.empty.orders, isEmpty);
      expect(MarketSnapshot.empty.slotsFree, bazaarOfferSlots);
      expect(MarketSnapshot.empty.collectGold, 0);
      expect(MarketSnapshot.empty.collectItems, 0);
    });

    test('reads back whatever the server sent, keys and all', () {
      final snapshot = MarketSnapshot(
        orders: <MarketOrder>[_order()],
        offers: const <MarketOffer>[
          MarketOffer(itemId: _ironOre, side: bazaarSell, unitPrice: 30, quantity: 90, orders: 2),
        ],
        market: const <MarketSummary>[
          MarketSummary(
            itemId: _ironOre,
            bestBid: 25,
            bestAsk: 30,
            buyQuantity: 10,
            sellQuantity: 90,
          ),
        ],
        collect: const <MarketCollectEntry>[
          MarketCollectEntry(
            id: 'c1',
            itemId: null,
            quantity: 0,
            gold: 400,
            reason: bazaarCollectRefund,
            createdAt: '2026-09-13T00:00:00.000Z',
          ),
        ],
        prices: const <MarketPrice>[
          MarketPrice(itemId: _ironOre, averagePrice: 28, lastPrice: 30, volume: 500, trades: 12),
        ],
      );
      final round = MarketSnapshot.fromJson(snapshot.toJson());
      expect(round.toJson(), snapshot.toJson());
      expect(round.collect.single.isGold, isTrue);
      expect(round.collectGold, 400);
      expect(round.pricesByItem[_ironOre]?.averagePrice, 28);
    });
  });
}
