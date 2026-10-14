import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/dialogue_text.dart';
import 'package:idle_kingdoms/src/ui/format.dart';
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

  testWidgets('a buy spends plaza points through plaza_shop_buy and updates the balance', (
    tester,
  ) async {
    final controller = buildController(database, seed: shopper(points: 210));
    addTearDown(controller.dispose);
    final commands = <String>[];
    final args = <Map<String, Object?>>[];
    controller.submitGameCommand = (command, [commandArgs = const <String, Object?>{}]) async {
      commands.add(command);
      args.add(commandArgs);
      return null;
    };

    await pumpPanel(tester, ShopPanel(controller: controller, shopId: shopId));
    expect(find.text('210 plaza points'), findsWidgets);

    final cuirassBuy = tester.widget<GameButton>(find.byKey(const Key('plaza-buy-$cuirassId')));
    expect(cuirassBuy.onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('plaza-buy-$cuirassId')));
    await tester.pump();

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
    controller.submitGameCommand = (command, [commandArgs = const <String, Object?>{}]) async {
      commands.add(command);
      return null;
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
}
