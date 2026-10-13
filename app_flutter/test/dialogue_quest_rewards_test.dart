import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/dialogue_window.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  /// At the King with the feast food handed in, one choice away from completion.
  PlayerSave feastReady() {
    final db = database.launch;
    var save = startedCharacter(database).copyWith(currentLocationId: 'LOC-0016');
    save = chooseDialogue(db, save, 'DLG-0011', 'DNODE-0018', 'DCH-0023').save;
    save = addItemToInventory(addItemToInventory(save, 'ITEM-0058', 10), 'ITEM-0059', 10);
    final handedIn = chooseDialogue(db, save, 'DLG-0012', 'DNODE-0020', 'DCH-0026');
    expect(handedIn.ok, isTrue, reason: handedIn.reason);
    return handedIn.save;
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
    expect(controller.takePendingDialogueQuestCompletions(), isEmpty);
  });

  testWidgets('the shell shows the dialogue reward popup without a legacy line', (tester) async {
    final controller = buildController(database, seed: feastReady());
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(420, 900));
    await tester.pump();

    final completed = chooseDialogue(
      database.launch,
      controller.save,
      'DLG-0012',
      'DNODE-0020',
      'DCH-0030',
    );
    expect(completed.ok, isTrue, reason: completed.reason);
    controller.noteDialogueQuestCompletions(completed.questCompletions);
    controller.commit(completed.save);
    final collect = find.text('Collect');
    await tester.pump();
    for (var i = 0; i < 20 && collect.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Level up'), findsNothing);
    expect(find.text('Thank you'), findsOne);
    expect(find.text('The Grand Feast'), findsOne);
    for (final reward in completed.questCompletions.single.rewards) {
      expect(find.text('· $reward'), findsOne);
    }
    final legacy = questTalkLine(database.launch, 'QST-0001', 'NPC-0001', controller.save);
    if (legacy != null) expect(find.text(legacy), findsNothing);

    await tester.tap(find.widgetWithText(GameButton, 'Collect'));
    for (var i = 0; i < 20 && collect.evaluate().isNotEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(collect, findsNothing);
    // The Cooking XP the feast paid levels the skill after the reward is collected.
    expect(find.text('Level up'), findsOne);
  });
}
