import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/npc_panel.dart';
import 'package:idle_kingdoms/src/ui/tutorial_spotlight.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('tutorial lock hides other places and shows the next-step line', (tester) async {
    final controller = buildController(database, seed: tutorialCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(400, 900));
    await tester.pump();

    expect(isTutorialLocked(controller.save), isTrue);
    expect(find.byType(TutorialHintBar), findsOneWidget);
    expect(find.textContaining('Gather potatoes'), findsOneWidget);
    expect(find.byTooltip('Skills'), findsNothing);
    expect(find.byTooltip('Open menu'), findsNothing);
    expect(find.text('Bank'), findsNothing);
  });

  PlayerSave combatStep({String raceId = 'RACE-0001'}) {
    final assigned = assignRace(
      database.launch,
      createNewSave(database.launch, testStartMs).copyWith(characterName: 'Tester'),
      raceId,
    );
    var save = assigned.save!.copyWith(hasSeenFennelIntro: true);
    save = save.copyWith(
      quests: [
        for (final quest in save.quests)
          if (quest.questId == tutorialQuestId)
            quest.copyWith(
              counters: const {
                'step:QSTP-0013': 1,
                'step:QSTP-0014': 1,
                'step:QSTP-0015': 1,
                'step:QSTP-0016': 1,
              },
            )
          else
            quest,
      ],
    );
    return applyQuestStepUnlocks(database.launch, save);
  }

  NpcRow fennel() => database.launch.npcs.singleWhere((npc) => npc.npcId == tutorialNpcId);

  testWidgets('the cow-kill farewell opens Fennel at the bottom of the screen', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(dialogueFlags: const [tutorialFarewellFlag]),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(400, 900));
    await tester.pump();

    expect(find.byKey(const Key('fennel-dialogue-panel')), findsOneWidget);
    expect(find.text('Well, that settles that.'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('talking to Fennel on the cow step uses Quest\'s sword node, not the QDL panel', (
    tester,
  ) async {
    final controller = buildController(database, seed: combatStep());
    addTearDown(controller.dispose);
    await pumpPanel(tester, NpcPanel(controller: controller, npc: fennel(), onClose: () {}));
    await tester.pump();

    expect(find.byKey(const Key('fennel-dialogue-panel')), findsOneWidget);
    expect(
      find.text(
        "That cow's been trouble all week. Put on your sword and shield before you go near her.",
      ),
      findsOneWidget,
    );
    expect(find.text('Grab your dagger before you go near her.'), findsNothing);
    expect(find.text("I'll handle her."), findsOneWidget);
  });

  testWidgets('a bag with a Wooden dagger opens Quest\'s dagger node', (tester) async {
    final controller = buildController(database, seed: combatStep(raceId: 'RACE-0005'));
    addTearDown(controller.dispose);
    expect(
      controller.save.inventory.any((stack) => stack.itemId == tutorialStarterDaggerId),
      isTrue,
    );
    await pumpPanel(tester, NpcPanel(controller: controller, npc: fennel(), onClose: () {}));
    await tester.pump();

    expect(find.byKey(const Key('fennel-dialogue-panel')), findsOneWidget);
    expect(
      find.text("That cow's been trouble all week. Grab your dagger before you go near her."),
      findsOneWidget,
    );
    expect(find.textContaining('sword and shield'), findsNothing);
    expect(find.text("I'll handle her."), findsOneWidget);
  });

  testWidgets('auto-dialogue flags open Quest nodes DNODE-0028 to DNODE-0030', (tester) async {
    const cases = [
      (tutorialLossFlag, "She got you, didn't she? Dust off and try again."),
      (tutorialFoodGrantFlag, 'Out of food? Here, eat these and get back out there.'),
      (tutorialLockbackFlag, "Back so soon? Let's finish what we started."),
    ];
    for (final (flag, line) in cases) {
      final controller = buildController(
        database,
        seed: startedCharacter(database).copyWith(dialogueFlags: [flag]),
      );
      addTearDown(controller.dispose);
      await pumpShell(tester, controller, size: const Size(400, 900));
      await tester.pump();
      expect(find.byKey(const Key('fennel-dialogue-panel')), findsOneWidget);
      expect(find.text(line), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('showing cooked potatoes with a dagger in the bag reaches DNODE-0031', (
    tester,
  ) async {
    final assigned = assignRace(
      database.launch,
      createNewSave(database.launch, testStartMs).copyWith(characterName: 'Tester'),
      'RACE-0005',
    );
    var save = assigned.save!.copyWith(hasSeenFennelIntro: true);
    save = save.copyWith(
      quests: [
        for (final quest in save.quests)
          if (quest.questId == tutorialQuestId)
            quest.copyWith(
              counters: const {'step:QSTP-0013': 1, 'step:QSTP-0014': 1, 'step:QSTP-0015': 1},
            )
          else
            quest,
      ],
    );
    save = applyQuestStepUnlocks(database.launch, save);
    save = addItemToInventory(save, 'ITEM-0058', 5);
    final controller = buildController(database, seed: save);
    addTearDown(controller.dispose);
    await pumpPanel(tester, NpcPanel(controller: controller, npc: fennel(), onClose: () {}));
    await tester.pump();

    expect(find.byKey(const Key('fennel-dialogue-panel')), findsOneWidget);
    expect(find.text('Is that baked potato I smell? Let me have a look.'), findsOneWidget);
    await tester.tap(find.text('Show 5 Baked potato'));
    await tester.pump();
    expect(
      find.text("That cow's been trouble all week. Grab your dagger before you go near her."),
      findsOneWidget,
    );
    expect(find.textContaining('sword and shield'), findsNothing);
  });

  testWidgets('a finished Getting Started character sees the open world', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0034'),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(400, 900));
    await tester.pump();

    expect(isTutorialLocked(controller.save), isFalse);
    expect(find.byType(TutorialHintBar), findsNothing);
    expect(find.byTooltip('Skills'), findsOneWidget);
    expect(find.byTooltip('Open menu'), findsOneWidget);
  });
}
