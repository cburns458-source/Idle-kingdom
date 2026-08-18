import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  Future<void> openLog(WidgetTester tester) async {
    await openChinScreen(tester, 'Log');
  }

  testWidgets('opens on the achievements a save has not reached', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await openLog(tester);

    expect(find.text('Skill milestones unlocked on this save.'), findsOne);
    expect(find.textContaining('Reach '), findsWidgets);
  });

  testWidgets('an achievement stays greyed out until it is earned', (tester) async {
    final save = startedCharacter(database);
    final raised = raiseSkillToMinimumLevel(save, database.launch, 'SKL-0002', 50);
    final controller = buildController(database, seed: raised.save);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await openLog(tester);

    Finder rowFor(String title) => find.ancestor(
      of: find.text(title),
      matching: find.byType(Opacity),
    );

    expect(rowFor('Mining Level 50'), findsNothing);
    expect(tester.widget<Opacity>(rowFor('Combat Level 50').first).opacity, lessThan(1));
  });

  testWidgets('the Log reports how much of each page is done', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await openLog(tester);

    final completion = logCompletion(database.launch, controller.save);
    expect(find.text('${completion.overall.percent}% complete'), findsOne);
    expect(find.text(completion.section('achievements')!.label), findsOne);

    await tester.tap(find.text('Critters'));
    await tester.pump();
    expect(find.text(completion.section('critters')!.label), findsOne);
  });

  testWidgets('Critter Collector waits on the last critter, then is lost again', (tester) async {
    final every = startedCharacter(database).copyWith(
      critterCollections: <CritterCollectionEntry>[
        for (final critter in critterDefs) CritterCollectionEntry(critterId: critter.id, count: 1),
      ],
    );
    final controller = buildController(
      database,
      seed: syncProgressionMeta(database.launch, every, testStartMs),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await openLog(tester);
    expect(find.text('Critter Collector'), findsOne);
    expect(
      find.ancestor(of: find.text('Critter Collector'), matching: find.byType(Opacity)),
      findsNothing,
    );

    // A critter leaves the collection, the way a new one being added would look.
    final short = controller.save.copyWith(
      critterCollections: controller.save.critterCollections.sublist(1),
    );
    controller.commit(syncProgressionMeta(database.launch, short, testStartMs));
    await tester.pump();

    expect(
      find.textContaining('Collect one of every critter (${critterDefs.length - 1}/'),
      findsOne,
    );
  });

  testWidgets('shows an active quest with its objectives', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(
        inventory: const <InventoryStack>[InventoryStack(itemId: 'ITEM-0038', quantity: 3)],
        quests: const <QuestProgress>[
          QuestProgress(questId: 'QST-0002', status: 'active', progress: 0),
        ],
      ),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);
    await openLog(tester);

    await tester.tap(find.text('Quests'));
    await tester.pump();

    expect(find.text('Active'), findsOne);
    expect(find.text('Not started'), findsWidgets);
    expect(find.textContaining('Deliver '), findsWidgets);
  });

  testWidgets('withholds a recipe the player has not been taught', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);
    await openLog(tester);

    await tester.tap(find.text('Recipe Book'));
    await tester.pump();

    expect(find.text('Unknown recipe'), findsWidgets);
  });

  testWidgets('names a critter only once it has been caught', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(
        critterCollections: const <CritterCollectionEntry>[
          CritterCollectionEntry(critterId: 'CRT-0001', count: 4),
        ],
      ),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);
    await openLog(tester);

    await tester.tap(find.text('Critters'));
    await tester.pump();

    expect(find.text('Fly'), findsOne);
    expect(find.text('×4'), findsOne);
    expect(find.text('Unknown'), findsWidgets);
  });

  testWidgets('log tabs stay on screen while the list scrolls', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);
    await openLog(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();

    expect(find.text('Log'), findsOne);
    expect(find.text('Achievements'), findsOne);
    expect(find.text('Quests'), findsOne);
  });
}
