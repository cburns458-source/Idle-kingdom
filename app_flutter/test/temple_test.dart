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

  testWidgets('Temple lists both activities and blesses after unequipping', (tester) async {
    var seed = startedCharacter(database).copyWith(currentLocationId: 'LOC-0036', currentHp: 200);
    seed = equipStackToSlot(seed, weaponToolSlotId, 'ITEM-0100', 1);
    seed = equipStackToSlot(seed, offhandSlotId, 'ITEM-0145', 1);
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(900, 2400));

    expect(find.text('Temple'), findsWidgets);
    expect(find.text('Train with the monks'), findsOne);
    expect(find.text('Be blessed'), findsOne);

    await tapVisible(
      tester,
      find.descendant(of: dockRow('Be blessed'), matching: find.bySemanticsLabel('Start')),
    );

    expect(controller.save.currentHp, playerMaxHp(database.launch, controller.save));
    expect(slotItemId(controller.save, weaponToolSlotId), isNull);
    expect(slotItemId(controller.save, offhandSlotId), isNull);
    expect(controller.save.currentActivityId, isNull);
    expect(controller.message, 'You are blessed.');
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
}
