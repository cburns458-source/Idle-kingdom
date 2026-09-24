import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/production_panel.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  /// The town kitchen, whose first recipe bakes a potato from a raw one.
  const kitchenActivityId = 'ACT-0017';
  const kitchenLocationId = 'LOC-0023';
  const rawPotatoId = 'ITEM-0025';
  const rawPerchId = 'ITEM-0047';
  const bakedPotatoRecipeId = 'RCP-0001';

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  ActivityRow kitchen() => database.launchIndexes.activitiesById[kitchenActivityId]!;

  PlayerSave cook({num potatoes = 10}) {
    return startedCharacter(database).copyWith(
      currentLocationId: kitchenLocationId,
      inventory: [InventoryStack(itemId: rawPotatoId, quantity: potatoes)],
    );
  }

  testWidgets('queues the number of crafts the materials allow', (tester) async {
    final controller = buildController(database, seed: cook());
    addTearDown(controller.dispose);

    await pumpPanel(tester, ProductionPicker(controller: controller, activity: kitchen()));

    expect(find.textContaining('Baked Potato'), findsWidgets);
    expect(find.byTooltip('Potato'), findsOne);
    // Ten potatoes in the bag, so ten crafts of one potato each.
    expect(find.textContaining('materials 10'), findsOne);

    await tester.tap(find.widgetWithText(GameButton, 'Max'));
    await tester.pump();
    await tester.tap(find.text('Start queue'));
    await tester.pump();

    expect(controller.save.productionRecipeId, bakedPotatoRecipeId);
    expect(controller.save.productionQuantityTotal, 10);
    expect(controller.save.currentActivityId, kitchenActivityId);
  });

  testWidgets('hides recipes the bag cannot make and keeps them in the book', (tester) async {
    final controller = buildController(database, seed: cook(potatoes: 0));
    addTearDown(controller.dispose);

    await pumpPanel(tester, ProductionPicker(controller: controller, activity: kitchen()));

    expect(find.text('Start queue'), findsNothing);
    expect(find.textContaining('No recipes you can make right now'), findsOne);

    await tester.tap(find.text('Recipe book'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unlocks at Cooking'), findsWidgets);
    await tester.tap(find.widgetWithText(GameButton, 'Other'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Baked potato'), findsWidgets);
  });

  testWidgets('shows soup stock from kitchen water and scraps with an empty bag', (tester) async {
    final cook16 = startedCharacter(database).copyWith(
      currentLocationId: kitchenLocationId,
      inventory: const <InventoryStack>[],
      skills: [
        for (final row in startedCharacter(database).skills)
          if (row.skillId == 'SKL-0007') row.copyWith(level: 16) else row,
      ],
    );
    final controller = buildController(database, seed: cook16);
    addTearDown(controller.dispose);

    await pumpPanel(tester, ProductionPicker(controller: controller, activity: kitchen()));

    expect(find.textContaining('Soup Stock'), findsWidgets);
    expect(find.textContaining('materials ∞'), findsOne);
    expect(find.text('∞/1'), findsNWidgets(2));
    expect(find.byTooltip('Water'), findsOne);
    expect(find.byTooltip('Kitchen Scraps'), findsOne);

    await tester.tap(find.widgetWithText(GameButton, 'Max'));
    await tester.pump();
    await tester.tap(find.text('Start queue'));
    await tester.pump();

    expect(controller.save.productionRecipeId, 'RCP-0068');
    expect(controller.save.productionQuantityTotal, 3085);
    expect(controller.save.inventory, isEmpty);
  });

  testWidgets('starts the quantity over when the recipe changes', (tester) async {
    final controller = buildController(
      database,
      seed: cook().copyWith(
        inventory: const [
          InventoryStack(itemId: rawPotatoId, quantity: 10),
          InventoryStack(itemId: rawPerchId, quantity: 4),
        ],
      ),
    );
    addTearDown(controller.dispose);

    await pumpPanel(tester, ProductionPicker(controller: controller, activity: kitchen()));
    await tester.tap(find.widgetWithText(GameButton, 'Max'));
    await tester.pump();
    expect(find.widgetWithText(GameButton, '10'), findsOne);

    // Picking another recipe starts over at one, since its materials differ.
    await tester.tap(find.byType(GameDropdown<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Cooked Perch').last);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(GameButton, '1'), findsOne);
  });
}
