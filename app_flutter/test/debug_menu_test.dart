import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  num potatoCount(PlayerSave save) {
    return save.inventory.fold<num>(
      0,
      (sum, stack) => stack.itemId == 'ITEM-0025' ? sum + stack.quantity : sum,
    );
  }

  test('debug tools spawn a critter, change race, grant items, and move skill levels', () {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0001'),
    );
    addTearDown(controller.dispose);

    expect(controller.debugSpawnCritter(), 'Fly appeared.');
    expect(controller.save.activeCritterSpawns, isNotEmpty);
    expect(controller.debugSpawnCritter(), 'A Critter is already waiting here.');

    expect(controller.save.raceId, 'RACE-0001');
    expect(controller.debugChangeRace('RACE-0006'), 'Race is now Dwarf.');
    expect(controller.save.raceId, 'RACE-0006');

    final beforePotatoes = potatoCount(controller.save);
    expect(controller.debugGrantItem('ITEM-0025', 10), 'Added 10 Potato.');
    expect(potatoCount(controller.save), beforePotatoes + 10);
    expect(controller.debugGrantItem('ITEM-0025', 100), 'Added 100 Potato.');
    expect(potatoCount(controller.save), beforePotatoes + 110);

    expect(getSkillProgress(controller.save, combatSkillId).level, 1);
    expect(controller.debugAddSkillLevels(combatSkillId, 10), 'Combat is now level 11.');
    expect(getSkillProgress(controller.save, combatSkillId).level, 11);
    expect(controller.debugRemoveSkillLevels(combatSkillId, 1), 'Combat is now level 10.');
    expect(getSkillProgress(controller.save, combatSkillId).level, 10);
    expect(controller.debugResetAllSkills(), 'Every skill is back at level 1.');
    expect(controller.save.skills.every((skill) => skill.level == 1 && skill.xp == 0), isTrue);
  });

  testWidgets('Settings shows the testing tools and the social browse switch', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(900, 2400));

    await openChinScreen(tester, 'Settings');
    await tester.scrollUntilVisible(
      find.text('Testing tools'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(find.text('Browse social pages'), findsOne);
    expect(find.bySemanticsLabel('Spawn critter'), findsOne);
    expect(find.bySemanticsLabel('Change race'), findsOne);
    expect(find.bySemanticsLabel('Add 1'), findsOne);
    expect(find.bySemanticsLabel('Add 10'), findsOne);
    expect(find.bySemanticsLabel('Add 100'), findsOne);
    expect(find.bySemanticsLabel('Add 1 level'), findsOne);
    expect(find.bySemanticsLabel('Remove 1 level'), findsOne);
    expect(find.bySemanticsLabel('Reset all skills'), findsOne);
  });

  testWidgets('Settings testing buttons change the save', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0001'),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(900, 2400));

    await openChinScreen(tester, 'Settings');
    await tester.scrollUntilVisible(
      find.bySemanticsLabel('Spawn critter'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Spawn critter'));
    await tester.pump();
    expect(controller.save.activeCritterSpawns.single.critterId, 'CRT-0001');
    expect(find.text('Fly appeared.'), findsOne);

    final beforePotatoes = potatoCount(controller.save);
    await tester.tap(find.bySemanticsLabel('Add 1'));
    await tester.pump();
    expect(potatoCount(controller.save), beforePotatoes + 1);

    await tester.tap(find.bySemanticsLabel('Add 1 level'));
    await tester.pump();
    expect(getSkillProgress(controller.save, combatSkillId).level, 2);
  });

  testWidgets('Leaderboards stay behind a sign-in wall until browse is turned on', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    await pumpShell(tester, controller, multiplayer: net, size: const Size(900, 2400));

    await openChinScreen(tester, 'Leaderboards');
    expect(find.text(signInPrompt), findsOne);
    expect(find.text('Board'), findsNothing);

    await openChinScreen(tester, 'Settings');
    await tester.scrollUntilVisible(
      find.text('Browse social pages'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.byType(Switch).at(2));
    await tester.pump();
    await tester.pump();

    expect(net.canBrowseSocial, isTrue);
    await openChinScreen(tester, 'Leaderboards');
    await tester.pump();
    expect(find.text(signInPrompt), findsNothing);
    expect(find.text('Board'), findsOne);
    expect(find.bySemanticsLabel('Update my ranking'), findsOne);
  });

  testWidgets('browse social pages shows guilds, chat, and nearby without an account', (
    tester,
  ) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: demoMiraLocationId),
    );
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    net.setBrowseSocialUnsigned(true);
    await net.refresh(controller.save);

    await pumpShell(tester, controller, multiplayer: net, size: const Size(900, 2400));

    await openChinScreen(tester, 'Guilds');
    await tester.pump();
    expect(find.text(guildSignInPrompt), findsNothing);
    expect(find.text('[WCH] The Watch'), findsOne);

    await tester.tap(find.byTooltip('Open chat'));
    await tester.pump();
    await tester.pump();
    expect(find.text(signInPrompt), findsNothing);
    expect(find.text('Global'), findsWidgets);
    expect(find.text('The Watch holds the meadow road.'), findsOne);

    await tester.tap(find.byTooltip('Close chat'));
    await tester.pump();
    await tester.tap(find.byTooltip('Nearby adventurers'));
    await tester.pump();
    await tester.pump();
    expect(find.text(signInPrompt), findsNothing);
    expect(find.text('Mira'), findsOne);
  });
}
