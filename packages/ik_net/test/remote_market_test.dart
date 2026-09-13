// The Bazaar through the service, against an exchange held in memory.
//
// The stand-in mirrors `supabase/functions/bazaar` and the routines in
// `supabase/migrations/024_bazaar_market.sql`, so what these tests pin down is
// the agreement between the two: an offer costs the stored save, a fill lands in
// the collection box rather than in a bag, the resting order names the price,
// and the client adopts whatever save comes back rather than working one out.
// The SQL itself is exercised against a real Postgres by `supabase/tests/run.sh`.

import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';
import 'package:test/test.dart';

const num _nowMs = 1786568400000;
const String _ironOre = 'ITEM-0005';
const String _titaniumOre = 'ITEM-0009';

GameDatabase _database() => assertGameDatabaseShape(contentDatabaseJson());

/// The project every trader connects to.
///
/// Stamped well before the client clock on purpose: the exchange writes the save
/// as the server would, and a stored save stamped after the client's now looks
/// to `pushSave` like somebody else's newer copy.
FakeTransport _project() => FakeTransport(startIso: '2026-01-01T00:00:00.000Z');

RemoteMultiplayerService _service(FakeTransport connection) {
  var counter = 0;
  return RemoteMultiplayerService(
    transport: connection,
    storage: MemorySaveStorage(),
    ports: LocalBackendPorts(
      nowMs: () => _nowMs,
      newId: (prefix) => '${prefix}_${(counter += 1).toString().padLeft(4, '0')}',
    ),
  );
}

/// A trader on their own client, with a save already stored.
///
/// The stored save is the one that matters: it is what the exchange escrows an
/// offer out of, and the only copy a player cannot edit.
Future<RemoteMultiplayerService> _trader(
  FakeTransport project,
  GameDatabase db,
  String email,
  String name, {
  List<InventoryStack> bag = const <InventoryStack>[],
  num gold = 0,
}) async {
  final service = _service(FakeTransport.joining(project));
  final created = await service.signUp(email, name, 'secret');
  expect(created.ok, isTrue, reason: created.reason);
  final pushed = await service.pushSave(db, _save(db, bag: bag, gold: gold));
  expect(pushed.ok, isTrue, reason: pushed.reason);
  return service;
}

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

/// The save the backend is holding, which is the only one that decides anything.
PlayerSave _stored(FakeTransport project, RemoteMultiplayerService service) {
  final row = project.tables[RemoteTables.saves]!.firstWhere(
    (row) => row['user_id'] == service.session!.userId,
  );
  return PlayerSave.fromJson(row['payload']! as Map<String, Object?>);
}

