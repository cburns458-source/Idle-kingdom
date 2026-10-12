import 'dart:convert';

import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

/// Mirrors `src/game/quests/fullBag.test.ts`.
const _npc = 'NPC-9101';
const _bakedPotato = 'ITEM-0058';
const _cookedPerch = 'ITEM-0059';
const _goldenSpud = 'ITEM-0026';
const _potato = 'ITEM-0025';
const _noRoom = 'No room in your bag. Free 1 slot and try again.';
const _favouritesPrompt = 'Some items are favourited. Do you still want to use them?';

Map<String, Object?> _launch(Map<String, Object?> row) => <String, Object?>{
  'Status': 'Confirmed',
  'Release Phase': 'Launch',
  'Notes': null,
  ...row,
};

Map<String, Object?> _quest(String id, String? notes, [Map<String, Object?> extra = const {}]) =>
    _launch(<String, Object?>{
      'Quest ID': id,
      'Internal Key': id.toLowerCase(),
      'Display Name': id,
      'NPC ID': _npc,
      'Summary': null,
      'Pitch': null,
      'Notes': notes,
      'Objective Type': null,
      'Objective Target ID': null,
      'Required Quantity': null,
      'Repeatable': null,
      'Reward XP Skill ID': null,
      'Reward XP Amount': null,
      'Reward Item ID': null,
      'Reward Item Quantity': null,
      'Possible Rewards': null,
      ...extra,
    });

Map<String, Object?> _step(String id, String questId, int order, String type, String? items) =>
    _launch(<String, Object?>{
      'Step ID': id,
      'Quest ID': questId,
      'Step Order': order,
      'Journal Label': id,
      'Step Type': type,
      'Step Items': items,
      'Step NPC': _npc,
    });

Map<String, Object?> _choice(String id, String? condition, String action) =>
    _launch(<String, Object?>{
      'Choice ID': id,
      'Node ID': 'DNODE-9101',
      'Label': id,
      'Next Node ID': null,
      'Condition': condition,
      'Action': action,
      'Sort Order': 1,
      'Repeatable': true,
    });

const _spud = <String, Object?>{'Reward Item ID': _goldenSpud, 'Reward Item Quantity': 1};

GameDatabase _patchedDatabase() {
  final base = asJsonMap(contentDatabaseJson());
  final patch = <String, List<Map<String, Object?>>>{
    'NPCs': [
      _launch(<String, Object?>{
        'NPC ID': _npc,
        'Internal Key': 'npc-9101',
        'Display Name': 'Test King',
        'Location ID': 'LOC-0002',
        'Role': null,
        'Description': null,
      }),
    ],
    'Quests': [
      _quest('QST-9101', 'Deliver: $_bakedPotato x5; RewardGold: 100', _spud),
      _quest('QST-9102', 'Deliver: $_bakedPotato x5; RewardItem: $_potato x3, $_cookedPerch x2'),
      _quest(
        'QST-9103',
        'Deliver: $_bakedPotato x5; RewardGold: 250; RewardXp: SKL-0001 100; RewardBook: BOOK-0001',
      ),
      _quest('QST-9104', 'AutoCompleteOnTalk', _spud),
      _quest('QST-9105', 'AutoCompleteOnVisit', _spud),
      _quest('QST-9106', 'Deliver: $_bakedPotato x5', {..._spud, 'Reward Mode': 'dialogue'}),
      _quest('QST-9107', null, {'Reward Mode': 'dialogue'}),
    ],
    'QuestSteps': [
      _step('QSTP-9104', 'QST-9104', 1, 'Talk', null),
      _step('QSTP-9105', 'QST-9105', 1, 'Talk', null),
      _step('QSTP-9171', 'QST-9107', 1, 'Talk', null),
      _step('QSTP-9172', 'QST-9107', 2, 'HandIn', '$_bakedPotato:10;$_cookedPerch:10'),
    ],
    'Dialogues': [
      _launch(<String, Object?>{
        'Dialogue ID': 'DLG-9101',
        'Internal Key': 'dlg-9101',
        'Display Name': 'DLG-9101',
        'NPC ID': _npc,
        'Start Node ID': 'DNODE-9101',
        'Repeatable': true,
      }),
    ],
    'DialogueNodes': [
      _launch(<String, Object?>{
        'Node ID': 'DNODE-9101',
        'Dialogue ID': 'DLG-9101',
        'Line': 'line',
      }),
    ],
    'DialogueChoices': [
      _choice(
        'DCH-9101',
        'quest_active:QST-9107;!flag:gift:QST-9107:thanks',
        'hand_in:QST-9107:QSTP-9172;grant_item:$_goldenSpud:1;set_flag:gift:QST-9107:thanks',
      ),
      _choice('DCH-9102', 'quest_active:QST-9101', 'complete_quest:QST-9101'),
    ],
  };
  final db = <String, Object?>{...base};
  for (final entry in patch.entries) {
    db[entry.key] = <Object?>[...(base[entry.key] as List<Object?>? ?? const []), ...entry.value];
  }
  return filterLaunchContent(assertGameDatabaseShape(db));
}

