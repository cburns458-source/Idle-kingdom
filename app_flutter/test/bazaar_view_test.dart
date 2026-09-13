// The Bazaar screen: what it draws, and what it asks the server for.
//
// The exchange is server-decided, so the screen has almost no arithmetic in it.
// What is worth pinning down is the rest: the hamburger reaches it from anywhere,
// an unsigned player sees an empty book rather than a broken one, the browse and
// sell lists show what they should and refuse what they should, the three slots
// are always three, and placing an offer sends the two numbers the keypads
// collected. The matching itself is covered in `packages/ik_net/test`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/multiplayer_controller.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/bazaar_view.dart';
import 'package:idle_kingdoms/src/ui/game_popup.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'support/harness.dart';

const String _ironOre = 'ITEM-0005';
const String _titaniumOre = 'ITEM-0009';
const String _gold = 'ITEM-0001';

InventoryStack _stack(String itemId, num quantity, {String? enchantmentId, bool? favorite}) =>
    InventoryStack(
      itemId: itemId,
      quantity: quantity,
      enchantmentId: enchantmentId,
      favorite: favorite,
    );

void main() {
  final database = loadDatabaseFromRepo();

  /// A signed-in player on a hosted project, with [bag] and [gold] in the save
  /// the backend holds — the copy the exchange escrows from.
  Future<({MultiplayerController net, FakeTransport project, PlayerSave save})> hostedPlayer(
    WidgetTester tester, {
    List<InventoryStack> bag = const <InventoryStack>[],
    num gold = 0,
  }) async {
    final project = FakeTransport(startIso: '2025-01-01T00:00:00.000Z');
    final net = buildRemoteMultiplayer(database, transport: project);
    addTearDown(net.dispose);
    var save = startedCharacter(database).copyWith(inventory: bag, gold: gold);
    await net.signUp(
      testAccount.email,
      testAccount.username,
      testAccount.password,
      save,
      adopt: (adopted, {nowMs}) => save = adopted,
    );
    expect(net.isSignedIn, isTrue, reason: net.notice);
    final pushed = await net.service.pushSave(database.launch, save);
    expect(pushed.ok, isTrue, reason: pushed.reason);
    return (net: net, project: project, save: pushed.save!);
  }

  /// Another player already resting an offer on the book, so there is something
  /// to browse and something to trade against.
  Future<void> seedSeller(
    FakeTransport project, {
    String itemId = _ironOre,
    num unitPrice = 30,
    num quantity = 60,
  }) async {
    final rival = RemoteMultiplayerService(
      transport: FakeTransport.joining(project),
      storage: MemorySaveStorage(),
    );
    expect((await rival.signUp('rival@example.com', 'Rival', 'secret')).ok, isTrue);
    final stocked = startedCharacter(database)
        .copyWith(inventory: <InventoryStack>[_stack(itemId, quantity)]);
    expect((await rival.pushSave(database.launch, stocked)).ok, isTrue);
    final placed = await rival.placeBazaarOffer(
      database.launch,
      stocked,
      side: bazaarSell,
      itemId: itemId,
      unitPrice: unitPrice,
      quantity: quantity,
    );
    expect(placed.ok, isTrue, reason: placed.reason);
  }

  Future<void> pumpBazaar(WidgetTester tester, MultiplayerController net, PlayerSave save) async {
    final controller = buildController(database, seed: save);
    await pumpPanel(
      tester,
      BazaarView(controller: controller, multiplayer: net, onClose: () {}),
      size: const Size(900, 2400),
    );
    await tester.pump();
    await tester.pump();
  }

  /// Taps a tab by its name, which the Offers tab appends a waiting count to.
  Future<void> tab(WidgetTester tester, String label) async {
    await tester.tap(
      find.ancestor(of: find.textContaining(RegExp('^$label')), matching: find.byType(GameButton)),
    );
    await tester.pump();
    await tester.pump();
  }

  /// Answers the keypad on top with [digits], then its confirming button.
  Future<void> keypad(WidgetTester tester, String digits, String confirm) async {
    for (final digit in digits.split('')) {
      await tester.tap(find.widgetWithText(GameButton, digit));
    }
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(GamePopupCard),
        matching: find.widgetWithText(GameButton, confirm),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('opens from the hamburger wherever the player is standing', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    final net = buildMultiplayer(database);
    addTearDown(net.dispose);
    await pumpShell(tester, controller, multiplayer: net, size: const Size(900, 2000));

    await openChinScreen(tester, 'Bazaar');

    expect(find.text('Bazaar'), findsWidgets);
    // Local play has nobody to trade with, so the book is empty and says why.
    expect(find.text(bazaarHostedOnly), findsOne);
  });

  testWidgets('tells a signed-out player on a hosted build to sign in', (tester) async {
    final project = FakeTransport();
    final net = buildRemoteMultiplayer(database, transport: project);
    addTearDown(net.dispose);
    await pumpBazaar(tester, net, startedCharacter(database));

    expect(find.text(bazaarSignInToTrade), findsOne);
    expect(net.market.orders, isEmpty);
    // Nothing was asked of the server, so a signed-out screen costs no calls.
    expect(project.calls, isNot(contains('invoke:$remoteBazaarMarketFunction')));
  });

  testWidgets('browses what is on offer and opens one item\'s book', (tester) async {
    final player = await hostedPlayer(tester, gold: 5000);
    await seedSeller(player.project);
    await pumpBazaar(tester, player.net, player.save);

    expect(find.text('Iron Ore'), findsOne);
    expect(find.textContaining('Cheapest: 30'), findsOne);
    expect(find.textContaining('60 on offer'), findsOne);

    await tester.tap(find.text('Iron Ore'));
    await tester.pump();
    await tester.pump();

    expect(find.text('On offer'), findsOne);
    expect(find.text('30 each'), findsOne);
    expect(find.text('Nobody is buying.'), findsOne);
    expect(find.widgetWithText(GameButton, 'Offer to buy'), findsOne);
  });

  testWidgets('lists only the bag stacks the exchange will take', (tester) async {
    final player = await hostedPlayer(
      tester,
      bag: <InventoryStack>[
        _stack(_ironOre, 40),
        _stack(_titaniumOre, 5, favorite: true),
        _stack(_gold, 100),
      ],
      gold: 100,
    );
    await pumpBazaar(tester, player.net, player.save);
    await tab(tester, 'Sell');

    expect(find.text(bazaarWithdrawFirst), findsOne);
    expect(find.textContaining('Carrying 40'), findsOne);
    // The favourite is named with its reason rather than quietly dropped, and
    // gold is not mentioned at all because it is the currency, not a good.
    expect(find.text('Staying with you'), findsOne);
    expect(find.text('Titanium Ore — $bazaarFavoriteNotTraded'), findsOne);
    expect(find.textContaining('Gold —'), findsNothing);
  });

  testWidgets('says to withdraw when the item is only in the bank', (tester) async {
    final player = await hostedPlayer(tester);
    final banked = player.save.copyWith(bank: <InventoryStack>[_stack(_ironOre, 900)]);
    expect((await player.net.service.pushSave(database.launch, banked)).ok, isTrue);
    await seedSeller(player.project);
    await pumpBazaar(tester, player.net, banked);
    await tab(tester, 'Sell');

    expect(find.text('Nothing in your bag can be listed.'), findsOne);
  });

  testWidgets('draws three slots however many offers are open', (tester) async {
    final player = await hostedPlayer(tester, bag: <InventoryStack>[_stack(_ironOre, 40)]);
    await pumpBazaar(tester, player.net, player.save);
    await tab(tester, 'Offers');

    expect(find.textContaining('— empty'), findsNWidgets(bazaarOfferSlots));
    expect(find.text(bazaarEmptyCollection), findsOne);
  });

  testWidgets('places a sell offer with the two numbers the keypads collected', (tester) async {
    final player = await hostedPlayer(tester, bag: <InventoryStack>[_stack(_ironOre, 40)]);
    await pumpBazaar(tester, player.net, player.save);
    await tab(tester, 'Sell');

    await tester.tap(find.text('Iron Ore'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.widgetWithText(GameButton, 'Offer to sell'));
    await tester.pump();

    // How many, then what each. Quantity first so the price pad can cap itself.
    expect(find.text('How many to sell'), findsOne);
    expect(find.text('Carrying: 40'), findsOne);
    await keypad(tester, '25', 'Next');

    expect(find.text('Price per item to ask'), findsOne);
    expect(find.text('Quantity: 25'), findsOne);
    await keypad(tester, '40', 'Sell');
    await tester.pumpAndSettle();

    final order = player.net.market.orders.single;
    expect(order.side, bazaarSell);
    expect(order.itemId, _ironOre);
    expect(order.quantity, 25);
    expect(order.unitPrice, 40);
    expect(order.slot, 0);
    // The escrow came out of the save the server holds, and the screen adopted
    // what came back rather than working it out.
    expect(player.net.market.slotsFree, bazaarOfferSlots - 1);
  });

  testWidgets('shows a filled offer in the box, and empties it on collect', (tester) async {
    final player = await hostedPlayer(tester, gold: 5000);
    await seedSeller(player.project, unitPrice: 30, quantity: 10);

    // Buying above the resting ask pays the ask; the 20 an item comes back.
    await player.net.placeMarketOffer(
      side: bazaarBuy,
      itemId: _ironOre,
      unitPrice: 50,
      quantity: 10,
      save: player.save,
      onSaved: (written) {},
    );
    await pumpBazaar(tester, player.net, player.save);
    await tab(tester, 'Offers');

    expect(find.text('Iron Ore ×10'), findsOne);
    expect(find.text('Bought'), findsOne);
    expect(find.text('200 gold'), findsOne);
    expect(find.text('Change from a buy offer'), findsOne);
    // The finished offer freed its slot, so all three read empty again.
    expect(find.textContaining('— empty'), findsNWidgets(bazaarOfferSlots));
    // The Offers tab counts what is waiting so a fill is noticed without looking.
    expect(find.widgetWithText(GameButton, 'Offers (2)'), findsOne);

    await tester.tap(find.widgetWithText(GameButton, 'Collect'));
    await tester.pumpAndSettle();

    expect(player.net.market.collect, isEmpty);
    expect(find.text(bazaarEmptyCollection), findsOne);
  });

  testWidgets('cancels an open offer and leaves the remainder to collect', (tester) async {
    final player = await hostedPlayer(tester, bag: <InventoryStack>[_stack(_ironOre, 40)]);
    await player.net.placeMarketOffer(
      side: bazaarSell,
      itemId: _ironOre,
      unitPrice: 30,
      quantity: 40,
      save: player.save,
      onSaved: (written) {},
    );
    await pumpBazaar(tester, player.net, player.save);
    await tab(tester, 'Offers');

    expect(find.text('Selling Iron Ore ×40'), findsOne);
    await tester.tap(find.widgetWithText(GameButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(player.net.market.orders, isEmpty);
    expect(find.text('Iron Ore ×40'), findsOne);
    expect(find.text('Cancelled offer'), findsOne);
  });

  testWidgets('lists the player\'s own last trades with the tax on the sale', (tester) async {
    final player = await hostedPlayer(tester, bag: <InventoryStack>[_stack(_titaniumOre, 10)]);
    // A rival wanting titanium at 500, met by this player asking 200: the
    // resting bid is what gets paid, less 1%.
    final rival = RemoteMultiplayerService(
      transport: FakeTransport.joining(player.project),
      storage: MemorySaveStorage(),
    );
    expect((await rival.signUp('rival@example.com', 'Rival', 'secret')).ok, isTrue);
    final rich = startedCharacter(database).copyWith(gold: 100000);
    expect((await rival.pushSave(database.launch, rich)).ok, isTrue);
    expect(
      (await rival.placeBazaarOffer(
        database.launch,
        rich,
        side: bazaarBuy,
        itemId: _titaniumOre,
        unitPrice: 500,
        quantity: 10,
      )).ok,
      isTrue,
    );

    await player.net.placeMarketOffer(
      side: bazaarSell,
      itemId: _titaniumOre,
      unitPrice: 200,
      quantity: 10,
      save: player.save,
      onSaved: (written) {},
    );
    await pumpBazaar(tester, player.net, player.save);
    await tab(tester, 'History');

    expect(find.text('Your last $bazaarHistoryLength trades.'), findsOne);
    expect(find.text('Sold Titanium Ore ×10'), findsOne);
    expect(find.text('500 each · 4,950 gold received'), findsOne);
    expect(find.text('Tax 50'), findsOne);
  });

  testWidgets('says a taxed sale is taxed and an untaxed one is not', (tester) async {
    expect(bazaarTaxLine(bazaarTaxThreshold), contains('untaxed'));
    expect(bazaarTaxLine(bazaarTaxThreshold + 1), contains('pay $bazaarTaxPercent%'));
  });
}