void main() {
  group('reading the book', () {
    test('is empty in local play, where there is nobody to trade with', () async {
      final local = LocalMultiplayerService(
        storage: MemorySaveStorage(),
        ports: LocalBackendPorts(nowMs: () => _nowMs, newId: (prefix) => prefix),
      );
      expect((await local.bazaarMarket()).orders, isEmpty);
      expect(
        (await local.placeBazaarOffer(
          _database(),
          _save(_database()),
          side: bazaarBuy,
          itemId: _ironOre,
          unitPrice: 10,
          quantity: 10,
        )).reason,
        bazaarHostedOnly,
      );
      expect((await local.cancelBazaarOffer('o1')).reason, bazaarHostedOnly);
    });

    test('is empty while signed out, and never asks the server', () async {
      final project = _project();
      final service = _service(project);
      expect((await service.bazaarMarket()).offers, isEmpty);
      expect(project.calls, isNot(contains('invoke:$remoteBazaarMarketFunction')));
      expect((await service.cancelBazaarOffer('o1')).reason, bazaarSignInToTrade);
    });

    test('shows depth for the item asked about and a summary of everything open', () async {
      final project = _project();
      final db = _database();
      final seller = await _trader(
        project,
        db,
        'seller@example.com',
        'Seller',
        bag: <InventoryStack>[_stack(_ironOre, 100), _stack(_titaniumOre, 10)],
      );
      expect(
        (await seller.placeBazaarOffer(
          db,
          _stored(project, seller),
          side: bazaarSell,
          itemId: _ironOre,
          unitPrice: 30,
          quantity: 60,
        )).ok,
        isTrue,
      );
      expect(
        (await seller.placeBazaarOffer(
          db,
          _stored(project, seller),
          side: bazaarSell,
          itemId: _titaniumOre,
          unitPrice: 300,
          quantity: 10,
        )).ok,
        isTrue,
      );

      final book = await seller.bazaarMarket(itemId: _ironOre);
      expect(book.offers.single.unitPrice, 30);
      expect(book.offers.single.quantity, 60);
      expect(book.market.map((row) => row.itemId).toList(), <String>[_ironOre, _titaniumOre]);
      expect(book.market.first.bestAsk, 30);
      expect(book.market.first.bestBid, 0);

      // Depth is only sent for the item asked about, so browsing costs one row
      // an item rather than the whole book.
      expect((await seller.bazaarMarket()).offers, isEmpty);
    });
  });

  group('placing an offer', () {
    test('takes the items out of the stored save, not the one on the device', () async {
      final project = _project();
      final db = _database();
      final seller = await _trader(
        project,
        db,
        'seller@example.com',
        'Seller',
        bag: <InventoryStack>[_stack(_ironOre, 100)],
      );

      // A device claiming a thousand does not get to list a thousand: the push
      // that precedes the offer is soft-validated, and the escrow is worked out
      // against what the backend then holds.
      final placed = await seller.placeBazaarOffer(
        db,
        _stored(project, seller),
        side: bazaarSell,
        itemId: _ironOre,
        unitPrice: 30,
        quantity: 60,
      );
      expect(placed.ok, isTrue, reason: placed.reason);
      expect(placed.save!.inventory.single.quantity, 40);
      expect(_stored(project, seller).inventory.single.quantity, 40);
      expect(placed.order!.slot, 0);
      expect(placed.order!.status, 'open');
      expect(placed.message, 'Selling offer placed.');
    });

    test('refuses more than the bag holds and says what is on hand', () async {
      final project = _project();
      final db = _database();
      final seller = await _trader(
        project,
        db,
        'seller@example.com',
        'Seller',
        bag: <InventoryStack>[_stack(_ironOre, 40)],
      );
      final refused = await seller.placeBazaarOffer(
        db,
        _stored(project, seller),
        side: bazaarSell,
        itemId: _ironOre,
        unitPrice: 30,
        quantity: 60,
      );
      expect(refused.ok, isFalse);
      expect(refused.reason, contains('carrying 40'));
      expect(_stored(project, seller).inventory.single.quantity, 40);
    });

    test('will not list a favourited or enchanted stack even to make up the count', () async {
      final project = _project();
      final db = _database();
      final seller = await _trader(
        project,
        db,
        'seller@example.com',
        'Seller',
        bag: <InventoryStack>[
          _stack(_ironOre, 10),
          _stack(_ironOre, 20, favorite: true),
          _stack(_ironOre, 5, enchantmentId: 'ENCH-0001'),
        ],
      );
      final refused = await seller.placeBazaarOffer(
        db,
        _stored(project, seller),
        side: bazaarSell,
        itemId: _ironOre,
        unitPrice: 30,
        quantity: 20,
      );
      expect(refused.ok, isFalse);
      expect(_stored(project, seller).inventory, hasLength(3));

      final allowed = await seller.placeBazaarOffer(
        db,
        _stored(project, seller),
        side: bazaarSell,
        itemId: _ironOre,
        unitPrice: 30,
        quantity: 10,
      );
      expect(allowed.ok, isTrue, reason: allowed.reason);
      expect(allowed.save!.inventory, hasLength(2));
      expect(allowed.save!.inventory.first.favorite, isTrue);
    });

    test('costs a buy offer its whole worth up front, and refuses a short purse', () async {
      final project = _project();
      final db = _database();
      final buyer = await _trader(project, db, 'buyer@example.com', 'Buyer', gold: 5000);

      final tooDear = await buyer.placeBazaarOffer(
        db,
        _stored(project, buyer),
        side: bazaarBuy,
        itemId: _ironOre,
        unitPrice: 100,
        quantity: 100,
      );
      expect(tooDear.reason, 'That offer costs 10000 gold.');
      expect(_stored(project, buyer).gold, 5000);

      final placed = await buyer.placeBazaarOffer(
        db,
        _stored(project, buyer),
        side: bazaarBuy,
        itemId: _ironOre,
        unitPrice: 40,
        quantity: 100,
      );
      expect(placed.ok, isTrue, reason: placed.reason);
      expect(placed.save!.gold, 1000);
      expect(placed.order!.goldEscrow, 4000);
    });

    test('fills three slots and then refuses a fourth', () async {
      final project = _project();
      final db = _database();
      final buyer = await _trader(project, db, 'buyer@example.com', 'Buyer', gold: 5000);
      for (var offer = 0; offer < bazaarOfferSlots; offer += 1) {
        final placed = await buyer.placeBazaarOffer(
          db,
          _stored(project, buyer),
          side: bazaarBuy,
          itemId: _ironOre,
          unitPrice: 10,
          quantity: 10,
        );
        expect(placed.ok, isTrue, reason: placed.reason);
        expect(placed.order!.slot, offer);
      }
      final fourth = await buyer.placeBazaarOffer(
        db,
        _stored(project, buyer),
        side: bazaarBuy,
        itemId: _ironOre,
        unitPrice: 10,
        quantity: 10,
      );
      expect(fourth.reason, bazaarNoSlots);
      expect((await buyer.bazaarMarket()).slotsFree, 0);
    });

    test('does not trade with itself, so a slot cannot be used to move gold', () async {
      final project = _project();
      final db = _database();
      final trader = await _trader(
        project,
        db,
        'trader@example.com',
        'Trader',
        bag: <InventoryStack>[_stack(_ironOre, 10)],
        gold: 1000,
      );
      await trader.placeBazaarOffer(
        db,
        _stored(project, trader),
        side: bazaarSell,
        itemId: _ironOre,
        unitPrice: 30,
        quantity: 10,
      );
      final crossed = await trader.placeBazaarOffer(
        db,
        _stored(project, trader),
        side: bazaarBuy,
        itemId: _ironOre,
        unitPrice: 30,
        quantity: 10,
      );
      expect(crossed.ok, isTrue, reason: crossed.reason);
      expect(crossed.order!.filled, 0);
      expect((await trader.bazaarMarket()).trades, isEmpty);
    });
  });

  group('matching', () {
    test('pays the resting price and refunds a buyer who offered more', () async {
      final project = _project();
      final db = _database();
      final seller = await _trader(
        project,
        db,
        'seller@example.com',
        'Seller',
        bag: <InventoryStack>[_stack(_ironOre, 10)],
      );
      final buyer = await _trader(project, db, 'buyer@example.com', 'Buyer', gold: 1000);

      await seller.placeBazaarOffer(
        db,
        _stored(project, seller),
        side: bazaarSell,
        itemId: _ironOre,
        unitPrice: 30,
        quantity: 10,
      );
      // Offering 50 for something resting at 30 pays 30 and gets the 20 back.
      final bought = await buyer.placeBazaarOffer(
        db,
        _stored(project, buyer),
        side: bazaarBuy,
        itemId: _ironOre,
        unitPrice: 50,
        quantity: 10,
      );
      expect(bought.ok, isTrue, reason: bought.reason);
      expect(bought.save!.gold, 500);
      expect(bought.message, 'Bought at once. Collect it from the box.');

      final box = (await buyer.bazaarMarket()).collect;
      expect(box.map((entry) => entry.reason).toList(), <String>[
        bazaarCollectBought,
        bazaarCollectRefund,
      ]);
      expect(box.firstWhere((entry) => entry.isGold).gold, 200);
      expect(box.firstWhere((entry) => !entry.isGold).quantity, 10);

      // The slot is freed the moment the order finishes, so three offers means
      // three open offers rather than three offers ever.
      expect((await buyer.bazaarMarket()).slotsFree, bazaarOfferSlots);
    });

    test('pays a seller who asked less than the best bid the bid, minus tax', () async {
      final project = _project();
      final db = _database();
      final buyer = await _trader(project, db, 'buyer@example.com', 'Buyer', gold: 10000);
      final seller = await _trader(
        project,
        db,
        'seller@example.com',
        'Seller',
        bag: <InventoryStack>[_stack(_titaniumOre, 10)],
      );

      await buyer.placeBazaarOffer(
        db,
        _stored(project, buyer),
        side: bazaarBuy,
        itemId: _titaniumOre,
        unitPrice: 500,
        quantity: 10,
      );
      final sold = await seller.placeBazaarOffer(
        db,
        _stored(project, seller),
        side: bazaarSell,
        itemId: _titaniumOre,
        unitPrice: 200,
        quantity: 10,
      );
      expect(sold.ok, isTrue, reason: sold.reason);
      expect(sold.message, 'Sold at once. Collect the gold from the box.');

      // 500 each, not the 200 asked; 1% of 5,000 comes off the seller.
      final box = (await seller.bazaarMarket()).collect.single;
      expect(box.gold, bazaarSellerReceives(500, 10));
      expect(box.gold, 4950);
      expect(box.reason, bazaarCollectSold);
    });

    test('takes no tax below the threshold, however large the offer', () async {
      final project = _project();
      final db = _database();
      final buyer = await _trader(project, db, 'buyer@example.com', 'Buyer', gold: 100000);
      final seller = await _trader(
        project,
        db,
        'seller@example.com',
        'Seller',
        bag: <InventoryStack>[_stack(_ironOre, 1000)],
      );
      await buyer.placeBazaarOffer(
        db,
        _stored(project, buyer),
        side: bazaarBuy,
        itemId: _ironOre,
        unitPrice: bazaarTaxThreshold,
        quantity: 1000,
      );
      await seller.placeBazaarOffer(
        db,
        _stored(project, seller),
        side: bazaarSell,
        itemId: _ironOre,
        unitPrice: bazaarTaxThreshold,
        quantity: 1000,
      );
      expect((await seller.bazaarMarket()).collect.single.gold, 100000);
      expect((await seller.bazaarMarket()).trades.single.tax, 0);
    });

    test('takes the cheapest ask first and leaves the rest resting', () async {
      final project = _project();
      final db = _database();
      final dear = await _trader(
        project,
        db,
        'dear@example.com',
        'Dear',
        bag: <InventoryStack>[_stack(_ironOre, 10)],
      );
      final cheap = await _trader(
        project,
        db,
        'cheap@example.com',
        'Cheap',
        bag: <InventoryStack>[_stack(_ironOre, 10)],
      );
      final buyer = await _trader(project, db, 'buyer@example.com', 'Buyer', gold: 1000);

      await dear.placeBazaarOffer(
        db,
        _stored(project, dear),
        side: bazaarSell,
        itemId: _ironOre,
        unitPrice: 40,
        quantity: 10,
      );
      await cheap.placeBazaarOffer(
        db,
        _stored(project, cheap),
        side: bazaarSell,
        itemId: _ironOre,
        unitPrice: 20,
        quantity: 10,
      );
      await buyer.placeBazaarOffer(
        db,
        _stored(project, buyer),
        side: bazaarBuy,
        itemId: _ironOre,
        unitPrice: 40,
        quantity: 10,
      );

      // The cheap ask went; the dear one is still on the book.
      expect((await cheap.bazaarMarket()).collect.single.gold, 200);
      expect((await dear.bazaarMarket()).collect, isEmpty);
      expect((await dear.bazaarMarket()).orders.single.filled, 0);
      // Paid 20 rather than the 40 offered, so 200 came back.
      expect((await buyer.bazaarMarket()).collect.firstWhere((entry) => entry.isGold).gold, 200);
    });

    test('fills part of an offer and leaves the rest open in its slot', () async {
      final project = _project();
      final db = _database();
      final seller = await _trader(
        project,
        db,
        'seller@example.com',
        'Seller',
        bag: <InventoryStack>[_stack(_ironOre, 10)],
      );
      final buyer = await _trader(project, db, 'buyer@example.com', 'Buyer', gold: 3000);
      await seller.placeBazaarOffer(
        db,
        _stored(project, seller),
        side: bazaarSell,
        itemId: _ironOre,
        unitPrice: 30,
        quantity: 10,
      );
      final bought = await buyer.placeBazaarOffer(
        db,
        _stored(project, buyer),
        side: bazaarBuy,
        itemId: _ironOre,
        unitPrice: 30,
        quantity: 100,
      );
      expect(bought.message, 'Buying offer placed; 10 traded straight away.');

      final open = (await buyer.bazaarMarket()).orders.single;
      expect(open.filled, 10);
      expect(open.isPartlyFilled, isTrue);
      expect(open.goldEscrow, 30 * 90);
      expect(open.status, 'open');
    });

    test('records the trade for both sides, newest first, ten at most', () async {
      final project = _project();
      final db = _database();
      final seller = await _trader(
        project,
        db,
        'seller@example.com',
        'Seller',
        bag: <InventoryStack>[_stack(_titaniumOre, 20)],
      );
      final buyer = await _trader(project, db, 'buyer@example.com', 'Buyer', gold: 100000);

      for (var round = 0; round < 12; round += 1) {
        await seller.placeBazaarOffer(
          db,
          _stored(project, seller),
          side: bazaarSell,
          itemId: _titaniumOre,
          unitPrice: 200 + round,
          quantity: 1,
        );
        await buyer.placeBazaarOffer(
          db,
          _stored(project, buyer),
          side: bazaarBuy,
          itemId: _titaniumOre,
          unitPrice: 200 + round,
          quantity: 1,
        );
      }

      final mine = (await seller.bazaarMarket()).trades;
      expect(mine, hasLength(bazaarHistoryLength));
      expect(mine.first.unitPrice, 211);
      expect(mine.last.unitPrice, 202);
      expect(mine.every((trade) => trade.side == bazaarSell), isTrue);
      expect(mine.first.tax, bazaarTax(211, 1));

      final theirs = (await buyer.bazaarMarket()).trades;
      expect(theirs.every((trade) => trade.side == bazaarBuy), isTrue);
      expect(theirs.first.tax, greaterThan(0));
      expect(theirs.first.net, 211);
    });

    test('moves the guide price by how much traded, not by how often', () async {
      final project = _project();
      final db = _database();
      final seller = await _trader(
        project,
        db,
        'seller@example.com',
        'Seller',
        bag: <InventoryStack>[_stack(_ironOre, 200)],
      );
      final buyer = await _trader(project, db, 'buyer@example.com', 'Buyer', gold: 100000);
      Future<void> deal(num price, num quantity) async {
        await seller.placeBazaarOffer(
          db,
          _stored(project, seller),
          side: bazaarSell,
          itemId: _ironOre,
          unitPrice: price,
          quantity: quantity,
        );
        await buyer.placeBazaarOffer(
          db,
          _stored(project, buyer),
          side: bazaarBuy,
          itemId: _ironOre,
          unitPrice: price,
          quantity: quantity,
        );
      }

      await deal(100, 100);
      expect((await seller.bazaarMarket()).prices.single.averagePrice, 100);

      // One unit at a silly price barely shifts a guide built on a hundred.
      await deal(1000, 1);
      final guide = (await seller.bazaarMarket()).prices.single;
      expect(guide.lastPrice, 1000);
      expect(guide.averagePrice, closeTo(109, 1));
      expect(guide.volume, 101);
      expect(guide.trades, 2);
    });
  });

  group('cancelling', () {
    test('returns an untouched sell order in full, through the box', () async {
      final project = _project();
      final db = _database();
      final seller = await _trader(
        project,
        db,
        'seller@example.com',
        'Seller',
        bag: <InventoryStack>[_stack(_ironOre, 60)],
      );
      final placed = await seller.placeBazaarOffer(
        db,
        _stored(project, seller),
        side: bazaarSell,
        itemId: _ironOre,
        unitPrice: 30,
        quantity: 60,
      );
      expect(_stored(project, seller).inventory, isEmpty);

      final cancelled = await seller.cancelBazaarOffer(placed.order!.id);
      expect(cancelled.ok, isTrue, reason: cancelled.reason);
      expect(cancelled.message, 'Offer cancelled. What was left is in the collection box.');

      // Cancelling gives nothing back directly: the bag is still empty until the
      // box is claimed, which is the same rule a filled order follows.
      expect(_stored(project, seller).inventory, isEmpty);
      final market = await seller.bazaarMarket();
      expect(market.orders, isEmpty);
      expect(market.slotsFree, bazaarOfferSlots);
      expect(market.collect.single.quantity, 60);
      expect(market.collect.single.reason, bazaarCollectCancelled);
    });

    test('returns only what has not traded of a partly filled offer', () async {
      final project = _project();
      final db = _database();
      final seller = await _trader(
        project,
        db,
        'seller@example.com',
        'Seller',
        bag: <InventoryStack>[_stack(_ironOre, 10)],
      );
      final buyer = await _trader(project, db, 'buyer@example.com', 'Buyer', gold: 3000);
      await seller.placeBazaarOffer(
        db,
        _stored(project, seller),
        side: bazaarSell,
        itemId: _ironOre,
        unitPrice: 30,
        quantity: 10,
      );
      final order = (await buyer.placeBazaarOffer(
        db,
        _stored(project, buyer),
        side: bazaarBuy,
        itemId: _ironOre,
        unitPrice: 30,
        quantity: 100,
      )).order!;

      expect((await buyer.cancelBazaarOffer(order.id)).ok, isTrue);
      final box = (await buyer.bazaarMarket()).collect;
      // The 10 that traded, and the gold held against the 90 that did not.
      expect(box.firstWhere((entry) => !entry.isGold).quantity, 10);
      expect(box.firstWhere((entry) => entry.isGold).gold, 30 * 90);
      expect(box.firstWhere((entry) => entry.isGold).reason, bazaarCollectCancelled);
    });

    test('refuses somebody else\'s offer, and a second cancel of its own', () async {
      final project = _project();
      final db = _database();
      final seller = await _trader(
        project,
        db,
        'seller@example.com',
        'Seller',
        bag: <InventoryStack>[_stack(_ironOre, 10)],
      );
      final other = await _trader(project, db, 'other@example.com', 'Other');
      final placed = await seller.placeBazaarOffer(
        db,
        _stored(project, seller),
        side: bazaarSell,
        itemId: _ironOre,
        unitPrice: 30,
        quantity: 10,
      );

      expect((await other.cancelBazaarOffer(placed.order!.id)).reason, 'That offer is not yours.');
      expect((await seller.cancelBazaarOffer(placed.order!.id)).ok, isTrue);
      expect(
        (await seller.cancelBazaarOffer(placed.order!.id)).reason,
        'That offer has already closed.',
      );
    });
  });

  group('the collection box', () {
    test('pays items and gold into the stored save when it is claimed', () async {
      final project = _project();
      final db = _database();
      final seller = await _trader(
        project,
        db,
        'seller@example.com',
        'Seller',
        bag: <InventoryStack>[_stack(_ironOre, 10)],
      );
      final buyer = await _trader(project, db, 'buyer@example.com', 'Buyer', gold: 1000);
      await seller.placeBazaarOffer(
        db,
        _stored(project, seller),
        side: bazaarSell,
        itemId: _ironOre,
        unitPrice: 30,
        quantity: 10,
      );
      await buyer.placeBazaarOffer(
        db,
        _stored(project, buyer),
        side: bazaarBuy,
        itemId: _ironOre,
        unitPrice: 50,
        quantity: 10,
      );

      final claimed = await buyer.collectBazaarBox(db, _stored(project, buyer));
      expect(claimed.ok, isTrue, reason: claimed.reason);
      expect(claimed.save!.inventory.single.itemId, _ironOre);
      expect(claimed.save!.inventory.single.quantity, 10);
      // 1000 - 500 escrowed, then the 200 overpayment back.
      expect(claimed.save!.gold, 700);
      expect(claimed.message, 'Collected 10 items and 200 gold.');
      expect((await buyer.bazaarMarket()).collect, isEmpty);

      final paid = await seller.collectBazaarBox(db, _stored(project, seller));
      expect(paid.save!.gold, 300);
      expect(paid.message, 'Collected 300 gold.');
    });

    test('refuses an empty box rather than writing the save for nothing', () async {
      final project = _project();
      final db = _database();
      final trader = await _trader(project, db, 'trader@example.com', 'Trader');
      final refused = await trader.collectBazaarBox(db, _stored(project, trader));
      expect(refused.reason, bazaarEmptyCollection);
    });

    test('leaves behind a row that will not fit and says so', () async {
      final project = _project();
      final db = _database();
      final seller = await _trader(
        project,
        db,
        'seller@example.com',
        'Seller',
        bag: <InventoryStack>[_stack(_ironOre, 10)],
      );
      final buyer = await _trader(project, db, 'buyer@example.com', 'Buyer', gold: 1000);
      await seller.placeBazaarOffer(
        db,
        _stored(project, seller),
        side: bazaarSell,
        itemId: _ironOre,
        unitPrice: 30,
        quantity: 10,
      );
      await buyer.placeBazaarOffer(
        db,
        _stored(project, buyer),
        side: bazaarBuy,
        itemId: _ironOre,
        unitPrice: 50,
        quantity: 10,
      );

      // A bag with every slot taken by something else has nowhere for the ore,
      // but the refund is a number rather than a slot and still lands.
      final full = _stored(project, buyer).copyWith(
        inventory: <InventoryStack>[
          for (var slot = 0; slot < inventorySlotLimit; slot += 1) _stack(_titaniumOre, 1),
        ],
      );
      final claimed = await buyer.collectBazaarBox(db, full);
      expect(claimed.ok, isTrue, reason: claimed.reason);
      expect(claimed.message, 'Collected 200 gold. 1 more would not fit.');
      expect((await buyer.bazaarMarket()).collect.single.itemId, _ironOre);
    });
  });
}
