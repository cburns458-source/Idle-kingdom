import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/bank_panel.dart';
import 'package:idle_kingdoms/src/ui/location_view.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  const clayId = 'ITEM-0002';
  const oreId = 'ITEM-0003';

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  PlayerSave stashed({
    List<InventoryStack> inventory = const [],
    List<InventoryStack> bank = const [],
  }) {
    return startedCharacter(database).copyWith(inventory: inventory, bank: bank);
  }

  testWidgets('deposits from the bag and withdraws back', (tester) async {
    final controller = buildController(
      database,
      seed: stashed(inventory: [const InventoryStack(itemId: clayId, quantity: 5)]),
    );
    addTearDown(controller.dispose);

    await pumpPanel(tester, BankPanel(controller: controller));
    await tester.tap(find.text('Clay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Max'));
    await tester.pump();
    await tester.tap(find.text('Deposit'));
    await tester.pumpAndSettle();

    expect(controller.save.inventory, isEmpty);
    expect(controller.save.bank.single.itemId, clayId);
    expect(controller.save.bank.single.quantity, 5);

    await tester.tap(find.text('Clay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Max'));
    await tester.pump();
    await tester.tap(find.text('Withdraw'));
    await tester.pumpAndSettle();

    expect(controller.save.bank, isEmpty);
    expect(controller.save.inventory.single.quantity, 5);
  });

  testWidgets('filters both sides by the search field', (tester) async {
    final controller = buildController(
      database,
      seed: stashed(
        inventory: [const InventoryStack(itemId: clayId, quantity: 2)],
        bank: [const InventoryStack(itemId: oreId, quantity: 3)],
      ),
    );
    addTearDown(controller.dispose);

    await pumpPanel(tester, BankPanel(controller: controller));
    expect(find.text('Clay'), findsOne);
    expect(find.text('Copper Ore'), findsOne);

    await tester.enterText(find.byType(TextField), 'copper');
    await tester.pump();

    expect(find.text('Clay'), findsNothing);
    expect(find.text('Copper Ore'), findsOne);
  });

  testWidgets('offers the bank at Town and hides it in the Meadow', (tester) async {
    final town = buildController(database, seed: startedCharacter(database));
    addTearDown(town.dispose);
    await pumpPanel(
      tester,
      LocationView(
        controller: town,
        multiplayer: buildMultiplayer(database),
        onOpenMap: () {},
        onOpenSubMap: (_) {},
      ),
    );
    expect(find.text('Item storage'), findsOne);

    final meadow = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    addTearDown(meadow.dispose);
    await pumpPanel(
      tester,
      LocationView(
        controller: meadow,
        multiplayer: buildMultiplayer(database),
        onOpenMap: () {},
        onOpenSubMap: (_) {},
      ),
    );
    expect(find.text('Item storage'), findsNothing);
  });
}
