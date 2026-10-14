import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

/// Mirrors `src/game/quests/optionalSteps.test.ts`.
///
/// A step whose Notes carry a bare `Optional` field is passed over while
/// unfinished: it is never current, it does not stop later steps latching, and
/// the quest completes once the required steps are done.

const _quest = 'QST-9301';
const _visitStep = 'QSTP-9301';
const _holdStep = 'QSTP-9302';
const _cookStep = 'QSTP-9303';
const _defeatStep = 'QSTP-9304';

const _kitchen = 'LOC-0023';
const _bakedPotato = 'ITEM-0058';
const _bakeRecipe = 'RCP-0001';

Map<String, Object?> _step(String id, num order, String label, String notes) => <String, Object?>{
  'Step ID': id,
  'Quest ID': _quest,
  'Step Order': order,
  'Journal Label': label,
  'Notes': notes,
  'Step Type': null,
  'Step Items': null,
  'Step NPC': null,
  'Status': 'Confirmed',
  'Release Phase': 'Launch',
};

/// Test-only content matching `OPTIONAL_STEPS_PATCH` in
/// `src/parity/scenarios/optionalSteps.ts`: visit the kitchen (required), hold
/// ten baked potatoes (optional), bake one (required), defeat a goblin
/// (optional, trailing).
final Map<String, List<Map<String, Object?>>> _patch = <String, List<Map<String, Object?>>>{
  'Quests': [
    <String, Object?>{
      'Quest ID': _quest,
      'Internal Key': 'optional_steps_fixture',
      'Display Name': 'Optional Steps',
      'NPC ID': 'NPC-0014',
      'Summary': null,
      'Pitch': null,
      'Status': 'Confirmed',
      'Release Phase': 'Launch',
      'Notes': null,
      'Objective Type': null,
      'Objective Target ID': null,
      'Required Quantity': null,
      'Repeatable': null,
      'Reward XP Skill ID': null,
      'Reward XP Amount': null,
      'Reward Item ID': null,
      'Reward Item Quantity': null,
      'Possible Rewards': null,
    },
  ],
  'QuestSteps': [
    _step(_visitStep, 1, 'Visit the kitchen', 'Visit: $_kitchen'),
    _step(_holdStep, 2, 'Hold ten baked potatoes', 'Hold: $_bakedPotato x10; Optional'),
    _step(_cookStep, 3, 'Bake a potato', 'Process: $_bakeRecipe x1'),
    _step(_defeatStep, 4, 'Defeat a goblin', 'Defeat: ENM-0001 x1; Optional'),
  ],
};

GameDatabase _patchedDatabase() {
  final base = asJsonMap(contentDatabaseJson());
  final db = <String, Object?>{...base};
  for (final entry in _patch.entries) {
    db[entry.key] = <Object?>[...(base[entry.key] as List<Object?>? ?? const []), ...entry.value];
  }
  return assertGameDatabaseShape(db);
}

QuestStepRow _row(String? notes) => QuestStepRow(<String, Object?>{'Notes': notes});

PlayerSave _setCount(PlayerSave save, String itemId, num quantity) {
  final cleared = save.copyWith(
    inventory: save.inventory.where((stack) => stack.itemId != itemId).toList(),
  );
  return quantity > 0 ? addItemToInventory(cleared, itemId, quantity) : cleared;
}

