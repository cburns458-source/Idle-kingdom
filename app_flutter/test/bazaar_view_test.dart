// The Bazaar screen: what it draws, and what it asks the server for.
//
// The exchange is server-decided, so the screen has almost no arithmetic in it.
// What is worth pinning down is the rest: the hamburger reaches it from anywhere,
// an unsigned player sees a closed exchange rather than a broken one, the three
// slots are always three and are the only way to start an order, the buy list
// offers the whole catalogue while the sell list offers only the bag, and an
// order is placed with the two numbers the sections collected. The matching
// itself is covered in `packages/ik_net/test`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/multiplayer_controller.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/bazaar_view.dart';
import 'package:idle_kingdoms/src/ui/dialogue_text.dart';
import 'package:idle_kingdoms/src/ui/game_popup.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'support/harness.dart';

const String _ironOre = 'ITEM-0005';
const String _titaniumOre = 'ITEM-0009';
const String _gold = 'ITEM-0001';
const String _machete = 'ITEM-0406';

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
    int totalLevelTarget = 200,
  }) async {
    final project = FakeTransport(startIso: '2025-01-01T00:00:00.000Z', database: database.launch);
    final net = buildRemoteMultiplayer(database, transport: project);
    addTearDown(net.dispose);
    var save = withTotalLevel(
      startedCharacter(database).copyWith(inventory: bag, gold: gold),
      totalLevelTarget,
    );
    await net.signUp(
      testAccount.email,
      testAccount.username,
      testAccount.password,
      save,
      adopt: (adopted, {nowMs}) => save = adopted,
    );
    expect(net.isSignedIn, isTrue, reason: net.notice);
    final seeded = await seedHostedSave(net.service as RemoteMultiplayerService, project, save);
    expect(seeded.ok, isTrue, reason: seeded.reason);
    return (net: net, project: project, save: seeded.save!);
  }

  /// Another player already resting an offer on the book, so there is something
  /// to trade against.
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
    final stocked = withTotalLevel(
      startedCharacter(database).copyWith(inventory: <InventoryStack>[_stack(itemId, quantity)]),
      200,
    );
    expect((await seedHostedSave(rival, project, stocked)).ok, isTrue);
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

  Future<void> press(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(GameButton, label).first);
    await tester.pump();
    await tester.pump();
  }

  /// Opens the flow the first empty slot offers, for [side].
  Future<void> startOrder(WidgetTester tester, BazaarSide side) =>
      press(tester, side == bazaarBuy ? 'Create a buy order' : 'Create a sell order');

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

  /// Taps one of the two numbers on the compose page and answers its keypad.
  Future<void> setField(WidgetTester tester, String label, String digits) async {
    await tester.tap(find.text(label));
    await tester.pump();
    await tester.pump();
    await keypad(tester, digits, label == 'Quantity' ? 'Set quantity' : 'Set price');
  }

  testWidgets('opens from the hamburger wherever the player is standing', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    final net = buildMultiplayer(database);
    addTearDown(net.dispose);
    await pumpShell(tester, controller, multiplayer: net, size: const Size(900, 2000));

    await openChinScreen(tester, 'Bazaar');

    expect(find.text('Bazaar'), findsWidgets);
    // Local play has nobody to trade with, so the exchange is shut and says why.
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

  testWidgets('opens on six empty slots, each offering both sides', (tester) async {
    final player = await hostedPlayer(tester);
    await pumpBazaar(tester, player.net, player.save);

    expect(bazaarOfferSlots, 6);
    expect(find.textContaining('— empty'), findsNWidgets(bazaarOfferSlots));
    expect(find.widgetWithText(GameButton, 'Create a buy order'), findsNWidgets(bazaarOfferSlots));
    expect(find.widgetWithText(GameButton, 'Create a sell order'), findsNWidgets(bazaarOfferSlots));
    // The collection box stays on the page because it holds goods to take. The
    // history is only a look back, so it waits behind its own button.
    expect(find.text(bazaarEmptyCollection), findsOne);
    expect(find.text(bazaarEmptyHistory), findsNothing);
    expect(find.byKey(const Key('bazaar-recent-trades')), findsOne);
  });

  testWidgets('never shows anybody else\'s offers', (tester) async {
    final player = await hostedPlayer(tester, gold: 5000);
    await seedSeller(player.project);
    await pumpBazaar(tester, player.net, player.save);

    // A rival is resting 60 at 30, and none of it is on the screen: the player
    // sees their own six slots and nothing about the book.
    expect(find.text('On offer'), findsNothing);
    expect(find.text('Wanted'), findsNothing);
    expect(find.textContaining('on offer'), findsNothing);
  });

  testWidgets('buy offers the whole catalogue, searchable, with its average price', (tester) async {
    final player = await hostedPlayer(tester, gold: 5000);
    await seedSeller(player.project);
    await pumpBazaar(tester, player.net, player.save);
    await startOrder(tester, bazaarBuy);

    // Nothing has traded yet, so there is no average to quote, but the item is
    // still listed: a buy order is worth placing when nobody is selling.
    expect(find.text('Iron ore'), findsOne);
    expect(find.textContaining('No trades yet'), findsWidgets);
    expect(tester.widget<GameButton>(find.byKey(const Key('bazaar-filter-All'))).selected, isTrue);
    expect(
      tester
          .widget<PixelInkPlate>(
            find.descendant(
              of: find.byKey(const Key('bazaar-filter-All')),
              matching: find.byType(PixelInkPlate),
            ),
          )
          .selected,
      isFalse,
    );
    expect(
      tester
          .widget<PixelInkPlate>(
            find.descendant(
              of: find.byKey(const Key('bazaar-filter-All')),
              matching: find.byType(PixelInkPlate),
            ),
          )
          .inset,
      isTrue,
    );

    await tester.enterText(find.byType(TextField), 'titanium');
    await tester.pump();

    expect(find.text('Titanium ore'), findsOne);
    expect(find.text('Iron ore'), findsNothing);
  });

  testWidgets('sell offers only the bag stacks the exchange will take', (tester) async {
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
    await startOrder(tester, bazaarSell);

    expect(find.text(bazaarWithdrawFirst), findsOne);
    expect(find.textContaining('Carrying 40'), findsOne);
    // The favourite is named with its reason rather than quietly dropped, and
    // gold is not mentioned at all because it is the currency, not a good.
    expect(find.text('Staying with you'), findsOne);
    expect(find.text('Titanium ore — $bazaarFavoriteNotTraded'), findsOne);
    expect(find.textContaining('Gold —'), findsNothing);
  });

  testWidgets('lists an untradeable item like any other and refuses it with a popup', (
    tester,
  ) async {
    final player = await hostedPlayer(
      tester,
      bag: <InventoryStack>[_stack(_machete, 1), _stack(_ironOre, 40)],
      gold: 100,
    );
    await pumpBazaar(tester, player.net, player.save);
    await startOrder(tester, bazaarSell);

    // Same row as Iron ore: name, what is carried, and a price line. No section,
    // no marker, and no refusal text until the player tries to list it.
    expect(find.text('Machete'), findsOne);
    expect(find.textContaining('Carrying 1'), findsOne);
    expect(find.textContaining('Carrying 40'), findsOne);
    expect(find.text('Staying with you'), findsNothing);
    expect(find.textContaining(bazaarBoundItem), findsNothing);

    int bazaarCalls() => player.project.calls.where((call) => call.contains('bazaar')).length;
    final callsBefore = bazaarCalls();
    await tester.tap(find.text('Machete'));
    await tester.pump();
    await tester.pump();

    final popup = find.byType(GamePopupCard);
    expect(popup, findsOne);
    expect(find.descendant(of: popup, matching: find.text(bazaarBoundItem)), findsOne);
    await tester.tap(find.descendant(of: popup, matching: find.widgetWithText(GameButton, 'OK')));
    await tester.pump();
    await tester.pump();

    // Still on the sell list, with nothing composed and nothing sent.
    expect(find.byType(GamePopupCard), findsNothing);
    expect(find.text('Quantity'), findsNothing);
    expect(bazaarCalls(), callsBefore);
    expect(player.project.exchange.orders, isEmpty);
  });

  testWidgets('says to withdraw when the item is only in the bank', (tester) async {
    final player = await hostedPlayer(tester);
    final banked = player.save.copyWith(bank: <InventoryStack>[_stack(_ironOre, 900)]);
    expect(
      (await seedHostedSave(
        player.net.service as RemoteMultiplayerService,
        player.project,
        banked,
      )).ok,
      isTrue,
    );
    await pumpBazaar(tester, player.net, banked);
    await startOrder(tester, bazaarSell);

    expect(find.text('Nothing in your bag can be listed.'), findsOne);
  });

  testWidgets('places a sell order with the two numbers the sections collected', (tester) async {
    final player = await hostedPlayer(tester, bag: <InventoryStack>[_stack(_ironOre, 40)]);
    await pumpBazaar(tester, player.net, player.save);
    await startOrder(tester, bazaarSell);
    await tester.tap(find.text('Iron ore'));
    await tester.pump();
    await tester.pump();

    // A sell starts at the whole stack, so the quantity is already the 40 held.
    expect(find.text('Quantity'), findsOne);
    expect(find.text('40'), findsWidgets);
    expect(find.text('Price each'), findsOne);

    await setField(tester, 'Quantity', '25');
    await setField(tester, 'Price each', '40');
    await press(tester, 'Place sell order');
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

  testWidgets('will not place a buy the player cannot pay for', (tester) async {
    final player = await hostedPlayer(tester, gold: 50);
    await pumpBazaar(tester, player.net, player.save);
    await startOrder(tester, bazaarBuy);
    await tester.enterText(find.byType(TextField), 'iron ore');
    await tester.pump();
    await tester.tap(find.text('Iron ore'));
    await tester.pump();
    await tester.pump();

    // Price is capped at gold, so unaffordable means quantity × price > gold
    // while each is still individually within the purse.
    await setField(tester, 'Price each', '5');
    await setField(tester, 'Quantity', '10');
    await setField(tester, 'Price each', '6');

    // 60 gold against 50 held: the screen says so instead of offering a button
    // the server would only refuse.
    expect(find.textContaining('You have 50 gold'), findsOne);
    expect(find.widgetWithText(GameButton, 'Place buy order'), findsNothing);
  });

  testWidgets('buy price Max fills the player gold', (tester) async {
    final buyer = await hostedPlayer(tester, gold: 250);
    await pumpBazaar(tester, buyer.net, buyer.save);
    await startOrder(tester, bazaarBuy);
    await tester.enterText(find.byType(TextField), 'iron ore');
    await tester.pump();
    await tester.tap(find.text('Iron ore'));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Price each'));
    await tester.pump();
    await tester.pump();
    expect(find.widgetWithText(GameButton, 'Max'), findsOne);
    await tester.tap(find.widgetWithText(GameButton, 'Max'));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(GamePopupCard),
        matching: find.widgetWithText(GameButton, 'Set price'),
      ),
    );
    await tester.pump();
    await tester.pump();
    // Qty defaults to 1, so Max price = gold and the order is affordable.
    expect(find.text('250'), findsWidgets);
    expect(find.widgetWithText(GameButton, 'Place buy order'), findsOne);
  });

  testWidgets('sell price keypad has no Max button', (tester) async {
    final seller = await hostedPlayer(tester, bag: <InventoryStack>[_stack(_ironOre, 40)]);
    await pumpBazaar(tester, seller.net, seller.save);
    await startOrder(tester, bazaarSell);
    await tester.tap(find.text('Iron ore'));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Price each'));
    await tester.pump();
    await tester.pump();
    expect(find.widgetWithText(GameButton, 'Max'), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(GamePopupCard),
        matching: find.widgetWithText(GameButton, 'Set price'),
      ),
    );
    await tester.pump();
    await tester.pump();
  });

  testWidgets('buy quantity Max is capped by gold at the named price', (tester) async {
    final player = await hostedPlayer(tester, gold: 100);
    await pumpBazaar(tester, player.net, player.save);
    await startOrder(tester, bazaarBuy);
    await tester.enterText(find.byType(TextField), 'iron ore');
    await tester.pump();
    await tester.tap(find.text('Iron ore'));
    await tester.pump();
    await tester.pump();

    await setField(tester, 'Price each', '25');
    await tester.tap(find.text('Quantity'));
    await tester.pump();
    await tester.pump();
    expect(find.widgetWithText(GameButton, 'Max'), findsOne);
    await tester.tap(find.widgetWithText(GameButton, 'Max'));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(GamePopupCard),
        matching: find.widgetWithText(GameButton, 'Set quantity'),
      ),
    );
    await tester.pump();
    await tester.pump();
    // 100 gold / 25 each → 4.
    expect(find.text('4'), findsWidgets);
    expect(find.widgetWithText(GameButton, 'Place buy order'), findsOne);
  });

  testWidgets('a placed order takes over its slot and shows how filled it is', (tester) async {
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

    expect(find.text('Selling Iron ore ×40'), findsOne);
    expect(find.text('30 each · 0 of 40 traded'), findsOne);
    // That slot is no longer offering to start anything, and the other two are.
    expect(find.textContaining('— empty'), findsNWidgets(bazaarOfferSlots - 1));

    await press(tester, 'Cancel');
    await tester.pumpAndSettle();

    expect(player.net.market.orders, isEmpty);
    expect(find.text('Iron ore ×40'), findsOne);
    expect(find.text('Cancelled offer'), findsOne);
  });

  testWidgets('a filled order frees its slot and waits in the box', (tester) async {
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

    expect(find.text('Iron ore ×10'), findsOne);
    expect(find.text('Bought'), findsOne);
    expect(find.text('200 gold'), findsOne);
    expect(find.text('Change from a buy offer'), findsOne);
    // The finished order freed its slot, so all three offer to start again.
    expect(find.textContaining('— empty'), findsNWidgets(bazaarOfferSlots));

    await press(tester, 'Collect');
    await tester.pumpAndSettle();

    expect(player.net.market.collect, isEmpty);
    expect(find.text(bazaarEmptyCollection), findsOne);
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
    final rich = withTotalLevel(startedCharacter(database).copyWith(gold: 100000), 200);
    expect((await seedHostedSave(rival, player.project, rich)).ok, isTrue);
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

    expect(find.text('Recent trades'), findsOne);
    expect(find.text('Sold Titanium ore ×10'), findsNothing);

    await tester.tap(find.byKey(const Key('bazaar-recent-trades')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Sold Titanium ore ×10'), findsOne);
    expect(find.text('500 each · 4,950 gold received'), findsOne);
    expect(find.text('Tax 50'), findsOne);
  });

  testWidgets('shows the exact total-level popup on a buy and does not send a request', (
    tester,
  ) async {
    final player = await hostedPlayer(
      tester,
      bag: <InventoryStack>[_stack(_ironOre, 40)],
      gold: 5000,
      totalLevelTarget: 199,
    );
    expect(totalLevel(player.save), 199);
    await pumpBazaar(tester, player.net, player.save);

    int bazaarCalls() => player.project.calls.where((call) => call.contains('bazaar')).length;
    final callsBefore = bazaarCalls();
    await startOrder(tester, bazaarBuy);

    final popup = find.byType(GamePopupCard);
    expect(popup, findsOne);
    expect(
      find.descendant(
        of: popup,
        matching: find.text('You need total level 200 to use the bazaar.'),
      ),
      findsOne,
    );
    expect(find.descendant(of: popup, matching: find.text(bazaarTotalLevelTooLow)), findsOne);
    await tester.tap(find.descendant(of: popup, matching: find.widgetWithText(GameButton, 'OK')));
    await tester.pump();
    await tester.pump();

    expect(find.byType(GamePopupCard), findsNothing);
    expect(find.text('Quantity'), findsNothing);
    expect(bazaarCalls(), callsBefore);
    expect(player.project.exchange.orders, isEmpty);
  });

  testWidgets('shows the exact total-level popup on a sell and does not send a request', (
    tester,
  ) async {
    final player = await hostedPlayer(
      tester,
      bag: <InventoryStack>[_stack(_ironOre, 40)],
      gold: 5000,
      totalLevelTarget: 199,
    );
    await pumpBazaar(tester, player.net, player.save);

    int bazaarCalls() => player.project.calls.where((call) => call.contains('bazaar')).length;
    final callsBefore = bazaarCalls();
    await startOrder(tester, bazaarSell);

    final popup = find.byType(GamePopupCard);
    expect(popup, findsOne);
    expect(
      find.descendant(
        of: popup,
        matching: find.text('You need total level 200 to use the bazaar.'),
      ),
      findsOne,
    );
    await tester.tap(find.descendant(of: popup, matching: find.widgetWithText(GameButton, 'OK')));
    await tester.pump();
    await tester.pump();

    expect(find.byType(GamePopupCard), findsNothing);
    expect(bazaarCalls(), callsBefore);
    expect(player.project.exchange.orders, isEmpty);
  });

  testWidgets('says a taxed sale is taxed and an untaxed one is not', (tester) async {
    expect(bazaarTaxLine(bazaarTaxThreshold), contains('untaxed'));
    expect(bazaarTaxLine(bazaarTaxThreshold + 1), contains('pay $bazaarTaxPercent%'));
  });

  List<InventoryStack> filledBag({int free = 0}) {
    return [
      for (var index = 0; index < inventorySlotLimit - free; index++)
        InventoryStack(itemId: 'FILL-$index', quantity: 1),
    ];
  }

  void seedCollection(
    FakeTransport project,
    String userId, {
    int gold = 0,
    List<(String itemId, int quantity)> items = const <(String, int)>[],
  }) {
    var stamp = 0;
    if (gold > 0) {
      project.exchange.box.add(
        FakeExchangeCollect(
          id: 'bzc_gold',
          userId: userId,
          itemId: null,
          quantity: 0,
          gold: gold,
          reason: bazaarCollectSold,
          createdAt: '2026-01-01T00:00:${stamp.toString().padLeft(2, '0')}.000Z',
        ),
      );
      stamp += 1;
    }
    for (final (itemId, quantity) in items) {
      project.exchange.box.add(
        FakeExchangeCollect(
          id: 'bzc_$itemId',
          userId: userId,
          itemId: itemId,
          quantity: quantity,
          gold: 0,
          reason: bazaarCollectBought,
          createdAt: '2026-01-01T00:00:${stamp.toString().padLeft(2, '0')}.000Z',
        ),
      );
      stamp += 1;
    }
  }

  testWidgets('a full Bazaar collect shows no popup', (tester) async {
    final player = await hostedPlayer(tester, gold: 10);
    seedCollection(
      player.project,
      player.net.service.session!.userId,
      gold: 40,
      items: <(String, int)>[(_ironOre, 2)],
    );
    await pumpBazaar(tester, player.net, player.save);

    await tester.tap(find.widgetWithText(GameButton, 'Collect'));
    await tester.pumpAndSettle();

    expect(find.text(DialogueText.bazaarCollectionFull), findsNothing);
    expect(find.textContaining('still in your collection box'), findsNothing);
    expect(player.net.market.collect, isEmpty);
  });

  testWidgets('a full-bag Bazaar collect still takes gold and shows the collection-box popup', (
    tester,
  ) async {
    final player = await hostedPlayer(tester);
    final userId = player.net.service.session!.userId;
    seedCollection(player.project, userId, gold: 80, items: <(String, int)>[(_ironOre, 3)]);
    final full = player.save.copyWith(inventory: filledBag(), gold: 5);
    expect(
      (await seedHostedSave(
        player.net.service as RemoteMultiplayerService,
        player.project,
        full,
      )).ok,
      isTrue,
    );
    final controller = buildController(database, seed: full);
    addTearDown(controller.dispose);
    await pumpPanel(
      tester,
      BazaarView(controller: controller, multiplayer: player.net, onClose: () {}),
      size: const Size(900, 2400),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.widgetWithText(GameButton, 'Collect'));
    await tester.pumpAndSettle();

    expect(find.text(DialogueText.bazaarCollectionFull), findsOne);
    expect(find.textContaining('cannot hold'), findsNothing);
    expect(controller.save.gold, 85);
    expect(controller.save.inventory, hasLength(inventorySlotLimit));
    expect(player.net.market.collect.single.itemId, _ironOre);
  });

  testWidgets('a partial Bazaar collect takes one row and shows the collection-box popup', (
    tester,
  ) async {
    final player = await hostedPlayer(tester);
    final userId = player.net.service.session!.userId;
    seedCollection(
      player.project,
      userId,
      items: <(String, int)>[(_ironOre, 1), (_titaniumOre, 1), (clayId, 1)],
    );
    final roomForOne = player.save.copyWith(inventory: filledBag(free: 1));
    expect(
      (await seedHostedSave(
        player.net.service as RemoteMultiplayerService,
        player.project,
        roomForOne,
      )).ok,
      isTrue,
    );
    final controller = buildController(database, seed: roomForOne);
    addTearDown(controller.dispose);
    await pumpPanel(
      tester,
      BazaarView(controller: controller, multiplayer: player.net, onClose: () {}),
      size: const Size(900, 2400),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.widgetWithText(GameButton, 'Collect'));
    await tester.pumpAndSettle();

    expect(find.text(DialogueText.bazaarCollectionFull), findsOne);
    expect(controller.save.inventory, hasLength(inventorySlotLimit));
    expect(controller.save.inventory.any((stack) => stack.itemId == _ironOre), isTrue);
    expect(player.net.market.collect, hasLength(2));
  });
}

const String clayId = 'ITEM-0002';

PlayerSave withTotalLevel(PlayerSave save, int target) {
  if (save.skills.isEmpty) {
    return save.copyWith(
      skills: <SkillProgress>[SkillProgress(skillId: 'SKL-0001', level: target, xp: 0)],
    );
  }
  final current = totalLevel(save);
  final first = save.skills.first;
  final next = first.level + (target - current);
  if (next < 1) {
    return save.copyWith(skills: <SkillProgress>[first.copyWith(level: target)]);
  }
  return save.copyWith(
    skills: <SkillProgress>[
      first.copyWith(level: next),
      ...save.skills.skip(1),
    ],
  );
}
