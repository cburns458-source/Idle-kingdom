import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/game_controller.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/dialogue_text.dart';
import 'package:idle_kingdoms/src/ui/format.dart';
import 'package:idle_kingdoms/src/ui/item_icon.dart';
import 'package:idle_kingdoms/src/ui/plaza_points.dart';
import 'package:idle_kingdoms/src/ui/shop_panel.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  const shopId = plazaShopId;
  const cuirassId = hearthguardCuirassId;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  PlayerSave shopper({num points = 0, List<InventoryStack> inventory = const []}) {
    return startedCharacter(database)
        .copyWith(currentLocationId: citadelPlazaId, plazaPoints: points, inventory: inventory);
  }

  List<InventoryStack> filledBag() {
    return [
      for (var index = 0; index < inventorySlotLimit; index++)
        InventoryStack(itemId: 'FILL-$index', quantity: 1),
    ];
  }

  testWidgets('prices and header use plaza points, and Buy is greyed when unaffordable', (
    tester,
  ) async {
    final controller = buildController(database, seed: shopper());
    addTearDown(controller.dispose);

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));

    expect(find.text('Hearthguard Shop'), findsOne);
    expect(find.byKey(const Key('plaza-points-balance')), findsOne);
    expect(find.text('0 plaza points'), findsOne);
    expect(find.text('Confirm trade'), findsNothing);
    expect(find.textContaining('gold'), findsNothing);

    for (final row in plazaShopStock) {
      expect(find.text('${formatThousands(row.points)} plaza points'), findsWidgets);
    }

    final buttons = tester.widgetList<GameButton>(find.widgetWithText(GameButton, 'Buy')).toList();
    expect(buttons, hasLength(plazaShopStock.length));
    expect(buttons.every((button) => button.onPressed == null), isTrue);
  });

  testWidgets('offline and local play disable Buy and a tap changes nothing', (tester) async {
    final controller = buildController(database, seed: shopper(points: 210));
    addTearDown(controller.dispose);
    final commands = <String>[];
    controller.submitGameCommand = (command, [commandArgs = const <String, Object?>{}]) async {
      commands.add(command);
      return null;
    };

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));

    expect(find.text(plazaShopNeedsConnection), findsOne);
    final buttons = tester.widgetList<GameButton>(find.widgetWithText(GameButton, 'Buy')).toList();
    expect(buttons, hasLength(plazaShopStock.length));
    expect(buttons.every((button) => button.onPressed == null), isTrue);

    await tester.tap(find.byKey(const Key('plaza-buy-$cuirassId')));
    await tester.pump();

    expect(commands, isEmpty);
    expect(plazaPointsOf(controller.save), 210);
    expect(inventoryCount(controller.save, cuirassId), 0);
    expect(find.text('-210 plaza points'), findsNothing);
    expect(controller.message, isNull);
  });

  testWidgets('a buy spends plaza points through plaza_shop_buy and updates the balance', (
    tester,
  ) async {
    final controller = buildController(database, seed: shopper(points: 210));
    addTearDown(controller.dispose);
    final commands = <String>[];
    final args = <Map<String, Object?>>[];
    controller.hostedPlay = () => true;
    controller.submitGameCommand = (command, [commandArgs = const <String, Object?>{}]) async {
      return null;
    };
    controller.submitHostedCommand = (command, [commandArgs = const <String, Object?>{}]) async {
      commands.add(command);
      args.add(commandArgs);
      return HostedCommandReceipt(
        pointsSpent: 210,
        plazaPoints: 0,
        save: controller.save.copyWith(
          plazaPoints: 0,
          inventory: const [InventoryStack(itemId: cuirassId, quantity: 1)],
        ),
      );
    };

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));
    expect(find.text('210 plaza points'), findsWidgets);
    expect(find.text(plazaShopNeedsConnection), findsNothing);

    final cuirassBuy = tester.widget<GameButton>(find.byKey(const Key('plaza-buy-$cuirassId')));
    expect(cuirassBuy.onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('plaza-buy-$cuirassId')));
    await tester.pumpAndSettle();

    expect(commands, ['plaza_shop_buy']);
    expect(args.single['itemId'], cuirassId);
    expect(plazaPointsOf(controller.save), 0);
    expect(inventoryCount(controller.save, cuirassId), 1);
    expect(controller.message, plazaPointsSpentNotice(210));
    expect(find.text('-210 plaza points'), findsOne);
    expect(find.byKey(const Key('plaza-points-balance')), findsOne);
    expect(
      tester.widget<Text>(find.byKey(const Key('plaza-points-balance'))).data,
      '0 plaza points',
    );
  });

  testWidgets('a full bag refuses the buy, spends no points, and shows the bag popup first', (
    tester,
  ) async {
    final controller = buildController(
      database,
      seed: shopper(points: 210, inventory: filledBag()),
    );
    addTearDown(controller.dispose);
    final commands = <String>[];
    controller.hostedPlay = () => true;
    controller.submitGameCommand = (command, [commandArgs = const <String, Object?>{}]) async {
      return null;
    };
    controller.submitHostedCommand = (command, [commandArgs = const <String, Object?>{}]) async {
      commands.add(command);
      return const HostedCommandReceipt();
    };

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));
    await tester.tap(find.byKey(const Key('plaza-buy-$cuirassId')));
    await tester.pumpAndSettle();

    expect(find.text(DialogueText.bagFull(1)), findsOne);
    expect(find.text('-210 plaza points'), findsNothing);
    expect(controller.message, isNull);
    expect(commands, isEmpty);
    expect(plazaPointsOf(controller.save), 210);
    expect(inventoryCount(controller.save, cuirassId), 0);
    expect(controller.save.inventory, hasLength(inventorySlotLimit));

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('-210 plaza points'), findsNothing);
    expect(controller.message, isNull);
    expect(plazaPointsOf(controller.save), 210);
  });

  testWidgets('a full bag still buys when the piece can join an existing stack', (tester) async {
    final controller = buildController(
      database,
      seed: shopper(
        points: 210,
        inventory: [
          const InventoryStack(itemId: cuirassId, quantity: 1),
          for (var index = 0; index < inventorySlotLimit - 1; index++)
            InventoryStack(itemId: 'FILL-$index', quantity: 1),
        ],
      ),
    );
    addTearDown(controller.dispose);
    final commands = <String>[];
    controller.hostedPlay = () => true;
    controller.submitGameCommand = (command, [commandArgs = const <String, Object?>{}]) async {
      return null;
    };
    controller.submitHostedCommand = (command, [commandArgs = const <String, Object?>{}]) async {
      commands.add(command);
      return HostedCommandReceipt(
        pointsSpent: 210,
        plazaPoints: 0,
        save: controller.save.copyWith(
          plazaPoints: 0,
          inventory: [
            const InventoryStack(itemId: cuirassId, quantity: 2),
            for (final stack in controller.save.inventory)
              if (stack.itemId != cuirassId) stack,
          ],
        ),
      );
    };

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));
    await tester.tap(find.byKey(const Key('plaza-buy-$cuirassId')));
    await tester.pumpAndSettle();

    expect(commands, ['plaza_shop_buy']);
    expect(plazaPointsOf(controller.save), 0);
    expect(inventoryCount(controller.save, cuirassId), 2);
    expect(controller.save.inventory, hasLength(inventorySlotLimit));
    expect(find.text('-210 plaza points'), findsOne);
  });

  testWidgets('hosted refuse after send keeps in-flight progress and shows no -N', (tester) async {
    final controller = buildController(database, seed: shopper(points: 210));
    addTearDown(controller.dispose);
    final commands = <String>[];
    final gate = Completer<HostedCommandReceipt>();
    controller.hostedPlay = () => true;
    controller.submitHostedCommand = (command, [commandArgs = const <String, Object?>{}]) {
      commands.add(command);
      return gate.future;
    };

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));
    await tester.tap(find.byKey(const Key('plaza-buy-$cuirassId')));
    await tester.pump();

    final first = controller.save.skills.first;
    const flightItemId = 'ITEM-FLIGHT';
    controller.commit(
      controller.save.copyWith(
        skills: [
          first.copyWith(xp: first.xp + 25),
          ...controller.save.skills.skip(1),
        ],
        inventory: [
          ...controller.save.inventory,
          const InventoryStack(itemId: flightItemId, quantity: 3),
        ],
      ),
    );
    gate.complete(const HostedCommandReceipt(reason: plazaShopInsufficientPoints));
    await tester.pumpAndSettle();

    expect(commands, ['plaza_shop_buy']);
    expect(controller.save.skills.first.xp, first.xp + 25);
    expect(inventoryCount(controller.save, flightItemId), 3);
    expect(plazaPointsOf(controller.save), 210);
    expect(inventoryCount(controller.save, cuirassId), 0);
    expect(find.text('-210 plaza points'), findsNothing);
    expect(controller.message, isNull);
    expect(find.text(plazaShopInsufficientPoints), findsOne);
  });

  testWidgets('hosted stack_full refusal shows stack-full text', (tester) async {
    final controller = buildController(database, seed: shopper(points: 210));
    addTearDown(controller.dispose);
    controller.hostedPlay = () => true;
    controller.submitHostedCommand = (command, [commandArgs = const <String, Object?>{}]) async {
      return const HostedCommandReceipt(
        reason: 'Inventory is full (84 slots).',
        code: 'no_room',
        noRoom: NoRoom(reason: 'stack_full'),
      );
    };

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));
    await tester.tap(find.byKey(const Key('plaza-buy-$cuirassId')));
    await tester.pumpAndSettle();

    expect(find.text(DialogueText.stackFull), findsOne);
    expect(find.textContaining('more item'), findsNothing);
    expect(find.text('-210 plaza points'), findsNothing);
    expect(plazaPointsOf(controller.save), 210);
    expect(inventoryCount(controller.save, cuirassId), 0);
  });

  testWidgets('hosted no_room without a slot count falls back to 1 more item', (tester) async {
    final controller = buildController(database, seed: shopper(points: 210));
    addTearDown(controller.dispose);
    controller.hostedPlay = () => true;
    controller.submitHostedCommand = (command, [commandArgs = const <String, Object?>{}]) async {
      return const HostedCommandReceipt(reason: 'Inventory is full (84 slots).', code: 'no_room');
    };

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));
    await tester.tap(find.byKey(const Key('plaza-buy-$cuirassId')));
    await tester.pumpAndSettle();

    expect(find.text(DialogueText.bagFull(1)), findsOne);
    expect(find.text(DialogueText.bagFull(3)), findsNothing);
    expect(plazaPointsOf(controller.save), 210);
  });

  testWidgets('hosted success with no save shows no -N', (tester) async {
    final controller = buildController(database, seed: shopper(points: 210));
    addTearDown(controller.dispose);
    controller.hostedPlay = () => true;
    controller.submitHostedCommand = (command, [commandArgs = const <String, Object?>{}]) async {
      return const HostedCommandReceipt(pointsSpent: 210, plazaPoints: 0);
    };

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));
    await tester.tap(find.byKey(const Key('plaza-buy-$cuirassId')));
    await tester.pumpAndSettle();

    expect(find.text('-210 plaza points'), findsNothing);
    expect(controller.message, isNull);
    expect(plazaPointsOf(controller.save), 210);
    expect(inventoryCount(controller.save, cuirassId), 0);
  });

  testWidgets('hosted no_room uses the response slot count for the bag popup', (tester) async {
    final controller = buildController(database, seed: shopper(points: 210));
    addTearDown(controller.dispose);
    controller.hostedPlay = () => true;
    controller.submitHostedCommand = (command, [commandArgs = const <String, Object?>{}]) async {
      return const HostedCommandReceipt(
        reason: 'Inventory is full (84 slots).',
        code: 'no_room',
        noRoom: NoRoom(slotsNeeded: 3, slotsFree: 0),
      );
    };

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));
    await tester.tap(find.byKey(const Key('plaza-buy-$cuirassId')));
    await tester.pumpAndSettle();

    expect(find.text(DialogueText.bagFull(3)), findsOne);
    expect(find.text(DialogueText.bagFull(1)), findsNothing);
    expect(find.text('-210 plaza points'), findsNothing);
    expect(plazaPointsOf(controller.save), 210);
    expect(inventoryCount(controller.save, cuirassId), 0);
  });

  testWidgets('hosted play while signed out disables Buy and a tap changes nothing', (
    tester,
  ) async {
    final controller = buildController(database, seed: shopper(points: 210));
    addTearDown(controller.dispose);
    final commands = <String>[];
    controller.hostedPlay = () => false;
    controller.submitHostedCommand = (command, [commandArgs = const <String, Object?>{}]) async {
      commands.add(command);
      return const HostedCommandReceipt();
    };

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));

    expect(find.text(plazaShopNeedsConnection), findsOne);
    final buttons = tester.widgetList<GameButton>(find.widgetWithText(GameButton, 'Buy')).toList();
    expect(buttons.every((button) => button.onPressed == null), isTrue);

    await tester.tap(find.byKey(const Key('plaza-buy-$cuirassId')));
    await tester.pump();

    expect(commands, isEmpty);
    expect(plazaPointsOf(controller.save), 210);
    expect(inventoryCount(controller.save, cuirassId), 0);
    expect(find.text('-210 plaza points'), findsNothing);
    expect(controller.message, isNull);
  });

  testWidgets('hosted play without submitHostedCommand disables Buy and a tap changes nothing', (
    tester,
  ) async {
    final controller = buildController(database, seed: shopper(points: 210));
    addTearDown(controller.dispose);
    final commands = <String>[];
    controller.hostedPlay = () => true;
    controller.submitGameCommand = (command, [commandArgs = const <String, Object?>{}]) async {
      commands.add(command);
      return null;
    };

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));

    expect(find.text(plazaShopNeedsConnection), findsOne);
    final buttons = tester.widgetList<GameButton>(find.widgetWithText(GameButton, 'Buy')).toList();
    expect(buttons.every((button) => button.onPressed == null), isTrue);

    await tester.tap(find.byKey(const Key('plaza-buy-$cuirassId')));
    await tester.pump();

    expect(commands, isEmpty);
    expect(plazaPointsOf(controller.save), 210);
    expect(inventoryCount(controller.save, cuirassId), 0);
    expect(find.text('-210 plaza points'), findsNothing);
  });

  testWidgets('double tap sends only one hosted buy and greys Buy while it is in flight', (
    tester,
  ) async {
    final controller = buildController(database, seed: shopper(points: 210));
    addTearDown(controller.dispose);
    final commands = <String>[];
    final gate = Completer<HostedCommandReceipt>();
    controller.hostedPlay = () => true;
    controller.submitGameCommand = (command, [commandArgs = const <String, Object?>{}]) async {
      return null;
    };
    controller.submitHostedCommand = (command, [commandArgs = const <String, Object?>{}]) {
      commands.add(command);
      return gate.future;
    };

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));
    await tester.tap(find.byKey(const Key('plaza-buy-$cuirassId')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('plaza-buy-$cuirassId')));
    await tester.pump();

    expect(commands, ['plaza_shop_buy']);
    expect(plazaPointsOf(controller.save), 210);
    expect(find.text('-210 plaza points'), findsNothing);
    final busyButtons = tester
        .widgetList<GameButton>(find.widgetWithText(GameButton, 'Buy'))
        .toList();
    expect(busyButtons.every((button) => button.onPressed == null), isTrue);

    gate.complete(
      HostedCommandReceipt(
        pointsSpent: 210,
        plazaPoints: 0,
        save: controller.save.copyWith(
          plazaPoints: 0,
          inventory: const [InventoryStack(itemId: cuirassId, quantity: 1)],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(commands, ['plaza_shop_buy']);
    expect(plazaPointsOf(controller.save), 0);
    expect(find.text('-210 plaza points'), findsOne);
  });

  testWidgets('hosted success shows -N only from the server pointsSpent', (tester) async {
    final controller = buildController(database, seed: shopper(points: 210));
    addTearDown(controller.dispose);
    controller.hostedPlay = () => true;
    controller.submitGameCommand = (command, [commandArgs = const <String, Object?>{}]) async {
      return null;
    };
    controller.submitHostedCommand = (command, [commandArgs = const <String, Object?>{}]) async {
      return HostedCommandReceipt(
        pointsSpent: 0,
        plazaPoints: 0,
        save: controller.save.copyWith(
          plazaPoints: 0,
          inventory: const [InventoryStack(itemId: cuirassId, quantity: 1)],
        ),
      );
    };

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));
    await tester.tap(find.byKey(const Key('plaza-buy-$cuirassId')));
    await tester.pumpAndSettle();

    expect(plazaPointsOf(controller.save), 0);
    expect(find.text('-210 plaza points'), findsNothing);
    expect(controller.message, isNull);
  });

  testWidgets('a gold shop header still shows gold, not plaza points', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0024', gold: 1000),
    );
    addTearDown(controller.dispose);

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: 'SHP-0001'));

    expect(find.byKey(const Key('shop-gold-balance')), findsOne);
    expect(find.byKey(const Key('plaza-points-balance')), findsNothing);
    expect(find.byType(GoldAmount), findsOne);
    expect(find.text('Hearthguard Shop'), findsNothing);
  });
}
