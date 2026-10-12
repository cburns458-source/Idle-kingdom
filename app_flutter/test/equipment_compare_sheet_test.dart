import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/item_detail_sheet.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('Compare expands deltas without equipping', (tester) async {
    var save = startedCharacter(database);
    save = raiseSkillToMinimumLevel(save, database.launch, mightSkillId, 20).save;
    save = equipStackToSlot(save, weaponToolSlotId, 'ITEM-0124', 1);
    save = addItemToInventory(save, 'ITEM-0128', 1);
    final controller = buildController(database, seed: save);
    addTearDown(controller.dispose);

    await pumpPanel(
      tester,
      ItemDetailSheet(
        controller: controller,
        itemId: 'ITEM-0128',
        quantity: 1,
        allowCompare: true,
        onEquip: () => fail('Compare must not equip'),
      ),
    );

    expect(find.text('Compare'), findsOneWidget);
    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();

    expect(find.text('Hide'), findsOneWidget);
    expect(find.text('Equipped'), findsOneWidget);
    expect(find.text('This item'), findsOneWidget);
    expect(find.textContaining('Min damage:'), findsNWidgets(2));
    final equippedLabel = tester.getRect(find.text('Equipped'));
    final candidateLabel = tester.getRect(find.text('This item'));
    expect(candidateLabel.top, greaterThan(equippedLabel.bottom));
    expect(find.textContaining('Attack damage'), findsNothing);
    expect(controller.save.equipment.slots[weaponToolSlotId]?.itemId, 'ITEM-0124');
  });

  testWidgets('Compare is hidden for non-equippable bag items', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database)
          .copyWith(inventory: const [InventoryStack(itemId: 'ITEM-0003', quantity: 2)]),
    );
    addTearDown(controller.dispose);

    await pumpPanel(
      tester,
      ItemDetailSheet(
        controller: controller,
        itemId: 'ITEM-0003',
        quantity: 2,
        allowCompare: false,
      ),
    );

    expect(find.text('Compare'), findsNothing);
  });
}
