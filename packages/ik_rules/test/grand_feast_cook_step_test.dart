import 'dart:convert';

import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

/// The Grand Feast (QST-0001) on the launch content players load: briefing,
/// optional Cook step, hand-in at the King. Twin of
/// `src/game/quests/grandFeastCookStep.test.ts`.
const _throneRoom = 'LOC-0016';
const _feast = 'QST-0001';
const _briefing = 'QSTP-0001';
const _cook = 'QSTP-0036';
const _handIn = 'QSTP-0002';
const _bakedPotato = 'ITEM-0058';
const _cookedPerch = 'ITEM-0059';
const _goldenSpud = 'ITEM-0026';
const _cooking = 'SKL-0007';
const _bakePotato = 'RCP-0001';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = filterLaunchContent(assertGameDatabaseShape(asJsonMap(contentDatabaseJson())));
  });

  PlayerSave fresh() => createNewSave(db, 0).copyWith(currentLocationId: _throneRoom);

  PlayerSave withQuest(PlayerSave save, String status, Map<String, num> counters) => save.copyWith(
    quests: [
      ...save.quests.where((quest) => quest.questId != _feast),
      QuestProgress(questId: _feast, status: status, progress: 0, counters: counters),
    ],
  );

  PlayerSave setCount(PlayerSave save, String itemId, num quantity) {
    final cleared = save.copyWith(
      inventory: save.inventory.where((stack) => stack.itemId != itemId).toList(),
    );
    return quantity > 0 ? addItemToInventory(cleared, itemId, quantity) : cleared;
  }

  PlayerSave reload(PlayerSave save) => parseSave(jsonDecode(jsonEncode(save.toJson())), 0);

  DialogueResult picked(PlayerSave save, String dialogueId, String nodeId, String choiceId) {
    final result = chooseDialogue(db, save, dialogueId, nodeId, choiceId);
    expect(result.ok, isTrue, reason: '$choiceId: ${result.reason}');
    return result;
  }

  PlayerSave accept() => picked(fresh(), 'DLG-0011', 'DNODE-0018', 'DCH-0023').save;

  String? stepOf(PlayerSave save) => getCurrentStepId(db, save, getQuest(db, _feast)!);

  List<String> kingChoices(PlayerSave save) => [
    for (final choice
        in startDialogue(db, save, 'DLG-0012').view?.choices ?? const <DialogueChoiceView>[])
      choice.choiceId,
  ];

  /// Hands in everything the King still needs, then takes "The feast is ready."
  PlayerSave finishAtTheKing(PlayerSave save) {
    final handedIn = picked(save, 'DLG-0012', 'DNODE-0020', 'DCH-0026');
    expect(handedIn.questCompletions, isEmpty);
    final paid = picked(handedIn.save, 'DLG-0012', 'DNODE-0022', 'DCH-0031');
    expect([for (final completion in paid.questCompletions) completion.questId], [_feast]);
    return paid.save;
  }

  void expectPaid(PlayerSave save) {
    expect(getQuestProgress(save, _feast).status, 'completed');
    expect(getSkillProgress(save, _cooking).xp, 10000);
    expect(bagCount(save, _goldenSpud), 1);
    expect(courtyardBotanyUnlocked(save), isTrue);
  }

  List<Map<String, Object?>> deltas(DialogueResult result) => [
    for (final delta in result.itemDeltas) delta.toJson(),
  ];

  test('authors the Cook step as an optional Hold between the briefing and the hand-in', () {
    final steps = getQuestSteps(db, _feast);
    expect([for (final step in steps) step.stepId], [_briefing, _cook, _handIn]);
    expect([for (final step in steps) step.stepOrder], [1, 2, 3]);

    final cook = steps[1];
    expect(cook.journalLabel, 'Cook food for the feast');
    expect(cook.notes, 'Hold: ITEM-0058 x10, ITEM-0059 x10; Optional');
    // `Optional` is its own semicolon-separated field, which is what the engine parses.
    expect((cook.notes ?? '').split(';').map((field) => field.trim()), contains('Optional'));
    expect(dialogueStepType(cook), isNull);
    expect(cook.stepItems, 'ITEM-0058:10;ITEM-0059:10');
    expect(cook.stepNpc, isNull);
    expect(cook.status, 'Planned');
    expect(cook.releasePhase, 'Launch');
    expect(
      [for (final hold in parseNotesObjectives(cook.notes ?? '').holds) hold.toJson()],
      [
        {'targetId': _bakedPotato, 'quantity': 10},
        {'targetId': _cookedPerch, 'quantity': 10},
      ],
    );

    final handIn = steps[2];
    expect(handIn.journalLabel, 'Bring the food to the King');
    expect(handIn.stepType, 'HandIn');
    expect(handIn.stepItems, 'ITEM-0058:10;ITEM-0059:10');
    expect(handIn.stepNpc, 'NPC-0001');
  });

  test('keeps the rewards, the King dialogue and the quest lines as they were', () {
    final quest = getQuest(db, _feast)!;
    expect(quest['Reward XP Skill ID'], _cooking);
    expect(quest['Reward XP Amount'], 10000);
    expect(quest['Reward Item ID'], _goldenSpud);
    expect(quest['Reward Item Quantity'], 1);

    DialogueChoiceRow choice(String choiceId) =>
        db.dialogueChoices.firstWhere((row) => row.choiceId == choiceId);
    expect(
      db.dialogues.firstWhere((row) => row.dialogueId == 'DLG-0012').condition,
      'quest_active:QST-0001;!quest_step:QST-0001:QSTP-0001',
    );
    expect(choice('DCH-0026').condition, 'quest_step:QST-0001:QSTP-0002');
    expect(choice('DCH-0026').action, 'hand_in:QST-0001:QSTP-0002');
    expect(choice('DCH-0030').condition, 'quest_active:QST-0001;!quest_step:QST-0001:QSTP-0002');
    expect(choice('DCH-0031').condition, 'quest_active:QST-0001;!quest_step:QST-0001:QSTP-0002');
    expect(choice('DCH-0032').condition, 'quest_step:QST-0001:QSTP-0002');

    expect(
      [
        for (final row in db.questDialogue)
          if (row.questId == _feast) row.dialogueId,
      ],
      ['QDL-0007', 'QDL-0024'],
    );
  });

  test('finishes at the King after cooking the food', () {
    var save = accept();
    expect(stepOf(save), _handIn);
    expect(isStepLatched(save, _feast, _cook), isFalse);

    // Bake ten potatoes and ten perch; the cooking tick latches the finished step.
    save = setCount(setCount(save, _bakedPotato, 10), _cookedPerch, 10);
    save = applyQuestProcessProgress(db, save, _bakePotato);
    expect(isStepLatched(save, _feast, _cook), isTrue);
    expect(stepOf(save), _handIn);
    expect(
      [for (final step in questStepJournal(db, save, getQuest(db, _feast)!)) step.toJson()],
      [
        {'key': _briefing, 'label': 'Hear what the King needs', 'state': 'done'},
        {'key': _cook, 'label': 'Cook food for the feast', 'state': 'done'},
        {'key': _handIn, 'label': 'Bring the food to the King', 'state': 'current'},
      ],
    );

    expect(dialoguesForNpc(db, save, 'NPC-0001').first, 'DLG-0012');
    expect(kingChoices(save), contains('DCH-0026'));
    expect(kingChoices(save), isNot(contains('DCH-0030')));
    expect(completeQuest(db, save, _feast).ok, isFalse);

    save = finishAtTheKing(save);
    expect(bagCount(save, _bakedPotato), 0);
    expect(bagCount(save, _cookedPerch), 0);
    expectPaid(save);
  });

  test('opens the hand-in right away when the food is obtained another way', () {
    var save = accept();
    // Bought or gifted elsewhere: nothing was cooked, so no cooking tick ran.
    save = setCount(setCount(save, _bakedPotato, 10), _cookedPerch, 10);
    expect(isStepLatched(save, _feast, _cook), isFalse);
    expect(stepOf(save), _handIn);
    expect(dialoguesForNpc(db, save, 'NPC-0001').first, 'DLG-0012');
    expect(kingChoices(save), contains('DCH-0026'));
    expect(kingChoices(save), isNot(contains('DCH-0030')));

    // Walking into the throne room is the tick that latches the held food.
    save = applyQuestVisitProgress(db, save, _throneRoom);
    expect(stepOf(save), _handIn);
    expectPaid(finishAtTheKing(save));
  });

  test(
    'skips cooking and still completes at QSTP-0002 with 10,000 Cooking XP and the Golden Spud',
    () {
      var save = accept();
      // After the briefing the hand-in is already current; the Cook step is skipped.
      expect(stepOf(save), _handIn);
      expect(isStepLatched(save, _feast, _cook), isFalse);

      // Food obtained elsewhere — no cooking tick, no step:QSTP-0036 latch.
      save = setCount(setCount(save, _bakedPotato, 10), _cookedPerch, 10);
      expect(isStepLatched(save, _feast, _cook), isFalse);
      expect(stepOf(save), _handIn);
      expect(kingChoices(save), contains('DCH-0026'));

      save = finishAtTheKing(save);
      expect(isStepLatched(save, _feast, _cook), isFalse);
      expectPaid(save);
    },
  );

  test('hands the food in a few at a time without ever holding the full order', () {
    var save = accept();
    expect(stepOf(save), _handIn);
    expect(
      chooseDialogue(db, save, 'DLG-0012', 'DNODE-0020', 'DCH-0026').code,
      'nothing_to_hand_in',
    );

    final first = picked(setCount(save, _bakedPotato, 6), 'DLG-0012', 'DNODE-0020', 'DCH-0026');
    expect(deltas(first), [
      {'itemId': _bakedPotato, 'qty': -6},
    ]);
    save = reload(picked(first.save, 'DLG-0012', 'DNODE-0022', 'DCH-0032').save);
    expect(stepOf(save), _handIn);
    expect(isStepLatched(save, _feast, _cook), isFalse);

    save = setCount(setCount(save, _bakedPotato, 4), _cookedPerch, 10);
    save = finishAtTheKing(save);
    expect(isStepLatched(save, _feast, _cook), isFalse);
    expectPaid(save);
  });

  test('loads a save made before the Cook step at the hand-in with its counts kept', () {
    // Saved on the old two-step quest: briefed, six potatoes already with the
    // King, four more and the perch in the bag. The Cook step was never a step
    // for this player, so it has no latch and the bag is short of ten potatoes.
    final before = withQuest(fresh(), 'active', {
      'talk:NPC-0001': 1,
      'talk:NPC-0001:QSTP-0001': 1,
      'step:QSTP-0001': 1,
      handInCounterKey(_handIn, _bakedPotato): 6,
    });
    var save = reload(setCount(setCount(before, _bakedPotato, 4), _cookedPerch, 10));

    expect(stepOf(save), _handIn);
    expect(isStepLatched(save, _feast, _cook), isFalse);
    expect(getQuestProgress(save, _feast).counters?[handInCounterKey(_handIn, _bakedPotato)], 6);
    expect(kingChoices(save), contains('DCH-0026'));
    expect(kingChoices(save), isNot(contains('DCH-0030')));

    final handedIn = picked(save, 'DLG-0012', 'DNODE-0020', 'DCH-0026');
    expect(deltas(handedIn), [
      {'itemId': _bakedPotato, 'qty': -4},
      {'itemId': _cookedPerch, 'qty': -10},
    ]);
    save = picked(handedIn.save, 'DLG-0012', 'DNODE-0022', 'DCH-0031').save;
    expectPaid(save);
  });
}