void main() {
  late GameDatabase db;
  late QuestRow quest;

  setUpAll(() {
    db = _patchedDatabase();
    quest = getQuest(db, _quest)!;
  });

  PlayerSave fresh() {
    final save = createNewSave(db, 0);
    return save.copyWith(
      quests: [
        ...save.quests.where((row) => row.questId != _quest),
        const QuestProgress(questId: _quest, status: 'active', progress: 0, counters: {}),
      ],
    );
  }

  int index(PlayerSave save) => getCurrentStepIndex(db, save, quest);
  String? current(PlayerSave save) => getCurrentStepId(db, save, quest);
  bool latched(PlayerSave save, String stepId) => isStepLatched(save, _quest, stepId);

  group('isOptionalStep', () {
    test('matches a whole trimmed Optional field', () {
      expect(isOptionalStep(_row('Hold: ITEM-0058 x10; Optional')), isTrue);
      expect(isOptionalStep(_row('Optional')), isTrue);
      expect(isOptionalStep(_row('Hold: ITEM-0058 x10;Optional')), isTrue);
      expect(isOptionalStep(_row('  Optional  ; Visit: LOC-0023')), isTrue);
    });

    test('is not fooled by prefixes, values or case', () {
      expect(isOptionalStep(_row('Talk: NPC-0012; OptionalTalk: NPC-0007')), isFalse);
      expect(isOptionalStep(_row('Optional: yes')), isFalse);
      expect(isOptionalStep(_row('Optional Talk')), isFalse);
      expect(isOptionalStep(_row('optional')), isFalse);
      expect(isOptionalStep(_row('Hold: ITEM-0058 x10')), isFalse);
      expect(isOptionalStep(_row('')), isFalse);
      expect(isOptionalStep(_row(null)), isFalse);
      expect(isOptionalStep(null), isFalse);
    });

    test('reads the fixture quest as required, optional, required, optional', () {
      expect(getQuestSteps(db, _quest).map(isOptionalStep).toList(), [false, true, false, true]);
    });

    test('marks no shipped step optional', () {
      final shipped = db.questSteps.where((step) => step.questId != _quest).toList();
      expect(shipped, isNotEmpty);
      expect(shipped.any(isOptionalStep), isFalse);
    });
  });

  group('optional quest steps', () {
    test('starts on the first required step', () {
      final save = fresh();
      expect(index(save), 0);
      expect(current(save), _visitStep);
      expect(questAllStepsComplete(db, save, quest), isFalse);
    });

    test('does not latch a finished optional step ahead of an unfinished required one', () {
      final save = applyQuestStepUnlocks(db, _setCount(fresh(), _bakedPotato, 10));
      expect(latched(save, _holdStep), isFalse);
      expect(getQuestProgress(save, _quest).counters, isEmpty);
      expect(current(save), _visitStep);
    });

    test('passes over the unfinished optional step once the step before it is done', () {
      final save = applyQuestVisitProgress(db, fresh(), _kitchen);
      expect(latched(save, _visitStep), isTrue);
      expect(latched(save, _holdStep), isFalse);
      expect(index(save), 2);
      expect(current(save), _cookStep);
      final targets = questActiveStepObjectives(db, save, quest)!.processTargets;
      expect(targets.map((line) => line.toJson()).toList(), [
        {'targetId': _bakeRecipe, 'quantity': 1},
      ]);
    });

    test('latches a finished optional step and keeps the latch after the bag changes', () {
      var save = applyQuestVisitProgress(db, fresh(), _kitchen);
      save = applyQuestStepUnlocks(db, _setCount(save, _bakedPotato, 10));
      expect(latched(save, _holdStep), isTrue);
      expect(current(save), _cookStep);

      save = applyQuestStepUnlocks(db, _setCount(save, _bakedPotato, 0));
      expect(latched(save, _holdStep), isTrue);
      expect(current(save), _cookStep);
    });

    test('completes on the required steps with both optional steps untouched', () {
      var save = fresh();
      expect(completeQuest(db, save, _quest, ignoreLocation: true).ok, isFalse);

      save = applyQuestVisitProgress(db, save, _kitchen);
      save = applyQuestProcessProgress(db, save, _bakeRecipe);
      expect(latched(save, _cookStep), isTrue);
      expect(latched(save, _holdStep), isFalse);
      expect(latched(save, _defeatStep), isFalse);
      expect(index(save), getQuestSteps(db, _quest).length);
      expect(current(save), isNull);
      expect(questAllStepsComplete(db, save, quest), isTrue);
      expect(questObjectiveProgress(db, save, quest).ready, isTrue);

      final turnedIn = completeQuest(db, save, _quest, ignoreLocation: true);
      expect(turnedIn.ok, isTrue, reason: turnedIn.reason);
      expect(getQuestProgress(turnedIn.save!, _quest).status, 'completed');
    });

    test('still needs every required step', () {
      final save = applyQuestStepUnlocks(
        db,
        applyQuestVisitProgress(db, _setCount(fresh(), _bakedPotato, 10), _kitchen),
      );
      expect(latched(save, _visitStep), isTrue);
      expect(latched(save, _holdStep), isTrue);
      expect(current(save), _cookStep);
      expect(questAllStepsComplete(db, save, quest), isFalse);
      expect(completeQuest(db, save, _quest, ignoreLocation: true).ok, isFalse);
    });
  });
}
