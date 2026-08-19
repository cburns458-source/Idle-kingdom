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

  test('chat filter starts on and can be turned off', () {
    final net = buildMultiplayer(database);
    addTearDown(net.dispose);
    expect(net.filterChatProfanity, isTrue);
    net.setFilterChatProfanity(false);
    expect(net.filterChatProfanity, isFalse);
  });

  testWidgets('Settings shows the testing tools and the chat filter', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(900, 2400));

    await openChinScreen(tester, 'Settings');
    await tester.scrollUntilVisible(
      find.text('Filter chat'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('Filter chat'), findsOne);
    expect(find.text('Guild tag on HUD'), findsOne);
    expect(find.text('Show title on HUD'), findsOne);
    expect(find.text('Hide chat bubble'), findsOne);
    expect(find.text('Browse social pages'), findsNothing);
    expect(find.text('Move this save'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Testing tools'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.bySemanticsLabel('Spawn critter'), findsOne);
    expect(find.bySemanticsLabel('Change race'), findsOne);
    expect(find.bySemanticsLabel('Add 1'), findsOne);
    expect(find.bySemanticsLabel('Add 10'), findsOne);
    expect(find.bySemanticsLabel('Add 100'), findsOne);
    expect(find.bySemanticsLabel('Add 1 level'), findsOne);
    expect(find.bySemanticsLabel('Remove 1 level'), findsOne);
    expect(find.bySemanticsLabel('Reset all skills'), findsOne);

    await tester.scrollUntilVisible(
      find.text('Player sprite'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('Player sprite'), findsOne);
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

  testWidgets('Leaderboards open for a signed-in player', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(900, 2400));

    await openChinScreen(tester, 'Leaderboards');
    expect(find.text(signInPrompt), findsNothing);
    expect(find.text('Board'), findsOne);
    expect(find.bySemanticsLabel('Update my ranking'), findsOne);
  });

  testWidgets('browse social pages shows guilds, chat, and nearby while signed in', (tester) async {
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
    expect(find.text('Send'), findsOne);
    expect(
      net.messages.map((message) => message.body),
      contains('The Watch holds the meadow road.'),
    );

    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    await tester.tap(find.byTooltip('Meadow'));
    await tester.pump();
    await tester.tap(find.byTooltip('Nearby adventurers'));
    await tester.pump();
    await tester.pump();
    expect(find.text(signInPrompt), findsNothing);
    expect(find.text('Mira'), findsOne);
  });
}
