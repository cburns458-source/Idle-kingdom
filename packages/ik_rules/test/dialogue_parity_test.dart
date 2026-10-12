import 'dart:convert';

import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// Replays `src/parity/scenarios/dialogue.ts`: the content database with the
/// fixture's synthetic patch appended, then the same script of operations.
GameDatabase _patchedDatabase(ParityFixture fixture) {
  final base = asJsonMap(contentDatabaseJson());
  final db = <String, Object?>{...base};
  final patch = fixture.inputField<Map<String, Object?>>('patch');
  for (final entry in patch.entries) {
    db[entry.key] = <Object?>[
      ...(base[entry.key] as List<Object?>? ?? const []),
      ...entry.value! as List<Object?>,
    ];
  }
  return assertGameDatabaseShape(db);
}

PlayerSave _setItemCount(PlayerSave save, String itemId, num quantity) {
  final cleared = save.copyWith(
    inventory: save.inventory.where((stack) => stack.itemId != itemId).toList(),
  );
  return quantity > 0 ? addItemToInventory(cleared, itemId, quantity) : cleared;
}

PlayerSave _fillBag(PlayerSave save, int free) {
  final inventory = [...save.inventory];
  for (var index = 0; inventory.length < inventorySlotLimit - free; index++) {
    inventory.add(InventoryStack(itemId: 'ITEM-FILL-$index', quantity: 1));
  }
  return save.copyWith(inventory: inventory);
}

Map<String, Object?> _digest(PlayerSave save) {
  final quests = [...save.quests]..sort((a, b) => a.questId.compareTo(b.questId));
  return <String, Object?>{
    'gold': save.gold,
    'inventory': [for (final stack in save.inventory) stack.toJson()],
    'quests': [for (final row in quests) row.toJson()],
    'dialogueFlags': save.dialogueFlags,
    'unlockedBookIds': save.unlockedBookIds,
    'completedDialogueIds': save.completedDialogueIds,
  };
}

Map<String, Object?> _resultSummary(PlayerSave before, DialogueResult result) {
  final json = result.toJson();
  return <String, Object?>{
    'ok': result.ok,
    'code': result.code,
    'reason': result.reason,
    'message': result.message,
    'completed': result.completed,
    'view': json['view'],
    'itemDeltas': json['itemDeltas'],
    'bookDeltas': result.bookDeltas,
    'stepProgress': json['stepProgress'],
    'noRoom': json['noRoom'],
    'missing': json['missing'],
    'unchanged': canonicalJson(before.toJson()) == canonicalJson(result.save.toJson()),
  };
}

Map<String, Object?> _runScript(GameDatabase db, PlayerSave initial, List<Object?> ops, num nowMs) {
  var save = initial;
  final steps = <Object?>[];
  for (final raw in ops) {
    final op = raw! as Map<String, Object?>;
    String str(String key) => op[key]! as String;
    Object? out;
    switch (op['op']) {
      case 'npc':
        out = dialoguesForNpc(db, save, str('npcId'));
      case 'start':
        out = _resultSummary(save, startDialogue(db, save, str('dialogueId')));
      case 'view':
        out = viewDialogueNode(db, save, str('dialogueId'), str('nodeId'))?.toJson();
      case 'choose':
        final result = chooseDialogue(db, save, str('dialogueId'), str('nodeId'), str('choiceId'));
        out = _resultSummary(save, result);
        if (result.ok) save = result.save;
      case 'setItem':
        save = _setItemCount(save, str('itemId'), op['quantity']! as num);
      case 'fillBag':
        save = _fillBag(save, (op['free']! as num).toInt());
      case 'clearFillers':
        save = save.copyWith(
          inventory: save.inventory
              .where((stack) => !stack.itemId.startsWith('ITEM-FILL-'))
              .toList(),
        );
      case 'progress':
        out = [
          for (final line in stepProgressView(db, save, str('questId'), str('stepId')))
            line.toJson(),
        ];
      case 'conditions':
        out = [
          for (final token in op['tokens']! as List<Object?>)
            () {
              final check = checkDialogueCondition(
                db,
                save,
                parseDialogueTokens(token! as String).first,
              );
              return <String, Object?>{
                'token': token,
                'holds': check.holds,
                'reason': check.reason,
              };
            }(),
        ];
      case 'cheatAbandon':
        final result = cheatAbandonQuest(save, str('questId'));
        out = result.ok
            ? <String, Object?>{
                'ok': true,
                'deletedHandIns': [for (final line in result.deletedHandIns) line.toJson()],
              }
            : <String, Object?>{'ok': false, 'reason': result.reason};
        if (result.ok) save = result.save!;
      case 'completeQuest':
        final result = completeQuest(db, save, str('questId'));
        out = result.ok
            ? <String, Object?>{'ok': true, 'rewards': result.rewards}
            : <String, Object?>{'ok': false, 'reason': result.reason};
        if (result.ok) save = result.save!;
      case 'reload':
        save = parseSave(jsonDecode(jsonEncode(save.toJson())), nowMs);
      default:
        throw StateError('Unknown dialogue script op: ${op['op']}');
    }
    steps.add(<String, Object?>{'op': op['op'], 'out': out, 'state': _digest(save)});
  }
  return <String, Object?>{'steps': steps, 'save': save.toJson()};
}

void main() {
  group('dialogue engine parity (SYS-01)', () {
    for (final fixture in loadParityFixtures('dialogue/engine')) {
      test(fixture.name, () {
        final output = _runScript(
          _patchedDatabase(fixture),
          saveOf(fixture),
          fixture.inputField<List<Object?>>('ops'),
          fixture.inputField<num>('nowMs'),
        );
        expect(checkParity(fixture, output), isNull);
      });
    }
  });

  group('dialogue save migration parity (v61 -> v62)', () {
    for (final fixture in loadParityFixtures('dialogue/migration')) {
      test(fixture.name, () {
        final nowMs = fixture.inputField<num>('nowMs');
        final migrated = migrateSaveJson(
          asJsonMap(fixture.inputField<Map<String, Object?>>('legacy')),
          nowMs,
        );
        final output = <String, Object?>{
          'migrated': migrated,
          'script': _runScript(
            _patchedDatabase(fixture),
            PlayerSave.fromJson(migrated),
            fixture.inputField<List<Object?>>('ops'),
            nowMs,
          ),
        };
        expect(checkParity(fixture, output), isNull);
      });
    }
  });

  group('dialogue content validation parity', () {
    for (final fixture in loadParityFixtures('dialogue/validate')) {
      test(fixture.name, () {
        final db = fixture.inputMap.containsKey('patch')
            ? _patchedDatabase(fixture)
            : databaseOf(fixture);
        final issues = [for (final issue in validateDialogueContent(db)) issue.toJson()];
        expect(checkParity(fixture, {'issues': issues}), isNull);
      });
    }
  });

  test('the shipped content has no dialogue validation errors', () {
    final issues = validateDialogueContent(assertGameDatabaseShape(contentDatabaseJson()));
    expect(issues.where((issue) => issue.isError), isEmpty);
  });
}
