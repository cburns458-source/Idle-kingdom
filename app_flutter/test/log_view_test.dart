import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/quest_log_sort_pref.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/log_view.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  const throneRoom = 'LOC-0016';
  const feastId = 'QST-0001';
  const cookStep = 'QSTP-0036';
  const bakedPotato = 'ITEM-0058';
  const cookedPerch = 'ITEM-0059';
  const bakePotato = 'RCP-0001';

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  Future<void> openLog(WidgetTester tester) async {
    await openChinScreen(tester, 'Log');
  }

  PlayerSave afterKingBriefing() {
    final save = startedCharacter(database).copyWith(currentLocationId: throneRoom);
    final accepted = chooseDialogue(database.launch, save, 'DLG-0011', 'DNODE-0018', 'DCH-0023');
    expect(accepted.ok, isTrue, reason: accepted.reason);
    return accepted.save;
  }

  Future<void> openFeastJournal(WidgetTester tester) async {
    await openLog(tester);
    await tester.tap(find.text('Quests'));
    await tester.pump();
    await tester.tap(find.text('The Grand Feast'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  String journalMark(WidgetTester tester, String label) {
    final row = find.ancestor(of: find.text(label), matching: find.byType(Row)).first;
    return tester.widget<Text>(find.descendant(of: row, matching: find.byType(Text)).first).data!;
  }

  testWidgets('log journal copy uses panel ink on wood and stone plates', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);
    await openLog(tester);

    void expectPackInk(UiChromePack pack) {
      final chrome = UiChrome.forPack(pack);
      final easy = tester.widget<Text>(find.text('Easy'));
      expect(easy.style?.color, chrome.panelInk);
      expect(easy.style?.color, isNot(Palette.parchmentText));
      expect(easy.style?.color, isNot(Palette.gold));

      final completion = logCompletion(database.launch, controller.save);
      final overall = tester.widget<Text>(find.text('${completion.overall.percent}% complete'));
      expect(overall.style?.color, Palette.heading);
      expect(overall.style?.color, isNot(Palette.progress));
      expect(overall.style?.color, isNot(Palette.borderSelected));

      final section = tester.widget<Text>(find.text(completion.section('achievements')!.label));
      expect(section.style?.color, Palette.gold);
      expect(section.style?.color, isNot(chrome.embossFace));

      final bandMuted = find
          .descendant(
            of: find.ancestor(of: find.text('Easy'), matching: find.byType(ExpansionTile)),
            matching: find.byType(MutedText),
          )
          .first;
      final band = tester.widget<Text>(find.descendant(of: bandMuted, matching: find.byType(Text)));
      expect(band.style?.color, chrome.panelMuted);
      expect(band.style?.color, isNot(Palette.muted));
      expect(band.style?.color, isNot(Palette.parchmentText));
    }

    expectPackInk(UiChromePack.wood);
    controller.setUiChromePack(UiChromePack.stone);
    await tester.pump();
    expectPackInk(UiChromePack.stone);
  });

  testWidgets('opens on the achievements a save has not reached', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await openLog(tester);

    expect(find.text('Deeds unlocked on this save.'), findsOne);
    expect(find.text('Easy'), findsOne);
    expect(find.textContaining('Craft any spell'), findsWidgets);
  });

  testWidgets('Acolyte and Theologian appear in the deeds list', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(420, 900));

    await openLog(tester);

    await tester.ensureVisible(find.text('Acolyte'));
    expect(find.text('Acolyte'), findsOne);

    await tester.tap(find.text('Hard'));
    await tester.pump();
    await tester.ensureVisible(find.text('Theologian'));
    expect(find.text('Theologian'), findsOne);
  });

  testWidgets('an achievement stays greyed out until it is earned', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await openLog(tester);

    final ironMan = tester.widget<Text>(find.text('Iron man'));
    expect(ironMan.style?.color?.a, closeTo(0.45, 0.01));
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

  testWidgets('Critter collector milestone unlocks with every critter, then locks again', (
    tester,
  ) async {
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
    await tester.tap(find.text('Milestones'));
    await tester.pump();
    await tester.dragUntilVisible(
      find.text('Critter collector'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pump();
    expect(find.text('Critter collector'), findsOne);
    final title = tester.widget<Text>(find.text('Critter collector'));
    expect(title.style?.color?.a, closeTo(1, 0.01));
    expect(find.text('Reached'), findsWidgets);

    final short = controller.save.copyWith(
      critterCollections: controller.save.critterCollections.sublist(1),
    );
    controller.commit(syncProgressionMeta(database.launch, short, testStartMs));
    await tester.pump();
    await tester.dragUntilVisible(
      find.textContaining('${critterDefs.length - 1} / ${critterDefs.length} critters'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pump();

    expect(
      find.textContaining('${critterDefs.length - 1} / ${critterDefs.length} critters'),
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

    expect(find.text('Quest log for this save.'), findsNothing);
    expect(find.textContaining('Miniquests'), findsOne);
    await tester.tap(find.textContaining('Miniquests'));
    await tester.pump();
    expect(find.text('No active miniquests.'), findsOne);

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

  testWidgets('a skipped optional quest step stays unticked while the quest is in progress', (
    tester,
  ) async {
    final save = afterKingBriefing();
    expect(isStepLatched(save, feastId, cookStep), isFalse);
    final controller = buildController(database, seed: save);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);
    await openFeastJournal(tester);

    expect(find.text('Cook food for the feast'), findsOne);
    expect(journalMark(tester, 'Cook food for the feast'), '•');
    expect(journalMark(tester, 'Hear what the King needs'), '✓');
    expect(journalMark(tester, 'Bring the food to the King'), '•');
  });

  testWidgets('a cooked optional quest step ticks immediately', (tester) async {
    var save = afterKingBriefing();
    save = addItemToInventory(addItemToInventory(save, bakedPotato, 10), cookedPerch, 10);
    save = applyQuestProcessProgress(database.launch, save, bakePotato);
    expect(isStepLatched(save, feastId, cookStep), isTrue);
    final controller = buildController(database, seed: save);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);
    await openFeastJournal(tester);

    expect(journalMark(tester, 'Cook food for the feast'), '✓');
    expect(journalMark(tester, 'Hear what the King needs'), '✓');
    expect(journalMark(tester, 'Bring the food to the King'), '•');
  });

  testWidgets('a skipped optional quest step ticks once the whole quest is completed', (
    tester,
  ) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(
        quests: const <QuestProgress>[
          QuestProgress(questId: feastId, status: 'completed', progress: 10),
        ],
      ),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);
    await openFeastJournal(tester);

    expect(isStepLatched(controller.save, feastId, cookStep), isFalse);
    expect(journalMark(tester, 'Cook food for the feast'), '✓');
    expect(journalMark(tester, 'Hear what the King needs'), '✓');
    expect(journalMark(tester, 'Bring the food to the King'), '✓');
  });

  testWidgets('completed quests list the turn-in rewards after the steps', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(
        quests: const <QuestProgress>[
          QuestProgress(questId: 'QST-0001', status: 'completed', progress: 10),
        ],
      ),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);
    await openLog(tester);

    await tester.tap(find.text('Quests'));
    await tester.pump();
    expect(find.text('Rewards'), findsNothing);
    expect(find.text('10,000 Cooking XP'), findsNothing);

    await tester.tap(find.text('The Grand Feast'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Hear what the King needs'), findsOne);
    expect(find.text('Rewards'), findsOne);
    expect(find.text('10,000 Cooking XP'), findsOne);
    expect(find.textContaining('Golden spud'), findsOne);
    expect(tester.widget<Text>(find.text('The Grand Feast')).style?.color, Palette.successInk);
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

    expect(find.text('Chick'), findsOne);
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

  testWidgets('a miniquest lists and ticks journal steps like a normal quest', (tester) async {
    final active = startedCharacter(database).copyWith(
      currentLocationId: 'LOC-0001',
      quests: const <QuestProgress>[
        QuestProgress(questId: 'QST-0006', status: 'completed', progress: 1),
        QuestProgress(
          questId: 'QST-0011',
          status: 'active',
          progress: 1,
          counters: <String, num>{'talk:NPC-0014:QSTP-0023': 1, 'step:QSTP-0023': 1},
        ),
      ],
    );
    final before = logCompletion(database.launch, active).section('quests')!;
    final finished = active.copyWith(
      quests: const <QuestProgress>[
        QuestProgress(questId: 'QST-0006', status: 'completed', progress: 1),
        QuestProgress(questId: 'QST-0011', status: 'completed', progress: 1),
      ],
    );
    expect(logCompletion(database.launch, finished).section('quests')!.label, before.label);

    final controller = buildController(database, seed: active);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);
    await openLog(tester);
    await tester.tap(find.text('Quests'));
    await tester.pump();

    expect(find.text('Green Thumb'), findsNothing);
    await tester.tap(find.textContaining('Miniquests'));
    await tester.pump();
    expect(find.text('Green Thumb'), findsOne);
    expect(find.text('Speak with Fennel at the farm'), findsNothing);

    await tester.tap(find.text('Green Thumb'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Speak with Fennel at the farm'), findsOne);
    expect(journalMark(tester, 'Speak with Fennel at the farm'), '✓');
    expect(find.text('Gather compost and speak with Fennel'), findsOne);
    expect(journalMark(tester, 'Gather compost and speak with Fennel'), '•');
  });

  testWidgets('miniquests list a weekly race change once total level is high enough', (
    tester,
  ) async {
    final base = startedCharacter(database);
    final bump = raceChangeTotalLevel - totalLevel(base);
    final first = base.skills.first;
    final seasoned = base.copyWith(
      skills: <SkillProgress>[
        first.copyWith(level: first.level + bump),
        ...base.skills.skip(1),
      ],
    );
    final controller = buildController(database, seed: seasoned);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);
    await openLog(tester);

    await tester.tap(find.text('Quests'));
    await tester.pump();
    await tester.tap(find.textContaining('Miniquests'));
    await tester.pump();

    expect(find.text('A Change of Skin'), findsOne);
    expect(find.textContaining('Every 7 days'), findsOne);
    expect(find.textContaining('Available now'), findsWidgets);
  });

  testWidgets('quest sort is a menu and persists the chosen order', (tester) async {
    final prefs = MemorySaveStorage();
    final first = buildController(
      database,
      seed: startedCharacter(database),
      questLogSort: QuestLogSortPref.load(prefs),
    );
    addTearDown(first.dispose);
    await pumpShell(tester, first);
    await openLog(tester);
    await tester.tap(find.text('Quests'));
    await tester.pump();

    expect(find.textContaining('Miniquests'), findsOne);
    expect(find.textContaining('Hide locked'), findsOne);
    expect(find.byTooltip('Sort'), findsOne);
    expect(_questSortChipBorder(tester), UiChrome.wood.embossFace);
    expect(_questSortChipGradient(tester), UiChrome.wood.secondaryFill);
    expect(find.text('Status'), findsNothing);
    expect(find.text('Release'), findsNothing);

    await tester.tap(find.byTooltip('Sort'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<QuestLogSort>, 'A–Z'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(prefs.getItem(QuestLogSortPref.storageKey), QuestLogSort.alphabetical.name);

    final again = buildController(
      database,
      seed: startedCharacter(database),
      questLogSort: QuestLogSortPref.load(prefs),
    );
    addTearDown(again.dispose);
    expect(again.questLogSort.sort, QuestLogSort.alphabetical);
    await pumpPanel(tester, LogView(controller: again));
    await tester.tap(find.text('Quests'));
    await tester.pump();
    expect(_questSortChipBorder(tester), UiChrome.wood.embossFace);
    expect(_questSortChipGradient(tester), UiChrome.wood.secondarySelected);
    await tester.tap(find.byTooltip('Sort'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester
          .widget<CheckedPopupMenuItem<QuestLogSort>>(
            find.widgetWithText(CheckedPopupMenuItem<QuestLogSort>, 'A–Z'),
          )
          .checked,
      isTrue,
    );
  });
}

BoxDecoration _questSortChipDecoration(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(of: find.byTooltip('Sort'), matching: find.byType(DecoratedBox)).first,
  );
  return box.decoration as BoxDecoration;
}

Color _questSortChipBorder(WidgetTester tester) =>
    _questSortChipDecoration(tester).border!.top.color;

Gradient? _questSortChipGradient(WidgetTester tester) => _questSortChipDecoration(tester).gradient;
