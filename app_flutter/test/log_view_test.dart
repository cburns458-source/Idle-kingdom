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

    expect(find.text('Deeds unlocked on this save.'), findsOne);
    expect(find.text('Easy'), findsOne);
    expect(find.textContaining('Craft any spell'), findsWidgets);
  });

  testWidgets('an achievement stays greyed out until it is earned', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await openLog(tester);

    Finder rowFor(String title) =>
        find.ancestor(of: find.text(title), matching: find.byType(Opacity));

    expect(rowFor('Every skill 50'), findsNothing);
    expect(tester.widget<Opacity>(rowFor('Iron man').first).opacity, lessThan(1));
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
    await pumpShell(tester, controller, size: const Size(420, 900));

    await openLog(tester);
    await tester.tap(find.text('Hard'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Critter collector'), findsOne);
    expect(
      find.ancestor(of: find.text('Critter collector'), matching: find.byType(Opacity)),
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

  testWidgets('hides quest steps until the journal is opened', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(
        quests: const <QuestProgress>[
          QuestProgress(questId: 'QST-0001', status: 'active', progress: 0),
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
    expect(find.text('Hear what the King needs'), findsNothing);

    await tester.tap(find.text('The Grand Feast'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Hear what the King needs'), findsOne);
    expect(find.text('Talk to King 0 / 1'), findsOne);
    expect(find.text('Prepare food for the feast'), findsNothing);
  });

  testWidgets('the Log no longer carries a recipe book page', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);
    await openLog(tester);

    expect(find.text('Recipe Book'), findsNothing);
    expect(logCompletion(database.launch, controller.save).section('recipes'), isNull);
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
    expect(find.text('Deeds'), findsOne);
    expect(find.text('Milestones'), findsOne);
    expect(find.text('Quests'), findsOne);
    expect(find.text('Recipe Book'), findsNothing);
  });
}
