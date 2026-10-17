import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/game_controller.dart';
import 'package:idle_kingdoms/src/ui/npc_panel.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

/// Quest-gated dialogues (Priority >= 10 with a `quest_*` Condition) open
/// [NpcPanel] ahead of the old quest branches, and opening an NPC commits the
/// seed auto-start the conversation used to apply to a copy only.
const _kingId = 'NPC-0001';
const _fennelId = 'NPC-0014';
const _guideId = 'NPC-0013';
const _throneRoom = 'LOC-0016';
const _farm = 'LOC-0001';
const _citadelPlaza = 'LOC-0028';
const _bakedPotato = 'ITEM-0058';
const _cookedPerch = 'ITEM-0059';
const _goldenSpud = 'ITEM-0026';
const _potatoSeed = 'ITEM-0324';
const _cooking = 'SKL-0007';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  GameDatabase db() => database.launch;

  NpcRow npcOf(String npcId) => db().npcs.firstWhere((row) => row.raw['NPC ID'] == npcId);

  String? stepOf(PlayerSave save, String questId) =>
      getCurrentStepId(db(), save, getQuest(db(), questId)!);

  num bagQty(PlayerSave save, String itemId) => save.inventory
      .where((stack) => stack.itemId == itemId)
      .fold<num>(0, (sum, stack) => sum + stack.quantity);

  /// Logs every hosted command the panel would send; the save still applies locally.
  List<(String, Map<String, Object?>)> watchCommands(GameController controller) {
    final log = <(String, Map<String, Object?>)>[];
    controller.submitGameCommand = (command, [args = const <String, Object?>{}]) async {
      log.add((command, Map<String, Object?>.of(args)));
      return null;
    };
    return log;
  }

  Future<GameController> openPanel(WidgetTester tester, PlayerSave seed, String npcId) async {
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);
    await pumpPanel(
      tester,
      NpcPanel(key: ValueKey(npcId), controller: controller, npc: npcOf(npcId), onClose: () {}),
    );
    return controller;
  }

  Future<void> reopen(WidgetTester tester, GameController controller, String npcId, Key key) {
    return pumpPanel(
      tester,
      NpcPanel(key: key, controller: controller, npc: npcOf(npcId), onClose: () {}),
    );
  }

  PlayerSave withBag(PlayerSave save, String itemId, int quantity) {
    final cleared = save.copyWith(
      inventory: save.inventory.where((stack) => stack.itemId != itemId).toList(),
    );
    return quantity > 0 ? addItemToInventory(cleared, itemId, quantity) : cleared;
  }

  /// The King's quest at its hand-in step with [potatoes] and [perch] in the bag.
  PlayerSave feastCook({int potatoes = 10, int perch = 10}) {
    var save = startedCharacter(database).copyWith(currentLocationId: _throneRoom);
    final accepted = chooseDialogue(db(), save, 'DLG-0011', 'DNODE-0018', 'DCH-0023');
    expect(accepted.ok, isTrue, reason: accepted.reason);
    save = accepted.save;
    expect(stepOf(save, 'QST-0001'), 'QSTP-0002');
    // Cook the whole order (the cooking tick latches the optional Cook step,
    // QSTP-0036), then carry only [potatoes] and [perch] to the King.
    save = addItemToInventory(addItemToInventory(save, _bakedPotato, 10), _cookedPerch, 10);
    save = applyQuestProcessProgress(db(), save, 'RCP-0001');
    expect(stepOf(save, 'QST-0001'), 'QSTP-0002');
    return withBag(withBag(save, _bakedPotato, potatoes), _cookedPerch, perch);
  }

  /// Same as [feastCook], but the food arrived without a cooking tick — no
  /// `step:QSTP-0036` latch. The hand-in at QSTP-0002 is already current.
  PlayerSave feastSkipCook({int potatoes = 10, int perch = 10}) {
    var save = startedCharacter(database).copyWith(currentLocationId: _throneRoom);
    final accepted = chooseDialogue(db(), save, 'DLG-0011', 'DNODE-0018', 'DCH-0023');
    expect(accepted.ok, isTrue, reason: accepted.reason);
    save = accepted.save;
    expect(stepOf(save, 'QST-0001'), 'QSTP-0002');
    expect(isStepLatched(save, 'QST-0001', 'QSTP-0036'), isFalse);
    return withBag(withBag(save, _bakedPotato, potatoes), _cookedPerch, perch);
  }

  /// Getting Started done and a found seed in the bag; Green Thumb not started.
  PlayerSave seedFinder() {
    final save = startedCharacter(database).copyWith(
      currentLocationId: _farm,
      quests: const [QuestProgress(questId: 'QST-0006', status: 'completed', progress: 1)],
    );
    return addItemToInventory(save, _potatoSeed, 1);
  }

  group('Grand Feast hand-in', () {
    testWidgets('the King opens DLG-0012 and the feast completes through it', (tester) async {
      final controller = await openPanel(tester, feastCook(), _kingId);
      final commands = watchCommands(controller);
      final cookingBefore = getSkillProgress(controller.save, _cooking).xp;

      expect(find.text('Ah, my cook returns! Tell me the feast is ready.'), findsOne);
      expect(find.text('Hand in 10 Baked potato and 10 Perch fillet'), findsOne);
      expect(find.text('Done'), findsNothing);
      expect(find.text('Turn in'), findsNothing);

      await tester.tap(find.textContaining('Hand in '));
      await tester.pump();

      expect(bagQty(controller.save, _bakedPotato), 0);
      expect(bagQty(controller.save, _cookedPerch), 0);
      expect(getQuestProgress(controller.save, 'QST-0001').status, 'active');
      expect(stepOf(controller.save, 'QST-0001'), isNull);
      expect(find.text('Into the kitchens they go! Is that everything?'), findsOne);

      await tester.tap(find.text("That's everything. The feast is ready."));
      await tester.pump();

      expect(getQuestProgress(controller.save, 'QST-0001').status, 'completed');
      expect(getSkillProgress(controller.save, _cooking).xp - cookingBefore, 10000);
      expect(bagQty(controller.save, _goldenSpud), 1);
      expect(courtyardBotanyUnlocked(controller.save), isTrue);
      expect(find.textContaining('Take this Golden spud with my thanks'), findsOne);
      expect(
        [
          for (final completion in controller.takePendingDialogueQuestCompletions())
            completion.questId,
        ],
        ['QST-0001'],
      );
      expect([for (final entry in commands) entry.$1], ['dialogue_choose', 'dialogue_choose']);
      expect(commands.last.$2, {
        'dialogueId': 'DLG-0012',
        'nodeId': 'DNODE-0022',
        'choiceId': 'DCH-0031',
      });

      // The conversation ends back on the panel, not in a reopened dialogue.
      await tester.tap(find.text('Thank you, Your Majesty.'));
      await tester.pump();
      expect(find.text('Done'), findsOne);
      expect(find.text('Ah, my cook returns! Tell me the feast is ready.'), findsNothing);
    });

    testWidgets('skipping the kitchen still completes at the King with the same reward', (
      tester,
    ) async {
      final controller = await openPanel(tester, feastSkipCook(), _kingId);
      final cookingBefore = getSkillProgress(controller.save, _cooking).xp;

      expect(isStepLatched(controller.save, 'QST-0001', 'QSTP-0036'), isFalse);
      expect(stepOf(controller.save, 'QST-0001'), 'QSTP-0002');
      expect(find.text('Ah, my cook returns! Tell me the feast is ready.'), findsOne);
      expect(find.text('Hand in 10 Baked potato and 10 Perch fillet'), findsOne);

      await tester.tap(find.textContaining('Hand in '));
      await tester.pump();
      await tester.tap(find.text("That's everything. The feast is ready."));
      await tester.pump();

      expect(getQuestProgress(controller.save, 'QST-0001').status, 'completed');
      expect(getSkillProgress(controller.save, _cooking).xp - cookingBefore, 10000);
      expect(bagQty(controller.save, _goldenSpud), 1);
      expect(isStepLatched(controller.save, 'QST-0001', 'QSTP-0036'), isFalse);
    });

    testWidgets('a partial hand-in keeps its count across visits', (tester) async {
      final controller = await openPanel(tester, feastCook(potatoes: 6, perch: 0), _kingId);

      expect(find.text('Hand in 6 Baked potato'), findsOne);
      await tester.tap(find.text('Hand in 6 Baked potato'));
      await tester.pump();
      expect(bagQty(controller.save, _bakedPotato), 0);
      expect(stepOf(controller.save, 'QST-0001'), 'QSTP-0002');
      expect(find.text("I'll bring the rest soon."), findsOne);
      expect(find.text("That's everything. The feast is ready."), findsNothing);

      await tester.tap(find.text("I'll bring the rest soon."));
      await tester.pump();
      expect(find.text('Done'), findsOne);

      controller.commit(
        addItemToInventory(addItemToInventory(controller.save, _bakedPotato, 4), _cookedPerch, 10),
      );
      await reopen(tester, controller, _kingId, const ValueKey('king again'));
      expect(find.text('Ah, my cook returns! Tell me the feast is ready.'), findsOne);
      expect(find.text('Hand in 4 Baked potato and 10 Perch fillet'), findsOne);
      await tester.tap(find.text('Hand in 4 Baked potato and 10 Perch fillet'));
      await tester.pump();
      expect(find.text("That's everything. The feast is ready."), findsOne);
      await tester.tap(find.text("That's everything. The feast is ready."));
      await tester.pump();
      expect(getQuestProgress(controller.save, 'QST-0001').status, 'completed');
    });

    testWidgets('a cook with nothing to hand in still gets the dialogue, not a bare Done', (
      tester,
    ) async {
      await openPanel(tester, feastCook(potatoes: 0, perch: 0), _kingId);
      expect(find.text('Ah, my cook returns! Tell me the feast is ready.'), findsOne);
      expect(find.text('Not yet, Your Majesty.'), findsOne);
      expect(find.textContaining('Hand in '), findsNothing);
      expect(
        find.text('Bring Baked potato (0/10 handed in) and Perch fillet (0/10 handed in)'),
        findsOne,
      );
      expect(find.text('Done'), findsNothing);

      // Closing drops to the old panel, where Done still lives.
      await tester.tap(find.text('Not yet, Your Majesty.'));
      await tester.pump();
      expect(find.text('Done'), findsOne);
      expect(find.text('Something else…'), findsOne);
    });
  });

  group('Green Thumb seed', () {
    testWidgets('opening Fennel commits the auto-start and hands over the seed', (tester) async {
      final controller = buildController(database, seed: seedFinder());
      addTearDown(controller.dispose);
      final commands = watchCommands(controller);
      expect(getQuestProgress(controller.save, 'QST-0011').status, 'inactive');

      await pumpPanel(
        tester,
        NpcPanel(controller: controller, npc: npcOf(_fennelId), onClose: () {}),
      );
      // The start is committed after the first frame, then the dialogue opens.
      await tester.pump();

      expect(getQuestProgress(controller.save, 'QST-0011').status, 'active');
      expect(stepOf(controller.save, 'QST-0011'), 'QSTP-0023');
      expect([for (final entry in commands) entry.$1], ['quest_autostart_seed']);
      expect(commands.single.$2, isEmpty);
      expect(find.textContaining("Oh, you've found a seed!"), findsOne);
      expect(find.text('Done'), findsNothing);

      await tester.tap(find.text("I'd like that."));
      await tester.pump();

      expect(bagQty(controller.save, _potatoSeed), 2);
      expect(controller.save.dialogueFlags, contains('gift:QST-0011:seed'));
      expect(stepOf(controller.save, 'QST-0011'), 'QSTP-0024');
      expect(find.textContaining('Here, a potato seed.'), findsOne);
      expect(commands.last.$1, 'dialogue_choose');
      expect(commands.last.$2['choiceId'], 'DCH-0014');

      await tester.tap(find.text("I'll find some compost."));
      await tester.pump();
      expect(find.text('Done'), findsOne);
      expect(find.text('A farmer who lives at the farm.'), findsNothing);
    });

    testWidgets('the committed start is the one the server rules produce', (tester) async {
      final controller = buildController(database, seed: seedFinder());
      addTearDown(controller.dispose);
      final expected = applyQuestAutoStartOnSeed(db(), controller.save);

      await pumpPanel(
        tester,
        NpcPanel(controller: controller, npc: npcOf(_fennelId), onClose: () {}),
      );
      await tester.pump();

      expect(
        [for (final row in controller.save.quests) row.toJson()],
        [for (final row in expected.quests) row.toJson()],
      );
    });

    testWidgets('a seed without Getting Started starts nothing and sends nothing', (tester) async {
      final seed = startedCharacter(database)
          .copyWith(currentLocationId: _farm, quests: const <QuestProgress>[]);
      final controller = buildController(database, seed: addItemToInventory(seed, _potatoSeed, 1));
      addTearDown(controller.dispose);
      final commands = watchCommands(controller);

      await pumpPanel(
        tester,
        NpcPanel(controller: controller, npc: npcOf(_fennelId), onClose: () {}),
      );
      await tester.pump();

      expect(getQuestProgress(controller.save, 'QST-0011').status, 'inactive');
      expect(commands, isEmpty);
      expect(find.textContaining("Oh, you've found a seed!"), findsNothing);
      expect(find.text('Start quest: Getting Started'), findsOne);
    });

    testWidgets('the old Continue cannot skip the seed gift', (tester) async {
      final controller = await openPanel(tester, seedFinder(), _fennelId);
      await tester.pump();
      final commands = watchCommands(controller);
      expect(find.textContaining("Oh, you've found a seed!"), findsOne);

      await tester.tap(find.text('Maybe later.'));
      await tester.pump();
      expect(find.text('Continue'), findsOne);
      expect(find.text('Something else…'), findsOne);

      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(commands.map((entry) => entry.$1), contains('quest_talk'));
      expect(stepOf(controller.save, 'QST-0011'), 'QSTP-0023');
      expect(bagQty(controller.save, _potatoSeed), 1);
      expect(controller.save.dialogueFlags, isNot(contains('gift:QST-0011:seed')));
      expect(find.text('Done'), findsOne);

      await reopen(tester, controller, _fennelId, const ValueKey('fennel again'));
      expect(find.textContaining("Oh, you've found a seed!"), findsOne);
      await tester.tap(find.text("I'd like that."));
      await tester.pump();
      expect(bagQty(controller.save, _potatoSeed), 2);
      expect(stepOf(controller.save, 'QST-0011'), 'QSTP-0024');
    });
  });

  group('which dialogue opens first', () {
    test('only quest-gated rows at Priority 10 or above take the opening', () {
      final plaza = startedCharacter(database).copyWith(currentLocationId: _citadelPlaza);
      expect(dialoguesForNpc(db(), plaza, _guideId), ['DLG-0001']);
      expect(questDialogueForNpc(db(), plaza, _guideId), isNull);

      final touring = plaza.copyWith(
        quests: const [QuestProgress(questId: 'QST-0004', status: 'active', progress: 0)],
      );
      expect(questDialogueForNpc(db(), touring, _guideId), 'DLG-0013');

      expect(questDialogueForNpc(db(), feastCook(), _kingId), 'DLG-0012');
      expect(
        questDialogueForNpc(db(), applyQuestAutoStartOnSeed(db(), seedFinder()), _fennelId),
        'DLG-0007',
      );
      expect(questDialogueForNpc(db(), seedFinder(), _fennelId), isNull);
    });

    testWidgets('an ungated greeting stays behind Something else…', (tester) async {
      final toured = startedCharacter(database).copyWith(
        currentLocationId: _citadelPlaza,
        quests: const [QuestProgress(questId: 'QST-0004', status: 'completed', progress: 5)],
      );
      expect(dialoguesForNpc(db(), toured, _guideId), ['DLG-0001']);
      await openPanel(tester, toured, _guideId);

      expect(find.text('Done'), findsOne);
      expect(find.text('Something else…'), findsOne);
      expect(find.textContaining('potato'), findsNothing);
      await tester.tap(find.text('Something else…'));
      await tester.pump();
      expect(find.text('Done'), findsNothing);
      expect(find.text('Citadel Guide'), findsOne);
    });

    testWidgets('a quest reminder opens first and drops back to the panel when closed', (
      tester,
    ) async {
      final touring = startedCharacter(database).copyWith(
        currentLocationId: _citadelPlaza,
        quests: const [QuestProgress(questId: 'QST-0004', status: 'active', progress: 0)],
      );
      await openPanel(tester, touring, _guideId);

      expect(find.textContaining('training grounds'), findsOne);
      expect(find.text('Done'), findsNothing);
      await tester.tap(find.text("I'll have a look."));
      await tester.pump();
      expect(find.textContaining('training grounds'), findsNothing);
      expect(find.text('Done'), findsOne);
      expect(find.text('Something else…'), findsOne);
    });
  });
}
