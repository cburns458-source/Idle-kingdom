import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/game_controller.dart';
import 'package:idle_kingdoms/src/ui/log_view.dart';
import 'package:idle_kingdoms/src/ui/npc_panel.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

const _farmerDescription = 'A farmer who lives at the farm.';
const _fennelId = 'NPC-0014';
const _greenThumb = 'QST-0011';
const _feast = 'QST-0001';
const _gettingStarted = 'QST-0006';
const _farm = 'LOC-0001';
const _potatoSeed = 'ITEM-0324';
const _compost = 'ITEM-0377';
const _compostAction = 'ACN-0199';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  GameDatabase db() => database.launch;

  NpcRow fennel() => db().npcs.singleWhere((row) => row.npcId == _fennelId);

  String? stepOf(PlayerSave save) => getCurrentStepId(db(), save, getQuest(db(), _greenThumb)!);

  PlayerSave startGreenThumb() {
    final save = applyQuestAutoStartOnSeed(
      db(),
      startedCharacter(database).copyWith(
        currentLocationId: _farm,
        inventory: const [InventoryStack(itemId: _potatoSeed, quantity: 1)],
        quests: const [QuestProgress(questId: _gettingStarted, status: 'completed', progress: 1)],
      ),
    );
    expect(getQuestProgress(save, _greenThumb).status, 'active');
    return save;
  }

  Future<GameController> openFennel(WidgetTester tester, PlayerSave seed, {Key? key}) async {
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);
    await pumpPanel(
      tester,
      NpcPanel(
        key: key ?? ValueKey(seed.hashCode),
        controller: controller,
        npc: fennel(),
        onClose: () {},
      ),
    );
    await tester.pump();
    return controller;
  }

  Future<void> reopenFennel(WidgetTester tester, GameController controller, Key key) {
    return pumpPanel(
      tester,
      NpcPanel(key: key, controller: controller, npc: fennel(), onClose: () {}),
    );
  }

  test('a miniquest lists and ticks its steps through the shared journal', () {
    var save = startGreenThumb();
    final quest = getQuest(db(), _greenThumb)!;
    expect(questLog(db(), save).any((row) => row.questId == _greenThumb), isFalse);

    var row = miniQuestJournal(db(), save, 0).singleWhere((entry) => entry.questId == _greenThumb);
    expect(
      [for (final step in row.steps) step.toJson()],
      [for (final step in questJournalSteps(db(), save, quest)) step.toJson()],
    );
    expect(stepOf(save), 'QSTP-0023');
    expect(row.steps.singleWhere((step) => step.key == 'QSTP-0023').state, 'current');

    save = chooseDialogue(db(), save, 'DLG-0007', 'DNODE-0011', 'DCH-0014').save;
    row = miniQuestJournal(db(), save, 0).singleWhere((entry) => entry.questId == _greenThumb);
    expect(
      [for (final step in row.steps) step.toJson()],
      [for (final step in questJournalSteps(db(), save, quest)) step.toJson()],
    );
    expect(row.steps.singleWhere((step) => step.key == 'QSTP-0023').state, 'done');
    expect(row.steps.singleWhere((step) => step.key == 'QSTP-0024').state, 'current');

    save = applyQuestActionProgress(db(), addItemToInventory(save, _compost, 1), _compostAction);
    save = chooseDialogue(db(), save, 'DLG-0008', 'DNODE-0013', 'DCH-0017').save;
    row = miniQuestJournal(db(), save, 0).singleWhere((entry) => entry.questId == _greenThumb);
    expect(stepOf(save), 'QSTP-0034');
    expect(row.steps.singleWhere((step) => step.key == 'QSTP-0024').state, 'done');
    expect(row.steps.singleWhere((step) => step.key == 'QSTP-0034').state, 'current');

    final planted = plantBotanySelection(
      db(),
      save,
      const [_potatoSeed],
      nowMs: 0,
      usedCompost: true,
    );
    expect(planted.ok, isTrue, reason: planted.reason);
    save = planted.save!;
    row = miniQuestJournal(db(), save, 0).singleWhere((entry) => entry.questId == _greenThumb);
    expect(stepOf(save), 'QSTP-0035');
    expect(row.steps.singleWhere((step) => step.key == 'QSTP-0034').state, 'done');
    expect(row.steps.singleWhere((step) => step.key == 'QSTP-0035').state, 'current');

    save = chooseDialogue(db(), save, 'DLG-0010', 'DNODE-0016', 'DCH-0021').save;
    row = miniQuestJournal(db(), save, 0).singleWhere((entry) => entry.questId == _greenThumb);
    expect(row.completed, isTrue);
    expect(
      row.steps.where((step) => step.key.startsWith('QSTP-')).every((step) => step.state == 'done'),
      isTrue,
    );
  });

  testWidgets('completing a miniquest leaves quest % still; a normal quest raises it', (
    tester,
  ) async {
    final active = startGreenThumb();
    final before = logCompletion(db(), active).section('quests')!;
    final miniDone = active.copyWith(
      quests: [
        for (final row in active.quests)
          if (row.questId == _greenThumb) row.copyWith(status: 'completed') else row,
      ],
    );
    expect(logCompletion(db(), miniDone).section('quests')!.label, before.label);

    final feastDone = miniDone.copyWith(
      quests: [
        ...miniDone.quests.where((row) => row.questId != _feast),
        const QuestProgress(questId: _feast, status: 'completed', progress: 10),
      ],
    );
    final afterFeast = logCompletion(db(), feastDone).section('quests')!;
    expect(afterFeast.done, before.done + 1);
    expect(afterFeast.label, isNot(before.label));

    Future<void> expectQuestLabel(PlayerSave seed, String label) async {
      final controller = buildController(database, seed: seed);
      addTearDown(controller.dispose);
      await pumpPanel(tester, LogView(controller: controller));
      await tester.tap(find.text('Quests'));
      await tester.pump();
      expect(find.text(label), findsOne);
    }

    await expectQuestLabel(active, before.label);
    await expectQuestLabel(miniDone, before.label);
    await expectQuestLabel(feastDone, afterFeast.label);
  });

  testWidgets('a full Green Thumb run never shows Fennel description', (tester) async {
    final controller = await openFennel(tester, startGreenThumb(), key: const ValueKey('talk'));
    expect(find.textContaining("Oh, you've found a seed!"), findsOne);
    expect(find.text(_farmerDescription), findsNothing);
    expect(questDialogueForNpc(db(), controller.save, _fennelId), 'DLG-0007');

    await tester.tap(find.text("I'd like that."));
    await tester.pump();
    expect(find.textContaining('every good harvest starts with compost'), findsOne);
    expect(find.text(_farmerDescription), findsNothing);

    await tester.tap(find.text("I'll find some compost."));
    await tester.pump();
    expect(find.text(_farmerDescription), findsNothing);
    expect(find.text('Done'), findsOne);

    controller.commit(
      applyQuestActionProgress(
        db(),
        addItemToInventory(controller.save, _compost, 1),
        _compostAction,
      ),
    );
    await reopenFennel(tester, controller, const ValueKey('compost'));
    await tester.pump();
    expect(find.text('Did you find the compost? Let me have a sniff.'), findsOne);
    expect(find.text(_farmerDescription), findsNothing);
    expect(questDialogueForNpc(db(), controller.save, _fennelId), 'DLG-0008');

    await tester.tap(find.text("Here's the compost."));
    await tester.pump();
    expect(find.textContaining('pick the potato seed'), findsOne);
    expect(find.text(_farmerDescription), findsNothing);

    await tester.tap(find.text('Into the ground it goes.'));
    await tester.pump();
    expect(find.text(_farmerDescription), findsNothing);
    expect(stepOf(controller.save), 'QSTP-0034');

    await reopenFennel(tester, controller, const ValueKey('plant'));
    await tester.pump();
    expect(find.textContaining('The patch is right there'), findsOne);
    expect(find.text(_farmerDescription), findsNothing);
    expect(questDialogueForNpc(db(), controller.save, _fennelId), 'DLG-0009');

    await tester.tap(find.text('Will do.'));
    await tester.pump();
    expect(find.text(_farmerDescription), findsNothing);

    final planted = plantBotanySelection(
      db(),
      controller.save,
      const [_potatoSeed],
      nowMs: 0,
      usedCompost: true,
    );
    expect(planted.ok, isTrue, reason: planted.reason);
    controller.commit(planted.save!);
    await reopenFennel(tester, controller, const ValueKey('return'));
    await tester.pump();
    expect(find.textContaining('Well done! Come back in a few hours'), findsOne);
    expect(find.text(_farmerDescription), findsNothing);
    expect(questDialogueForNpc(db(), controller.save, _fennelId), 'DLG-0010');

    await tester.tap(find.text('Thanks for the lesson, Fennel.'));
    await tester.pump();
    expect(find.textContaining("Botanist's Guide"), findsWidgets);
    expect(find.text(_farmerDescription), findsNothing);

    await tester.tap(find.text('I will.'));
    await tester.pump();
    expect(getQuestProgress(controller.save, _greenThumb).status, 'completed');
    expect(find.text(_farmerDescription), findsNothing);
  });

  testWidgets('Green Thumb lines follow talk, compost, plant reminder, then return and reward', (
    tester,
  ) async {
    var save = startGreenThumb();
    expect(questDialogueForNpc(db(), save, _fennelId), 'DLG-0007');
    await openFennel(tester, save, key: const ValueKey('order-talk'));
    expect(find.textContaining("Oh, you've found a seed!"), findsOne);

    save = chooseDialogue(db(), save, 'DLG-0007', 'DNODE-0011', 'DCH-0014').save;
    save = applyQuestActionProgress(db(), addItemToInventory(save, _compost, 1), _compostAction);
    expect(questDialogueForNpc(db(), save, _fennelId), 'DLG-0008');
    await openFennel(tester, save, key: const ValueKey('order-compost'));
    expect(find.text('Did you find the compost? Let me have a sniff.'), findsOne);

    save = chooseDialogue(db(), save, 'DLG-0008', 'DNODE-0013', 'DCH-0017').save;
    expect(questDialogueForNpc(db(), save, _fennelId), 'DLG-0009');
    await openFennel(tester, save, key: const ValueKey('order-plant'));
    expect(find.textContaining('The patch is right there'), findsOne);

    final planted = plantBotanySelection(
      db(),
      save,
      const [_potatoSeed],
      nowMs: 0,
      usedCompost: true,
    );
    expect(planted.ok, isTrue, reason: planted.reason);
    save = planted.save!;
    expect(questDialogueForNpc(db(), save, _fennelId), 'DLG-0010');
    await openFennel(tester, save, key: const ValueKey('order-return'));
    expect(find.textContaining('Well done! Come back in a few hours'), findsOne);
    await tester.tap(find.text('Thanks for the lesson, Fennel.'));
    await tester.pump();
    expect(find.textContaining("Botanist's Guide"), findsWidgets);
  });

  test('content data has Fennel description cleared', () {
    expect(fennel().raw['Description'], '');
    expect(fennel().raw['Description'], isNot(_farmerDescription));
    expect([
      for (final row in db().npcs)
        if (row.raw['Description'] == _farmerDescription) row.npcId,
    ], isEmpty);
  });
}
