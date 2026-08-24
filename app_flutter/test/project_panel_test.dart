import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/project_panel.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  /// The forge, where Smithing projects are made, and the mage tower.
  const forgeLocationId = 'LOC-0025';
  const mageLocationId = 'LOC-0007';
  const copperAxeProject = 'PRJ-0007';
  const copperAxeItem = 'ITEM-0132';

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  /// A location can hold more than one station, so pick the one for [skillId].
  SpecialProductionStation stationFor(String locationId, String skillId) {
    return specialProductionStationsAt(
      database.launch,
      locationId,
    ).firstWhere((station) => station.skillId == skillId);
  }

  PlayerSave smith() {
    final base = startedCharacter(database);
    return base.copyWith(
      currentLocationId: forgeLocationId,
      gold: 50000,
      unlockedNpcIds: const ['NPC-0003'],
      skills: base.skills
          .map(
            (skill) => const ['SKL-0011', 'SKL-0008', 'SKL-0012'].contains(skill.skillId)
                ? SkillProgress(skillId: skill.skillId, level: 40, xp: 500000)
                : skill,
          )
          .toList(),
      inventory: const [
        InventoryStack(itemId: 'ITEM-0074', quantity: 40),
        InventoryStack(itemId: 'ITEM-0214', quantity: 8),
        InventoryStack(itemId: 'ITEM-0084', quantity: 30),
      ],
    );
  }

  testWidgets('completes the chosen project and shows what it gave', (tester) async {
    final controller = buildController(database, seed: smith());
    addTearDown(controller.dispose);

    await pumpPanel(
      tester,
      ProjectPicker(controller: controller, station: stationFor(forgeLocationId, 'SKL-0011')),
    );
    expect(find.text('Smithing forge'), findsOne);

    await tester.tap(find.byType(GameDropdown<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Copper Axe → Copper Axe').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete project'));
    await tester.pumpAndSettle();

    expect(inventoryCount(controller.save, copperAxeItem), 1);
    expect(find.text('Copper Axe'), findsWidgets);
    expect(find.textContaining('XP'), findsWidgets);

    await tester.tap(find.text('Collect'));
    await tester.pumpAndSettle();
    expect(controller.message, contains('Completed Copper Axe'));
  });

  testWidgets('makes several at once, up to what the materials allow', (tester) async {
    final controller = buildController(database, seed: smith());
    addTearDown(controller.dispose);
    final maxQuantity = projectDetail(
      database.launch,
      controller.save,
      copperAxeProject,
    )!.maxQuantity;

    await pumpPanel(
      tester,
      ProjectPicker(controller: controller, station: stationFor(forgeLocationId, 'SKL-0011')),
    );
    await tester.tap(find.byType(GameDropdown<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Copper Axe → Copper Axe').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Max'));
    await tester.pump();
    await tester.tap(find.text('Complete project'));
    await tester.pumpAndSettle();

    expect(inventoryCount(controller.save, copperAxeItem), maxQuantity);
    expect(find.textContaining('Crafted $maxQuantity times'), findsOne);
  });

  testWidgets('lists projects in a dropdown', (tester) async {
    final controller = buildController(database, seed: smith());
    addTearDown(controller.dispose);

    await pumpPanel(
      tester,
      ProjectPicker(controller: controller, station: stationFor(forgeLocationId, 'SKL-0011')),
    );
    expect(find.byType(GameDropdown<String>), findsOne);
    await tester.tap(find.byType(GameDropdown<String>));
    await tester.pumpAndSettle();
    expect(find.textContaining('Copper Axe → Copper Axe'), findsWidgets);
  });

  testWidgets('the recipe book lists locked projects the dropdown hides', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: forgeLocationId),
    );
    addTearDown(controller.dispose);

    await pumpPanel(
      tester,
      ProjectPicker(controller: controller, station: stationFor(forgeLocationId, 'SKL-0011')),
    );
    expect(find.byType(GameDropdown<String>), findsNothing);
    expect(find.textContaining('speak with the Master Dwarf'), findsOne);

    await tester.tap(find.text('Recipe book'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unknown recipe'), findsWidgets);
    expect(find.text('Complete project'), findsNothing);
  });

  testWidgets('says which mentor unlocks a station', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: forgeLocationId),
    );
    addTearDown(controller.dispose);

    await pumpPanel(
      tester,
      ProjectPicker(controller: controller, station: stationFor(forgeLocationId, 'SKL-0011')),
    );
    expect(find.textContaining('speak with the Master Dwarf'), findsOne);
    expect(find.text('Complete project'), findsNothing);
  });

  testWidgets('an enchantment asks which item receives it', (tester) async {
    final base = startedCharacter(database);
    final controller = buildController(
      database,
      seed: base.copyWith(
        currentLocationId: mageLocationId,
        gold: 10000,
        unlockedNpcIds: const ['NPC-0004'],
        skills: base.skills
            .map(
              (skill) => skill.skillId == 'SKL-0013'
                  ? SkillProgress(skillId: skill.skillId, level: 40, xp: 900000)
                  : skill,
            )
            .toList(),
        inventory: const [
          InventoryStack(itemId: 'ITEM-0098', quantity: 2),
          InventoryStack(itemId: 'ITEM-0011', quantity: 300),
          InventoryStack(itemId: 'ITEM-0040', quantity: 2),
          InventoryStack(itemId: copperAxeItem, quantity: 1),
        ],
      ),
    );
    addTearDown(controller.dispose);

    await pumpPanel(
      tester,
      ProjectPicker(controller: controller, station: stationFor(mageLocationId, 'SKL-0013')),
    );
    await tester.tap(find.byType(GameDropdown<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Minor Combat Enchantment').last);
    await tester.pumpAndSettle();
    expect(find.text('Item to enchant'), findsOne);

    await tester.tap(find.text('Complete project'));
    await tester.pumpAndSettle();

    final enchanted = controller.save.inventory.where(
      (stack) => stack.itemId == copperAxeItem && stack.enchantmentId != null,
    );
    expect(enchanted, hasLength(1));
  });
}
