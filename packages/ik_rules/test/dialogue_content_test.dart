import 'dart:convert';

import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

/// Fennel (NPC-0014) and the King (NPC-0001) on the launch content players
/// load. Twin of `src/game/dialogue/content.test.ts`.
const _farm = 'LOC-0001';
const _throneRoom = 'LOC-0016';
const _citadelPlaza = 'LOC-0028';
const _potatoSeed = 'ITEM-0324';
const _carrotSeed = 'ITEM-0339';
const _compost = 'ITEM-0377';
const _bakedPotato = 'ITEM-0058';
const _cookedPerch = 'ITEM-0059';
const _goldenSpud = 'ITEM-0026';
const _cooking = 'SKL-0007';

void main() {
  late GameDatabase db;
  late Map<String, Object?> raw;

  setUpAll(() {
    raw = asJsonMap(contentDatabaseJson());
    db = filterLaunchContent(assertGameDatabaseShape(raw));
  });

  PlayerSave fresh(String locationId) =>
      createNewSave(db, 0).copyWith(currentLocationId: locationId);

  PlayerSave withQuest(
    PlayerSave save,
    String questId,
    String status, [
    Map<String, num>? counters,
  ]) => save.copyWith(
    quests: [
      ...save.quests.where((quest) => quest.questId != questId),
      QuestProgress(questId: questId, status: status, progress: 0, counters: counters),
    ],
  );

  PlayerSave setCount(PlayerSave save, String itemId, num quantity) {
    final cleared = save.copyWith(
      inventory: save.inventory.where((stack) => stack.itemId != itemId).toList(),
    );
    return quantity > 0 ? addItemToInventory(cleared, itemId, quantity) : cleared;
  }

  PlayerSave fillBag(PlayerSave save) {
    final inventory = [...save.inventory];
    for (var index = 0; inventory.length < inventorySlotLimit; index++) {
      inventory.add(InventoryStack(itemId: 'ITEM-FILL-$index', quantity: 1));
    }
    return save.copyWith(inventory: inventory);
  }

  PlayerSave reload(PlayerSave save) => parseSave(jsonDecode(jsonEncode(save.toJson())), 0);

  DialogueResult pick(PlayerSave save, String dialogueId, String nodeId, String choiceId) =>
      chooseDialogue(db, save, dialogueId, nodeId, choiceId);

  DialogueResult picked(PlayerSave save, String dialogueId, String nodeId, String choiceId) {
    final result = pick(save, dialogueId, nodeId, choiceId);
    expect(result.ok, isTrue, reason: '$choiceId: ${result.reason}');
    return result;
  }

  DialogueResult seedGift(PlayerSave save) => pick(save, 'DLG-0007', 'DNODE-0011', 'DCH-0014');
  DialogueResult guidePotato(PlayerSave save) => pick(save, 'DLG-0001', 'DNODE-0001', 'DCH-0001');

  PlayerSave greenThumbActive([String foundSeed = _potatoSeed]) {
    final save = applyQuestAutoStartOnSeed(
      db,
      setCount(withQuest(fresh(_farm), 'QST-0006', 'completed'), foundSeed, 1),
    );
    expect(getQuestProgress(save, 'QST-0011').status, 'active');
    return save;
  }

  String? stepOf(PlayerSave save, String questId) =>
      getCurrentStepId(db, save, getQuest(db, questId)!);

  List<String> choiceIds(DialogueView? view) => [
    for (final choice in view?.choices ?? const <DialogueChoiceView>[]) choice.choiceId,
  ];

  test('validates on the launch view with no errors and ships every Fennel and King dialogue', () {
    expect(validateDialogueContent(db).where((issue) => issue.isError), isEmpty);
    expect(
      [
        for (final row in db.dialogues)
          if (row.npcId == 'NPC-0014' || row.npcId == 'NPC-0001') row.dialogueId,
      ],
      [for (var id = 2; id <= 12; id++) 'DLG-${id.toString().padLeft(4, '0')}'],
    );
  });

  test('guards every dialogue grant with a gift flag, and quest gifts with !quest_done', () {
    final grants = [
      for (final row in raw['DialogueChoices']! as List<Object?>)
        if (row case final Map<String, Object?> choice)
          if (parseDialogueTokens(choice['Action'] as String?).any((t) => t.name == 'grant_item'))
            choice,
    ];
    expect([for (final row in grants) row['Choice ID']], ['DCH-0001', 'DCH-0014']);
    for (final row in grants) {
      final flag = parseDialogueTokens(row['Action'] as String?)
          .firstWhere((token) => token.name == 'set_flag')
          .args
          .first;
      expect(flag, matches(RegExp(r'^gift:(QST|DLG)-\d+:\w+$')));
      final conditions = [
        for (final token in parseDialogueTokens(row['Condition'] as String?)) token.raw,
      ];
      expect(conditions, contains('!flag:$flag'));
      final owner = flag.split(':')[1];
      if (owner.startsWith('QST-')) expect(conditions, contains('!quest_done:$owner'));
    }
  });

  test('keeps a Fennel planting reminder on QSTP-0034', () {
    final dialogue = db.dialogues.where((row) => row.dialogueId == 'DLG-0009').single;
    expect(dialogue.condition, 'quest_step:QST-0011:QSTP-0034');
    final node = db.dialogueNodes.where((row) => row.nodeId == 'DNODE-0015').single;
    expect(node.line, contains('patch'));
    expect(node.line, contains('compost'));
    expect(node.line.toLowerCase(), isNot(contains('bank')));
    expect(startDialogue(db, greenThumbActive(), 'DLG-0009').ok, isFalse);
    final planted = withQuest(greenThumbActive(), 'QST-0011', 'active', {
      'step:QSTP-0023': 1,
      'step:QSTP-0024': 1,
    });
    expect(stepOf(planted, 'QST-0011'), 'QSTP-0034');
    expect(dialoguesForNpc(db, planted, 'NPC-0014'), ['DLG-0009']);
    expect(startDialogue(db, planted, 'DLG-0009').view?.line, node.line);
    expect(choiceIds(startDialogue(db, planted, 'DLG-0009').view), ['DCH-0020']);
  });

  test('guides Visiting the Citadel on the Guide and Market Master without quest actions', () {
    expect(
      [
        for (final row in db.dialogues)
          if (row.dialogueId == 'DLG-0013' || row.dialogueId == 'DLG-0014')
            (row.dialogueId, row.npcId, row.condition, row.priority),
      ],
      [
        ('DLG-0013', 'NPC-0013', 'quest_active:QST-0004', 10),
        ('DLG-0014', 'NPC-0006', 'quest_active:QST-0004', 10),
      ],
    );
    final guideLine = db.dialogueNodes.where((row) => row.nodeId == 'DNODE-0023').single.line;
    final marketLine = db.dialogueNodes.where((row) => row.nodeId == 'DNODE-0024').single.line;
    expect(guideLine, contains('bazaar'));
    expect(guideLine, contains('training grounds'));
    expect(marketLine.toLowerCase(), contains('browse'));
    expect('$guideLine $marketLine'.toLowerCase(), isNot(contains('bank')));
    expect('$guideLine $marketLine'.toLowerCase(), isNot(contains('gold')));

    final idle = fresh(_citadelPlaza);
    expect(dialoguesForNpc(db, idle, 'NPC-0013'), ['DLG-0001']);
    expect(dialoguesForNpc(db, idle, 'NPC-0006'), isEmpty);

    final touring = withQuest(idle, 'QST-0004', 'active');
    expect(dialoguesForNpc(db, touring, 'NPC-0013').first, 'DLG-0013');
    expect(dialoguesForNpc(db, touring, 'NPC-0013'), contains('DLG-0001'));
    expect(dialoguesForNpc(db, touring, 'NPC-0006'), ['DLG-0014']);
    expect(startDialogue(db, touring, 'DLG-0013').view?.line, guideLine);
    expect(startDialogue(db, touring, 'DLG-0014').view?.line, marketLine);

    for (final choice in [
      ('DLG-0013', 'DNODE-0023', 'DCH-0033'),
      ('DLG-0014', 'DNODE-0024', 'DCH-0034'),
    ]) {
      final row = (raw['DialogueChoices']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .singleWhere((entry) => entry['Choice ID'] == choice.$3);
      expect(row['Action'], isNull);
      final after = picked(touring, choice.$1, choice.$2, choice.$3);
      expect(getQuestProgress(after.save, 'QST-0004').status, 'active');
      expect(after.itemDeltas, isEmpty);
    }

    final done = withQuest(idle, 'QST-0004', 'completed');
    expect(dialoguesForNpc(db, done, 'NPC-0013'), ['DLG-0001']);
    expect(dialoguesForNpc(db, done, 'NPC-0006'), isEmpty);
  });

  test('stores a numberless make-room line on every SYS-01 hand-out choice', () {
    final handOuts = [
      for (final row in raw['DialogueChoices']! as List<Object?>)
        if (row case final Map<String, Object?> choice)
          if (parseDialogueTokens(choice['Action'] as String?)
              .any((token) => token.name == 'grant_item' || token.name == 'complete_quest'))
            choice,
    ];
    expect(
      [for (final row in handOuts) row['Choice ID']],
      ['DCH-0001', 'DCH-0012', 'DCH-0014', 'DCH-0021', 'DCH-0030', 'DCH-0031'],
    );
    for (final row in handOuts) {
      final line = row['No Room Line'] as String;
      expect(line.length, greaterThan(10));
      expect(line, isNot(contains(RegExp(r'\d'))));
      expect(line.toLowerCase(), isNot(contains('bank')));
    }
  });

  test('gives each gift once, even after closing mid-conversation and reloading', () {
    var save = picked(fresh(_citadelPlaza), 'DLG-0001', 'DNODE-0001', 'DCH-0001').save;
    expect(bagCount(save, _bakedPotato), 1);
    save = reload(save);
    expect(startDialogue(db, save, 'DLG-0001').ok, isTrue);
    expect(guidePotato(save).code, 'not_available');

    final gift = seedGift(greenThumbActive());
    expect(gift.ok, isTrue, reason: gift.reason);
    final farm = reload(gift.save);
    expect(farm.dialogueFlags, contains('gift:QST-0011:seed'));
    expect(dialoguesForNpc(db, farm, 'NPC-0014'), isNot(contains('DLG-0007')));
    expect(seedGift(farm).ok, isFalse);
    expect(bagCount(farm, _potatoSeed), 2);
  });

  test('gives players who already finished either quest nothing new', () {
    var save = withQuest(withQuest(fresh(_farm), 'QST-0006', 'completed'), 'QST-0011', 'completed');
    save = applyQuestAutoStartOnSeed(db, setCount(save, _potatoSeed, 3));
    expect(dialoguesForNpc(db, save, 'NPC-0014'), isEmpty);
    expect(seedGift(save).ok, isFalse);
    expect(pick(save, 'DLG-0010', 'DNODE-0016', 'DCH-0021').ok, isFalse);

    var king = withQuest(fresh(_throneRoom), 'QST-0001', 'completed');
    king = setCount(setCount(king, _bakedPotato, 10), _cookedPerch, 10);
    expect(dialoguesForNpc(db, king, 'NPC-0001'), isEmpty);
    expect(pick(king, 'DLG-0012', 'DNODE-0020', 'DCH-0026').ok, isFalse);
    expect(pick(king, 'DLG-0012', 'DNODE-0020', 'DCH-0030').ok, isFalse);
    expect(pick(king, 'DLG-0012', 'DNODE-0022', 'DCH-0031').ok, isFalse);
    expect(bagCount(king, _goldenSpud), 0);
  });

  test('finishing Green Thumb gives exactly 4 Potato Seed, 3 Carrot Seed and the Guide, once', () {
    var save = greenThumbActive();
    final potatoBefore = bagCount(save, _potatoSeed);
    final carrotBefore = bagCount(save, _carrotSeed);
    final results = <DialogueResult>[];
    void take(String dialogueId, String nodeId, String choiceId) {
      final result = picked(save, dialogueId, nodeId, choiceId);
      results.add(result);
      save = result.save;
    }

    take('DLG-0007', 'DNODE-0011', 'DCH-0014');
    expect(stepOf(save, 'QST-0011'), 'QSTP-0024');
    expect(pick(save, 'DLG-0008', 'DNODE-0013', 'DCH-0017').reason, 'Needs Compost');
    save = applyQuestActionProgress(db, setCount(save, _compost, 1), 'ACN-0199');
    take('DLG-0008', 'DNODE-0013', 'DCH-0017');
    save = applyQuestPlantProgress(db, save, [_potatoSeed], usedCompost: true);
    expect(stepOf(save, 'QST-0011'), 'QSTP-0035');
    take('DLG-0010', 'DNODE-0016', 'DCH-0021');
    expect(getQuestProgress(save, 'QST-0011').status, 'completed');

    expect(seedGift(save).ok, isFalse);
    expect(pick(save, 'DLG-0010', 'DNODE-0016', 'DCH-0021').ok, isFalse);
    expect(dialoguesForNpc(db, save, 'NPC-0014'), isEmpty);

    num granted(String itemId) => results
        .expand((result) => result.itemDeltas)
        .where((delta) => delta.itemId == itemId)
        .fold<num>(0, (sum, delta) => sum + delta.qty);
    expect(granted(_potatoSeed), 4);
    expect(granted(_carrotSeed), 3);
    expect(results.expand((result) => result.bookDeltas).toList(), ['BOOK-0002']);
    expect(bagCount(save, _potatoSeed) - potatoBefore, 4);
    expect(bagCount(save, _carrotSeed) - carrotBefore, 3);
  });

  test('hands in the feast over several visits and pays the quest once', () {
    var save = fresh(_throneRoom);
    expect(dialoguesForNpc(db, save, 'NPC-0001').first, 'DLG-0011');
    save = picked(save, 'DLG-0011', 'DNODE-0018', 'DCH-0023').save;
    expect(stepOf(save, 'QST-0001'), 'QSTP-0002');
    expect(dialoguesForNpc(db, save, 'NPC-0001').first, 'DLG-0012');
    expect(pick(save, 'DLG-0012', 'DNODE-0020', 'DCH-0026').code, 'nothing_to_hand_in');
    expect(courtyardBotanyUnlocked(save), isFalse);

    final first = picked(setCount(save, _bakedPotato, 6), 'DLG-0012', 'DNODE-0020', 'DCH-0026');
    expect(choiceIds(first.view), ['DCH-0032']);
    save = reload(picked(first.save, 'DLG-0012', 'DNODE-0022', 'DCH-0032').save);
    expect(stepOf(save, 'QST-0001'), 'QSTP-0002');

    save = setCount(setCount(save, _bakedPotato, 9), _cookedPerch, 12);
    final second = picked(save, 'DLG-0012', 'DNODE-0020', 'DCH-0026');
    expect(bagCount(second.save, _bakedPotato), 5);
    expect(bagCount(second.save, _cookedPerch), 2);
    expect(choiceIds(second.view), ['DCH-0031']);
    expect(getSkillProgress(second.save, _cooking).xp, 0);

    save = reload(second.save);
    expect(choiceIds(startDialogue(db, save, 'DLG-0012').view), ['DCH-0030', 'DCH-0027']);
    final paid = picked(save, 'DLG-0012', 'DNODE-0020', 'DCH-0030');
    expect(
      [for (final delta in paid.itemDeltas) delta.toJson()],
      [
        {'itemId': _goldenSpud, 'qty': 1},
      ],
    );
    save = paid.save;
    expect(getQuestProgress(save, 'QST-0001').status, 'completed');
    expect(getSkillProgress(save, _cooking).xp, 10000);
    expect(bagCount(save, _goldenSpud), 1);
    expect(courtyardBotanyUnlocked(save), isTrue);

    expect(pick(save, 'DLG-0012', 'DNODE-0020', 'DCH-0030').ok, isFalse);
    expect(pick(save, 'DLG-0012', 'DNODE-0022', 'DCH-0031').ok, isFalse);
    expect(pick(save, 'DLG-0012', 'DNODE-0020', 'DCH-0026').ok, isFalse);
    expect(getSkillProgress(save, _cooking).xp, 10000);
    expect(bagCount(save, _goldenSpud), 1);
  });

  test('reports the quest a dialogue choice completed for the reward popup', () {
    var save = picked(fresh(_throneRoom), 'DLG-0011', 'DNODE-0018', 'DCH-0023').save;
    save = setCount(setCount(save, _bakedPotato, 10), _cookedPerch, 10);
    final handedIn = picked(save, 'DLG-0012', 'DNODE-0020', 'DCH-0026');
    expect(handedIn.questCompletions, isEmpty);

    final paid = picked(handedIn.save, 'DLG-0012', 'DNODE-0022', 'DCH-0031');
    expect(paid.questCompletions, hasLength(1));
    final completion = paid.questCompletions.single;
    final direct = completeQuest(db, handedIn.save, 'QST-0001');
    expect(completion.questId, 'QST-0001');
    expect(completion.questName, direct.questName);
    expect(completion.rewards, direct.rewards);
    expect(completion.rewards, isNotEmpty);
    expect(completion.pendingSkillXp, direct.pendingSkillXp);
    expect(completion.pendingSkillXp, 0);
    expect(paid.toJson()['questCompletions'], [completion.toJson()]);

    expect(pick(paid.save, 'DLG-0012', 'DNODE-0022', 'DCH-0031').questCompletions, isEmpty);
  });

  test('keeps gifts claimable while the bag is full', () {
    final full = fillBag(fresh(_citadelPlaza));
    expect(guidePotato(full).code, 'no_room');
    expect(guidePotato(full.copyWith(inventory: full.inventory.sublist(1))).ok, isTrue);

    final farm = fillBag(greenThumbActive(_carrotSeed));
    final noRoom = seedGift(farm);
    expect(noRoom.code, 'no_room');
    expect(noRoom.save.dialogueFlags, isNot(contains('gift:QST-0011:seed')));
    expect(stepOf(noRoom.save, 'QST-0011'), 'QSTP-0023');
    final freed = farm.copyWith(
      inventory: farm.inventory.where((stack) => !stack.itemId.startsWith('ITEM-FILL-')).toList(),
    );
    expect(seedGift(freed).ok, isTrue);
  });

  test('/abandonquest clears Green Thumb gift flags so the seed can be claimed again', () {
    final gift = seedGift(greenThumbActive());
    expect(gift.ok, isTrue);
    final save = gift.save.copyWith(
      dialogueFlags: [...gift.save.dialogueFlags, 'gift:DLG-0001:potato'],
    );
    final abandoned = cheatAbandonQuest(save, 'QST-0011');
    expect(abandoned.ok, isTrue);
    expect(abandoned.save!.dialogueFlags, ['gift:DLG-0001:potato']);
    final again = seedGift(applyQuestAutoStartOnSeed(db, abandoned.save!));
    expect(again.ok, isTrue, reason: again.reason);
    expect(seedGift(again.save).ok, isFalse);
  });

  test('keeps a Fennel step finished under the old flow done', () {
    final latched = withQuest(fresh(_farm), 'QST-0006', 'active', {
      'talk:NPC-0014': 1,
      'talk:NPC-0014:QSTP-0014': 1,
      'step:QSTP-0013': 1,
      'step:QSTP-0014': 1,
    });
    expect(stepOf(reload(latched), 'QST-0006'), 'QSTP-0015');
    expect(dialoguesForNpc(db, latched, 'NPC-0014'), ['DLG-0004']);

    final shown = withQuest(fresh(_farm), 'QST-0006', 'active', {
      'step:QSTP-0013': 1,
      'step:QSTP-0014': 1,
      'step:QSTP-0015': 1,
      'step:QSTP-0016': 1,
    });
    expect(stepOf(reload(shown), 'QST-0006'), 'QSTP-0022');
    final done = picked(shown, 'DLG-0006', 'DNODE-0009', 'DCH-0012');
    expect(done.bookDeltas, ['BOOK-0001']);
    expect(getQuestProgress(done.save, 'QST-0006').status, 'completed');

    final oldSeed = withQuest(
      withQuest(fresh(_farm), 'QST-0006', 'completed'),
      'QST-0011',
      'active',
      {'give:ITEM-0324': 1, 'talk:NPC-0014': 1, 'talk:NPC-0014:QSTP-0023': 1, 'step:QSTP-0023': 1},
    );
    expect(stepOf(oldSeed, 'QST-0011'), 'QSTP-0024');
    expect(dialoguesForNpc(db, oldSeed, 'NPC-0014'), ['DLG-0008']);
    expect(seedGift(setCount(oldSeed, _potatoSeed, 2)).ok, isFalse);
  });

  test('lets a player midway through the old feast finish with the new hand-in', () {
    var save = withQuest(fresh(_throneRoom), 'QST-0001', 'active', {
      'talk:NPC-0001': 1,
      'talk:NPC-0001:QSTP-0001': 1,
      'step:QSTP-0001': 1,
    });
    save = setCount(setCount(reload(save), _bakedPotato, 10), _cookedPerch, 10);
    expect(dialoguesForNpc(db, save, 'NPC-0001').first, 'DLG-0012');
    save = picked(save, 'DLG-0012', 'DNODE-0020', 'DCH-0026').save;
    save = picked(save, 'DLG-0012', 'DNODE-0022', 'DCH-0031').save;
    expect(getQuestProgress(save, 'QST-0001').status, 'completed');
    expect(bagCount(save, _goldenSpud), 1);
    expect(getSkillProgress(save, _cooking).xp, 10000);

    final accepted = withQuest(fresh(_throneRoom), 'QST-0001', 'active', {});
    expect(choiceIds(startDialogue(db, accepted, 'DLG-0011').view), ['DCH-0029', 'DCH-0024']);
    final briefed = picked(accepted, 'DLG-0011', 'DNODE-0018', 'DCH-0029');
    expect(stepOf(briefed.save, 'QST-0001'), 'QSTP-0002');
  });
}
