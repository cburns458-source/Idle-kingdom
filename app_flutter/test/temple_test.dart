import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  Finder dockRow(String title) {
    return find.ancestor(of: find.text(title), matching: find.byType(DockRow));
  }

  testWidgets('Temple lists monk training and a blessing popup', (tester) async {
    var seed = startedCharacter(database).copyWith(currentLocationId: 'LOC-0036', currentHp: 200);
    seed = equipStackToSlot(seed, weaponToolSlotId, 'ITEM-0100', 1);
    seed = equipStackToSlot(seed, offhandSlotId, 'ITEM-0145', 1);
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(900, 2400));

    expect(find.text('Temple'), findsWidgets);
    expect(find.text('Train with the monks'), findsOne);
    expect(find.text('Pick weeds'), findsOne);
    expect(find.text('Blessing'), findsOne);
    expect(find.text('Be blessed'), findsOne);
    expect(find.bySemanticsLabel('Bless'), findsOne);

    await tapVisible(
      tester,
      find.descendant(of: dockRow('Be blessed'), matching: find.bySemanticsLabel('Bless')),
    );
    await tester.pump();

    expect(controller.save.currentHp, playerMaxHp(database.launch, controller.save));
    expect(slotItemId(controller.save, weaponToolSlotId), 'ITEM-0100');
    expect(slotItemId(controller.save, offhandSlotId), 'ITEM-0145');
    expect(controller.save.currentActivityId, isNull);
    expect(find.byKey(const Key('game-popup')), findsOne);
    expect(
      find.descendant(
        of: find.byKey(const Key('game-popup')),
        matching: find.text('The monks restore you to full health.'),
      ),
      findsOne,
    );

    await tester.tap(find.text('OK'));
    await tester.pump();
    expect(find.byKey(const Key('game-popup')), findsNothing);
  });

  testWidgets('Train with the monks starts an unarmed Monk fight', (tester) async {
    var seed = startedCharacter(database).copyWith(currentLocationId: 'LOC-0036');
    seed = equipStackToSlot(seed, weaponToolSlotId, 'ITEM-0100', 1);
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(900, 2400));

    await tapVisible(
      tester,
      find.descendant(
        of: dockRow('Train with the monks'),
        matching: find.bySemanticsLabel('Start'),
      ),
    );

    expect(controller.save.currentActivityId, 'ACT-0035');
    expect(controller.save.combatEnemyId, 'ENM-0020');
    expect(slotItemId(controller.save, weaponToolSlotId), isNull);
    expect(find.text('Monk'), findsWidgets);
  });

  testWidgets('the monks refuse to let anything into either hand', (tester) async {
    var seed = startedCharacter(database).copyWith(currentLocationId: 'LOC-0036');
    // A wooden sword and shield, both of which a level-1 character can wear.
    seed = addItemToInventory(seed, 'ITEM-0124', 1);
    seed = addItemToInventory(seed, 'ITEM-0145', 1);
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(900, 2400));

    for (final itemId in <String>['ITEM-0124', 'ITEM-0145']) {
      final refusal = equipItemFromInventory(database.launch, controller.save, itemId);
      expect(refusal.ok, isFalse, reason: '$itemId should be refused at the Temple');
      expect(refusal.reason, 'The monks keep your hands empty at the Temple.');
    }

    // The same gear goes on fine once the player is off the Temple's ground.
    final away = controller.save.copyWith(currentLocationId: 'LOC-0002');
    expect(equipItemFromInventory(database.launch, away, 'ITEM-0124').ok, isTrue);
    expect(equipItemFromInventory(database.launch, away, 'ITEM-0145').ok, isTrue);
  });
}
