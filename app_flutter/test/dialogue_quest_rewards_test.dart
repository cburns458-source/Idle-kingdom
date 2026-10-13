import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/app_shell.dart';
import 'package:idle_kingdoms/src/ui/dialogue_text.dart';
import 'package:idle_kingdoms/src/ui/dialogue_window.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  GameDatabase db() => database.launch;

  /// At the King with the feast food handed in, one choice away from completion.
  PlayerSave feastReady() {
    var save = startedCharacter(database).copyWith(currentLocationId: 'LOC-0016');
    save = chooseDialogue(db(), save, 'DLG-0011', 'DNODE-0018', 'DCH-0023').save;
    save = addItemToInventory(addItemToInventory(save, 'ITEM-0058', 10), 'ITEM-0059', 10);
    final handedIn = chooseDialogue(db(), save, 'DLG-0012', 'DNODE-0020', 'DCH-0026');
    expect(handedIn.ok, isTrue, reason: handedIn.reason);
    return handedIn.save;
  }

  Future<void> waitFor(Finder finder, WidgetTester tester) async {
    for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('a dialogue choice that completes a quest queues its reward popup', (tester) async {
    final controller = buildController(database, seed: feastReady());
    addTearDown(controller.dispose);

    await pumpPanel(
      tester,
      StandaloneDialogueHost(controller: controller, dialogueId: 'DLG-0012', onClose: () {}),
    );
    expect(controller.takePendingDialogueQuestCompletions(), isEmpty);

    await tester.tap(find.text('The feast is ready.'));
    await tester.pump();

    expect(getQuestProgress(controller.save, 'QST-0001').status, 'completed');
    final pending = controller.takePendingDialogueQuestCompletions();
    expect([for (final completion in pending) completion.questId], ['QST-0001']);
    expect(pending.single.questName, 'The Grand Feast');
    expect(pending.single.rewards, isNotEmpty);
    expect(pending.single.pendingSkillXp, 0);
    expect(controller.takePendingDialogueQuestCompletions(), isEmpty);
    for (final reward in pending.single.rewards) {
      expect(controller.message, contains(reward));
    }
  });

  testWidgets('the toast lists the same rewards the popup will show', (tester) async {
    final controller = buildController(database, seed: feastReady());
    addTearDown(controller.dispose);
    final before = controller.save;
    final completed = chooseDialogue(db(), before, 'DLG-0012', 'DNODE-0020', 'DCH-0030');
    expect(completed.ok, isTrue, reason: completed.reason);
    expect(completed.questCompletions, isNotEmpty);

    final notice = DialogueText(db()).notice(before, completed);
    expect(notice, isNotNull);
    for (final reward in completed.questCompletions.single.rewards) {
      expect(notice, contains(reward));
    }
  });

  testWidgets('the shell shows the dialogue reward popup without a legacy line', (tester) async {
    final controller = buildController(database, seed: feastReady());
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(420, 900));
    await tester.pump();

    final completed = chooseDialogue(db(), controller.save, 'DLG-0012', 'DNODE-0020', 'DCH-0030');
    expect(completed.ok, isTrue, reason: completed.reason);
    expect(completed.questCompletions.single.pendingSkillXp, 0);
    final notice = DialogueText(db()).notice(controller.save, completed);
    controller.noteDialogueQuestCompletions(completed.questCompletions);
    controller.commit(completed.save);
    if (notice != null) controller.announce(notice);
    final collect = find.text('Collect');
    await tester.pump();
    await waitFor(collect, tester);

    expect(find.text('Level up'), findsNothing);
    expect(find.text('Choose a skill'), findsNothing);
    expect(find.text('Thank you'), findsOne);
    expect(find.text('The Grand Feast'), findsOne);
    for (final reward in completed.questCompletions.single.rewards) {
      expect(find.text('· $reward'), findsOne);
      expect(controller.message, contains(reward));
    }
    final legacy = questTalkLine(db(), 'QST-0001', 'NPC-0001', controller.save);
    if (legacy != null) expect(find.text(legacy), findsNothing);
    expect(getSkillProgress(controller.save, 'SKL-0007').xp, 10000);

    await tester.tap(find.widgetWithText(GameButton, 'Collect'));
    for (var i = 0; i < 20 && collect.evaluate().isNotEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(collect, findsNothing);
    expect(find.text('Choose a skill'), findsNothing);
    expect(getSkillProgress(controller.save, 'SKL-0007').xp, 10000);
    // The Cooking XP the feast paid levels the skill after the reward is collected.
    expect(find.text('Level up'), findsOne);
  });

  testWidgets('the book unlock waits until Collect and the picker stays closed', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(420, 900));
    await tester.pump();

    controller.noteDialogueQuestCompletions([
      QuestArrivalCompletion(
        questId: 'QST-0006',
        questName: 'Getting Started',
        rewards: const ["Newcomer's Guide"],
        pendingSkillXp: 0,
        message: 'Thank you.',
        booksGranted: const [QuestBookGrant(bookId: 'BOOK-0001', isFirstEver: true)],
      ),
    ]);
    controller.commit(controller.save);
    final collect = find.text('Collect');
    await tester.pump();
    await waitFor(collect, tester);

    expect(find.text('Thank you'), findsOne);
    expect(find.text('Getting Started'), findsOne);
    expect(find.text('You found a book!'), findsNothing);
    expect(find.text('Choose a skill'), findsNothing);

    await tester.tap(find.widgetWithText(GameButton, 'Collect'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Collect'), findsNothing);
    expect(find.text('You found a book!'), findsOne);
    expect(find.text('Choose a skill'), findsNothing);
  });

  testWidgets('the XP picker opens only for pickable XP and adds only that amount', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(420, 900));
    await tester.pump();
    expect(getSkillProgress(controller.save, 'SKL-0007').xp, 0);

    controller.noteDialogueQuestCompletions([
      QuestArrivalCompletion(
        questId: 'QST-0003',
        questName: 'A pickable reward',
        rewards: const ['Choose 250 XP in a non-combat skill'],
        pendingSkillXp: 250,
        message: 'Thank you.',
      ),
    ]);
    controller.commit(controller.save);
    final collect = find.text('Collect');
    await tester.pump();
    await waitFor(collect, tester);

    expect(find.text('Thank you'), findsOne);
    expect(find.text('Choose a skill'), findsNothing);
    expect(getSkillProgress(controller.save, 'SKL-0007').xp, 0);

    await tester.tap(find.widgetWithText(GameButton, 'Collect'));
    await tester.pump();
    await waitFor(find.text('Choose a skill'), tester);

    expect(find.text('Choose a skill'), findsOne);
    expect(find.text('250 XP'), findsOne);
    expect(getSkillProgress(controller.save, 'SKL-0007').xp, 0);

    await tester.tap(find.widgetWithText(GameButton, 'Cooking'));
    await tester.pump();
    expect(find.text('Choose a skill'), findsNothing);
    expect(getSkillProgress(controller.save, 'SKL-0007').xp, 250);
  });

  testWidgets('a dialogue choice that unlocks a cosmetic shows the notice', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0016'),
    );
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(420, 900));
    await tester.pump();
    expect(isCosmeticUnlocked(controller.save, 'COS-0002'), isFalse);
    expect(find.text('You found a Cosmetic!'), findsNothing);

    final nav = tester.element(find.byType(AppShell));
    unawaited(
      showDialog<void>(
        context: nav,
        builder: (context) => Dialog(
          child: StandaloneDialogueHost(
            controller: controller,
            dialogueId: 'DLG-0011',
            onClose: () => Navigator.of(context).pop(),
            request: (view, choiceId, {required useFavourites}) async {
              final granted = grantCosmetic(controller.save, 'COS-0002');
              expect(granted.granted, isTrue);
              return DialogueResult(
                ok: true,
                reason: '',
                save: granted.save,
                view: view,
                completed: false,
                message: null,
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Not today, Your Majesty.'));
    await tester.pump();

    expect(find.text('You found a Cosmetic!'), findsOne);
    expect(find.text('New Cosmetic'), findsOne);
  });
}
