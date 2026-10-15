import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

const _optionalMiniquest = 'QST-9302';
const _optionalHold = 'QSTP-9312';
const _kitchen = 'LOC-0023';
const _bakeRecipe = 'RCP-0001';

Map<String, Object?> _step(String id, num order, String label, String notes) => <String, Object?>{
  'Step ID': id,
  'Quest ID': _optionalMiniquest,
  'Step Order': order,
  'Journal Label': label,
  'Notes': notes,
  'Step Type': null,
  'Step Items': null,
  'Step NPC': null,
  'Status': 'Confirmed',
  'Release Phase': 'Launch',
};

final Map<String, List<Map<String, Object?>>> _patch = <String, List<Map<String, Object?>>>{
  'Quests': [
    <String, Object?>{
      'Quest ID': _optionalMiniquest,
      'Internal Key': 'miniquest_optional_journal',
      'Display Name': 'Miniquest Optional Journal',
      'NPC ID': 'NPC-0014',
      'Summary': 'A test miniquest with a skipped optional step.',
      'Pitch': null,
      'Status': 'Confirmed',
      'Release Phase': 'Launch',
      'Notes': 'Miniquest; HideFromQuestLog',
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
    _step('QSTP-9311', 1, 'Visit the kitchen', 'Visit: $_kitchen'),
    _step(_optionalHold, 2, 'Hold ten baked potatoes', 'Hold: ITEM-0058 x10; Optional'),
    _step('QSTP-9313', 3, 'Bake a potato', 'Process: $_bakeRecipe x1'),
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

void main() {
  late GameDatabase launch;
  late GameDatabase optionalDb;

  setUpAll(() {
    launch = assertGameDatabaseShape(contentDatabaseJson());
    optionalDb = _patchedDatabase();
  });

  test('lists Green Thumb steps with the shared journal and keeps them out of quest %', () {
    var save = createNewSave(launch, 0).copyWith(
      currentLocationId: 'LOC-0001',
      inventory: const [InventoryStack(itemId: 'ITEM-0324', quantity: 1)],
      quests: const [QuestProgress(questId: 'QST-0006', status: 'completed', progress: 1)],
    );
    save = applyQuestAutoStartOnSeed(launch, save);
    final quest = getQuest(launch, 'QST-0011')!;
    final row = miniQuestJournal(
      launch,
      save,
      0,
    ).singleWhere((entry) => entry.questId == 'QST-0011');
    expect(questLog(launch, save).any((entry) => entry.questId == 'QST-0011'), isFalse);
    expect(row.steps.map((step) => step.toJson()).toList(), [
      for (final step in questJournalSteps(launch, save, quest)) step.toJson(),
    ]);
    expect(row.steps.map((step) => step.toJson()).toList(), [
      for (final step in questStepJournal(launch, save, quest)) step.toJson(),
    ]);
    expect(row.steps.first.label, 'Speak with Fennel at the farm');
    expect(row.steps.first.state, 'current');

    final before = logCompletion(launch, save).section('quests')!;
    final miniDone = save.copyWith(
      quests: [
        for (final entry in save.quests)
          if (entry.questId == 'QST-0011') entry.copyWith(status: 'completed') else entry,
      ],
    );
    final afterMini = logCompletion(launch, miniDone).section('quests')!;
    expect(afterMini.done, before.done);
    expect(afterMini.total, before.total);

    final feastDone = miniDone.copyWith(
      quests: [
        ...miniDone.quests.where((entry) => entry.questId != 'QST-0001'),
        const QuestProgress(questId: 'QST-0001', status: 'completed', progress: 10),
      ],
    );
    final afterFeast = logCompletion(launch, feastDone).section('quests')!;
    expect(afterFeast.done, before.done + 1);
    expect(afterFeast.total, before.total);
  });

  test('ticks a skipped optional miniquest step the same way a normal quest does', () {
    final quest = getQuest(optionalDb, _optionalMiniquest)!;
    expect(
      isOptionalStep(optionalDb.questSteps.firstWhere((row) => row.stepId == _optionalHold)),
      isTrue,
    );
    var save = createNewSave(optionalDb, 0).copyWith(
      quests: const [
        QuestProgress(questId: _optionalMiniquest, status: 'active', progress: 0, counters: {}),
      ],
    );
    save = applyQuestVisitProgress(optionalDb, save, _kitchen);
    save = applyQuestProcessProgress(optionalDb, save, _bakeRecipe);

    final journal = miniQuestJournal(
      optionalDb,
      save,
      0,
    ).singleWhere((row) => row.questId == _optionalMiniquest);
    expect(journal.steps.map((step) => step.toJson()).toList(), [
      for (final step in questStepJournal(optionalDb, save, quest)) step.toJson(),
    ]);
    expect(journal.steps.singleWhere((step) => step.key == _optionalHold).toJson(), {
      'key': _optionalHold,
      'label': 'Hold ten baked potatoes',
      'state': 'current',
    });
    expect(questLog(optionalDb, save).any((row) => row.questId == _optionalMiniquest), isFalse);

    final before = logCompletion(optionalDb, save).section('quests')!;
    final finished = completeQuest(optionalDb, save, _optionalMiniquest, ignoreLocation: true);
    expect(finished.ok, isTrue);
    final afterMini = logCompletion(optionalDb, finished.save!).section('quests')!;
    expect(afterMini.done, before.done);
    expect(afterMini.total, before.total);
    expect(
      miniQuestJournal(optionalDb, finished.save!, 0)
          .singleWhere((row) => row.questId == _optionalMiniquest)
          .steps
          .singleWhere((step) => step.key == _optionalHold)
          .toJson(),
      {'key': _optionalHold, 'label': 'Hold ten baked potatoes', 'state': 'done'},
    );
  });
}