PlayerSave _withStacks(PlayerSave save, String itemId, List<(num, bool)> stacks) => save.copyWith(
  inventory: [
    ...save.inventory.where((stack) => stack.itemId != itemId),
    for (final (quantity, favorite) in stacks)
      InventoryStack(itemId: itemId, quantity: quantity, favorite: favorite ? true : null),
  ],
);

PlayerSave _fillBag(PlayerSave save, int free) {
  final inventory = save.inventory
      .where((stack) => !stack.itemId.startsWith('ITEM-FILL-'))
      .toList();
  for (var index = 0; inventory.length < inventorySlotLimit - free; index++) {
    inventory.add(InventoryStack(itemId: 'ITEM-FILL-$index', quantity: 1));
  }
  return save.copyWith(inventory: inventory);
}

String _snapshot(PlayerSave save) => jsonEncode(save.toJson());

const _noRoomJson = <String, Object?>{
  'ok': false,
  'reason': _noRoom,
  'code': 'no_room',
  'noRoom': {'slotsNeeded': 1, 'slotsFree': 0},
};

void main() {
  late GameDatabase db;
  late GameDatabase contentDb;

  setUpAll(() {
    db = _patchedDatabase();
    contentDb = filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));
  });

  PlayerSave fresh() => createNewSave(db, 0).copyWith(currentLocationId: 'LOC-0002');

  PlayerSave started(String questId, [PlayerSave? save]) {
    final accepted = acceptQuest(db, save ?? fresh(), questId);
    expect(accepted.ok, isTrue, reason: accepted.reason);
    return accepted.save!;
  }

  group('legacy quest rewards with a full bag', () {
    test('refuses the turn-in with no_room and leaves everything as it was', () {
      final save = _fillBag(_withStacks(started('QST-9101'), _bakedPotato, [(7, false)]), 0);
      final before = _snapshot(save);
      final result = completeQuest(db, save, 'QST-9101');
      expect(result.failureJson(), _noRoomJson);
      expect(result.save, isNull);
      expect(_snapshot(save), before);
      expect(getQuestProgress(save, 'QST-9101').status, 'active');
    });

    test('succeeds once a slot is free, granting the item once', () {
      final save = _fillBag(_withStacks(started('QST-9101'), _bakedPotato, [(7, false)]), 1);
      final result = completeQuest(db, save, 'QST-9101');
      expect(result.ok, isTrue, reason: result.reason);
      expect(bagCount(result.save!, _goldenSpud), 1);
      expect(bagCount(result.save!, _bakedPotato), 2);
      expect(result.save!.gold, save.gold + 100);
      expect(getQuestProgress(result.save!, 'QST-9101').status, 'completed');
      expect(completeQuest(db, result.save!, 'QST-9101').ok, isFalse);
    });

    test('counts the slot a delivery frees', () {
      final save = _fillBag(_withStacks(started('QST-9101'), _bakedPotato, [(5, false)]), 0);
      final result = completeQuest(db, save, 'QST-9101');
      expect(result.ok, isTrue, reason: result.reason);
      expect(bagCount(result.save!, _goldenSpud), 1);
      expect(bagCount(result.save!, _bakedPotato), 0);
    });

    test('merges into a stack already in a full bag', () {
      final save = _fillBag(
        _withStacks(_withStacks(started('QST-9101'), _bakedPotato, [(7, false)]), _goldenSpud, [
          (2, false),
        ]),
        0,
      );
      final result = completeQuest(db, save, 'QST-9101');
      expect(result.ok, isTrue, reason: result.reason);
      expect(bagCount(result.save!, _goldenSpud), 3);
    });

    test('grants none of a multi-item reward when only part fits', () {
      final save = _fillBag(_withStacks(started('QST-9102'), _bakedPotato, [(7, false)]), 1);
      final before = _snapshot(save);
      expect(completeQuest(db, save, 'QST-9102').failureJson(), <String, Object?>{
        'ok': false,
        'reason': _noRoom,
        'code': 'no_room',
        'noRoom': {'slotsNeeded': 2, 'slotsFree': 1},
      });
      expect(_snapshot(save), before);

      final roomy = completeQuest(db, _fillBag(save, 2), 'QST-9102');
      expect(roomy.ok, isTrue, reason: roomy.reason);
      expect(bagCount(roomy.save!, _potato), 3);
      expect(bagCount(roomy.save!, _cookedPerch), 2);
    });

    test('pays gold, XP and books into a full bag', () {
      final save = _fillBag(_withStacks(started('QST-9103'), _bakedPotato, [(7, false)]), 0);
      final result = completeQuest(db, save, 'QST-9103');
      expect(result.ok, isTrue, reason: result.reason);
      expect(result.save!.gold, save.gold + 250);
      expect(result.save!.unlockedBookIds, contains('BOOK-0001'));
    });

    test('leaves dialogue-mode quests alone: they pay nothing on completion', () {
      final save = _fillBag(_withStacks(started('QST-9106'), _bakedPotato, [(7, false)]), 0);
      final result = completeQuest(db, save, 'QST-9106');
      expect(result.ok, isTrue, reason: result.reason);
      expect(bagCount(result.save!, _goldenSpud), 0);
      expect(getQuestProgress(result.save!, 'QST-9106').status, 'completed');
    });

    test('keeps an auto-complete-on-talk quest active and finishes it on the next talk', () {
      final save = _fillBag(latchStep(started('QST-9104'), 'QST-9104', 'QSTP-9104'), 0);
      final blocked = talkWithQuestNpc(db, save, _npc);
      expect(blocked.ok, isTrue, reason: blocked.reason);
      expect(getQuestProgress(blocked.save!, 'QST-9104').status, 'active');
      expect(bagCount(blocked.save!, _goldenSpud), 0);

      final retried = talkWithQuestNpc(db, _fillBag(blocked.save!, 1), _npc);
      expect(retried.ok, isTrue, reason: retried.reason);
      expect(getQuestProgress(retried.save!, 'QST-9104').status, 'completed');
      expect(bagCount(retried.save!, _goldenSpud), 1);
    });

    test('keeps an auto-complete-on-visit quest active and finishes it on the next visit', () {
      final save = _fillBag(latchStep(started('QST-9105'), 'QST-9105', 'QSTP-9105'), 0);
      final blocked = applyQuestAutoCompleteOnVisit(db, save);
      expect(blocked.completions, isEmpty);
      expect(_snapshot(blocked.save), _snapshot(save));

      final retried = applyQuestAutoCompleteOnVisit(db, _fillBag(blocked.save, 1));
      expect([for (final line in retried.completions) line.questId], ['QST-9105']);
      expect(bagCount(retried.save, _goldenSpud), 1);
    });

    test('passes no_room through a dialogue complete_quest on a legacy quest', () {
      final save = _fillBag(_withStacks(started('QST-9101'), _bakedPotato, [(7, false)]), 0);
      final result = chooseDialogue(db, save, 'DLG-9101', 'DNODE-9101', 'DCH-9102');
      expect(result.ok, isFalse);
      expect(result.code, 'no_room');
      expect(result.reason, _noRoom);
      expect(result.noRoom?.toJson(), {'slotsNeeded': 1, 'slotsFree': 0});
      expect(identical(result.save, save), isTrue);
    });
  });

  group('legacy quest turn-ins share the hand-in item rules', () {
    test('takes bag stacks only; the bank never counts', () {
      final save = started('QST-9101')
          .copyWith(bank: const [InventoryStack(itemId: _bakedPotato, quantity: 50)]);
      expect(completeQuest(db, save, 'QST-9101').failureJson(), <String, Object?>{
        'ok': false,
        'reason': 'Need 5 Baked Potato.',
      });
    });

    test('asks before using favourited stacks, and takes unhearted ones first on a yes', () {
      final save = _withStacks(started('QST-9101'), _bakedPotato, [(3, true), (4, false)]);
      final before = _snapshot(save);
      expect(completeQuest(db, save, 'QST-9101').failureJson(), <String, Object?>{
        'ok': false,
        'reason': _favouritesPrompt,
        'code': 'confirm_favourites',
        'favourites': [
          {'itemId': _bakedPotato, 'qty': 1},
        ],
      });
      expect(_snapshot(save), before);

      final confirmed = completeQuest(db, save, 'QST-9101', useFavourites: true);
      expect(confirmed.ok, isTrue, reason: confirmed.reason);
      expect(
        [
          for (final stack in confirmed.save!.inventory)
            if (stack.itemId == _bakedPotato) stack.toJson(),
        ],
        [
          {'itemId': _bakedPotato, 'quantity': 2, 'favorite': true},
        ],
      );
    });

    test('does not ask when unhearted stacks cover the delivery', () {
      final save = _withStacks(started('QST-9101'), _bakedPotato, [(3, true), (5, false)]);
      final result = completeQuest(db, save, 'QST-9101');
      expect(result.ok, isTrue, reason: result.reason);
      expect(bagCount(result.save!, _bakedPotato), 3);
    });

    test('reports a full bag before the favourites prompt, with or without useFavourites', () {
      final save = _fillBag(_withStacks(started('QST-9101'), _bakedPotato, [(7, true)]), 0);
      final before = _snapshot(save);
      expect(completeQuest(db, save, 'QST-9101').failureJson(), _noRoomJson);
      expect(completeQuest(db, save, 'QST-9101', useFavourites: true).failureJson(), _noRoomJson);
      expect(_snapshot(save), before);
    });
  });

  group('dialogue hand-ins with a full bag (QA)', () {
    PlayerSave feastReady(int free) {
      final save = latchStep(started('QST-9107'), 'QST-9107', 'QSTP-9171');
      return _fillBag(
        _withStacks(_withStacks(save, _bakedPotato, [(12, true)]), _cookedPerch, [(12, true)]),
        free,
      );
    }

    test('returns no_room, not confirm_favourites, for a favourited hand-in with a full bag', () {
      final save = feastReady(0);
      for (final useFavourites in [false, true]) {
        final result = chooseDialogue(
          db,
          save,
          'DLG-9101',
          'DNODE-9101',
          'DCH-9101',
          useFavourites: useFavourites,
        );
        expect(result.ok, isFalse);
        expect(result.code, 'no_room');
        expect(result.reason, _noRoom);
        expect(result.noRoom?.toJson(), {'slotsNeeded': 1, 'slotsFree': 0});
        expect(result.favourites, isEmpty);
        expect(identical(result.save, save), isTrue);
      }
    });

    test('asks about favourites once the bag has room', () {
      final save = feastReady(1);
      expect(
        chooseDialogue(db, save, 'DLG-9101', 'DNODE-9101', 'DCH-9101').code,
        'confirm_favourites',
      );
      final confirmed = chooseDialogue(
        db,
        save,
        'DLG-9101',
        'DNODE-9101',
        'DCH-9101',
        useFavourites: true,
      );
      expect(confirmed.ok, isTrue, reason: confirmed.reason);
    });
  });

  group('bribe coin purse with a full bag', () {
    PlayerSave bribeReady(int free) {
      final base = createNewSave(contentDb, 0);
      return _fillBag(
        base.copyWith(
          gold: 300,
          currentLocationId: 'LOC-0017',
          quests: [
            ...base.quests,
            const QuestProgress(questId: 'QST-0003', status: 'active', progress: 0),
          ],
        ),
        free,
      );
    }

    test('refuses with no_room and takes no gold and sets no flag', () {
      final save = bribeReady(0);
      final before = _snapshot(save);
      final result = bribeQuestNpc(contentDb, save, 'QST-0003');
      expect(result.ok, isFalse);
      expect(result.reason, _noRoom);
      expect(result.code, 'no_room');
      expect(result.noRoom?.toJson(), {'slotsNeeded': 1, 'slotsFree': 0});
      expect(_snapshot(save), before);
      expect(bribeForQuest(contentDb, save, 'QST-0003').toJson(), _noRoomJson);
    });

    test('hands over the purse once there is room', () {
      final result = bribeQuestNpc(contentDb, bribeReady(1), 'QST-0003');
      expect(result.ok, isTrue, reason: result.reason);
      expect(result.save!.gold, 100);
      expect(bagCount(result.save!, 'ITEM-0299'), 1);
    });
  });
}
