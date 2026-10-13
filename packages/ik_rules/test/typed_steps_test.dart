import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

/// Mirrors `src/game/quests/typedSteps.test.ts`.

/// Step typing as SYS-01 PR B (#323) ships it, applied to the live step rows.
const _typed = <String, Map<String, Object?>>{
  'QSTP-0014': {'Step Type': 'Show', 'Step Items': 'ITEM-0025:5', 'Step NPC': 'NPC-0014'},
  'QSTP-0016': {'Step Type': 'Show', 'Step Items': 'ITEM-0058:5', 'Step NPC': 'NPC-0014'},
  'QSTP-0022': {'Step Type': 'Talk', 'Step NPC': 'NPC-0014'},
  'QSTP-0023': {'Step Type': 'Talk', 'Step NPC': 'NPC-0014'},
  'QSTP-0024': {'Step Type': 'Talk', 'Step NPC': 'NPC-0014'},
  'QSTP-0035': {'Step Type': 'Talk', 'Step NPC': 'NPC-0014'},
};

Map<String, Object?> _launch(Map<String, Object?> row) => <String, Object?>{
  'Status': 'Confirmed',
  'Release Phase': 'Launch',
  'Notes': null,
  ...row,
};

List<Object?> _rows(Map<String, Object?> base, String table) =>
    base[table] as List<Object?>? ?? const [];

GameDatabase _typedDatabase() {
  final base = asJsonMap(contentDatabaseJson());
  return filterLaunchContent(
    assertGameDatabaseShape(<String, Object?>{
      ...base,
      'QuestSteps': [
        for (final raw in _rows(base, 'QuestSteps'))
          <String, Object?>{
            ...raw! as Map<String, Object?>,
            ...?_typed[(raw as Map<String, Object?>)['Step ID']],
          },
        _launch(<String, Object?>{
          'Step ID': 'QSTP-9202',
          'Quest ID': 'QST-0001',
          'Step Order': 3,
          'Journal Label': 'Later talk',
          'Step Type': 'Talk',
          'Step NPC': 'NPC-0001',
        }),
      ],
      'Dialogues': [
        ..._rows(base, 'Dialogues'),
        _launch(<String, Object?>{
          'Dialogue ID': 'DLG-9201',
          'Internal Key': 'dlg-9201',
          'Display Name': 'Fennel',
          'NPC ID': 'NPC-0014',
          'Start Node ID': 'DNODE-9201',
          'Repeatable': true,
        }),
      ],
      'DialogueNodes': [
        ..._rows(base, 'DialogueNodes'),
        _launch(<String, Object?>{
          'Node ID': 'DNODE-9201',
          'Dialogue ID': 'DLG-9201',
          'Line': 'Hello.',
        }),
      ],
      'DialogueChoices': [
        ..._rows(base, 'DialogueChoices'),
        _launch(<String, Object?>{
          'Choice ID': 'DCH-9201',
          'Node ID': 'DNODE-9201',
          'Label': 'About the farm',
          'Next Node ID': null,
          'Condition': 'quest_step:QST-0011:QSTP-0023',
          'Action': 'talk_flag:QST-0011:QSTP-0023',
          'Sort Order': 1,
        }),
      ],
    }),
  );
}

const _early = <String, num>{'step:QSTP-0013': 1, 'step:QSTP-0014': 1, 'step:QSTP-0015': 1};

void main() {
  late GameDatabase db;
  late GameDatabase untypedDb;

  setUpAll(() {
    db = _typedDatabase();
    final base = asJsonMap(contentDatabaseJson());
    untypedDb = filterLaunchContent(
      assertGameDatabaseShape(<String, Object?>{
        ...base,
        'QuestSteps': [
          for (final raw in _rows(base, 'QuestSteps'))
            if (raw case final Map<String, Object?> row)
              _typed.containsKey(row['Step ID'])
                  ? (Map<String, Object?>.of(row)
                      ..remove('Step Type')
                      ..remove('Step Items')
                      ..remove('Step NPC'))
                  : row,
        ],
      }),
    );
  });

  PlayerSave withQuest(String questId, Map<String, num> counters, {String status = 'active'}) {
    final base = createNewSave(db, 0).copyWith(currentLocationId: 'LOC-0001');
    return base.copyWith(
      quests: [
        ...base.quests.where((row) => row.questId != questId),
        QuestProgress(
          questId: questId,
          status: status,
          progress: counters.values.fold<num>(0, (sum, value) => sum + value),
          counters: counters,
        ),
      ],
    );
  }

  PlayerSave withSeed(PlayerSave save) =>
      save.copyWith(inventory: const [InventoryStack(itemId: 'ITEM-0324', quantity: 1)]);

  group('typed steps on saves already past them', () {
    late QuestRow gettingStarted;
    setUp(() => gettingStarted = getQuest(db, 'QST-0006')!);

    test(
      'makes an old save show the cooked potatoes again when nothing shows it is past the step',
      () {
        final save = withQuest('QST-0006', _early);
        expect(isStepPassed(db, save, 'QST-0006', 'QSTP-0016'), isFalse);
        expect(getCurrentStepId(db, save, gettingStarted), 'QSTP-0016');
      },
    );

    test('counts an unmarked Show step as done once a later step is done', () {
      final save = withQuest('QST-0006', {..._early, 'step:QSTP-0022': 1});
      expect(isStepPassed(db, save, 'QST-0006', 'QSTP-0016'), isTrue);
      expect(getCurrentStepId(db, save, gettingStarted), isNull);
      expect(stepProgressGroup(db, save, 'QST-0006', 'QSTP-0016')?.done, isTrue);
    });

    test('counts an unmarked Show step as done once a later step is active', () {
      final save = withQuest('QST-0006', {..._early, 'talk:NPC-0014:QSTP-0022': 1});
      expect(getCurrentStepId(db, save, gettingStarted), 'QSTP-0022');
    });

    test('counts a later Notes-driven step met from saved counters', () {
      final atShow = withQuest('QST-0006', {'step:QSTP-0013': 1});
      expect(getCurrentStepId(db, atShow, gettingStarted), 'QSTP-0014');

      final cooked = withQuest('QST-0006', {
        'step:QSTP-0013': 1,
        'visit:LOC-0023': 1,
        'process:RCP-0001': 5,
      });
      expect(isStepPassed(db, cooked, 'QST-0006', 'QSTP-0014'), isTrue);
      expect(getCurrentStepId(db, cooked, gettingStarted), 'QSTP-0016');
    });

    test('never writes a done mark for a passed step', () {
      final save = withQuest('QST-0006', {..._early, 'talk:NPC-0014:QSTP-0022': 1});
      final after = applyQuestStepUnlocks(db, save);
      expect(
        getQuestProgress(after, 'QST-0006').counters,
        getQuestProgress(save, 'QST-0006').counters,
      );
    });

    test('refuses the dialogue action for a step the quest is past', () {
      final save = withQuest('QST-0011', {'step:QSTP-0024': 1});
      final result = chooseDialogue(db, save, 'DLG-9201', 'DNODE-9201', 'DCH-9201');
      expect(result.ok, isFalse);
      expect(result.code, 'not_available');
    });
  });

  group('farm patch for dialogue-only players (Green Thumb)', () {
    test('stays locked while Green Thumb has no Fennel progress', () {
      final save = withQuest('QST-0011', {});
      expect(farmBotanyUnlocked(db, save), isFalse);
      expect(canPlantBotanySeed(db, withSeed(save), 'ITEM-0324').ok, isFalse);
    });

    test('unlocks when the dialogue Talk step with Fennel is done', () {
      final save = withQuest('QST-0011', {'step:QSTP-0023': 1});
      expect(farmBotanyUnlocked(db, save), isTrue);
      expect(canPlantBotanySeed(db, withSeed(save), 'ITEM-0324').ok, isTrue);
      expect(
        discoverTimerSpotsForLocation(db, save, 'LOC-0001').discoveredTimerSpotIds,
        contains('botany:LOC-0001'),
      );
    });

    test('unlocks when the quest is past that step even if it was never marked', () {
      expect(farmBotanyUnlocked(db, withQuest('QST-0011', {'step:QSTP-0024': 1})), isTrue);
    });

    test('unlocks after talking to Fennel through dialogue only', () {
      final talked = chooseDialogue(
        db,
        withQuest('QST-0011', {}),
        'DLG-9201',
        'DNODE-9201',
        'DCH-9201',
      );
      expect(talked.ok, isTrue, reason: talked.reason);
      expect(getQuestProgress(talked.save, 'QST-0011').counters, {'step:QSTP-0023': 1});
      expect(farmBotanyUnlocked(db, talked.save), isTrue);
      expect(talked.save.discoveredTimerSpotIds, contains('botany:LOC-0001'));
    });

    test('still unlocks through the panel talk counter and on completion', () {
      expect(farmBotanyUnlocked(db, withQuest('QST-0011', {'talk:NPC-0014': 1})), isTrue);
      expect(farmBotanyUnlocked(db, withQuest('QST-0011', {}, status: 'completed')), isTrue);
    });

    test('ignores step marks on untyped steps, as before #323', () {
      expect(farmBotanyUnlocked(untypedDb, withQuest('QST-0011', {'step:QSTP-0023': 1})), isFalse);
    });

    test('adds the farm timer spot after panel talk', () {
      final talked = talkWithQuestNpc(db, withQuest('QST-0011', {}), 'NPC-0014');
      expect(talked.ok, isTrue);
      expect(talked.save!.discoveredTimerSpotIds, contains('botany:LOC-0001'));
    });
  });

  group('HandIn steps only count with their step latch (option b)', () {
    late QuestRow feast;
    setUp(() => feast = getQuest(db, 'QST-0001')!);

    test('stays current when a later step is latched', () {
      final save = withQuest('QST-0001', {'step:QSTP-0001': 1, 'step:QSTP-9202': 1});
      expect(isStepPassed(db, save, 'QST-0001', 'QSTP-0002'), isTrue);
      expect(isStepComplete(db, save, 'QST-0001', '', 'QSTP-0002'), isFalse);
      expect(getCurrentStepId(db, save, feast), 'QSTP-0002');
      expect(stepProgressGroup(db, save, 'QST-0001', 'QSTP-0002')?.done, isFalse);
    });

    test('counts as done once the step latch is written', () {
      final save = withQuest('QST-0001', {'step:QSTP-0001': 1, 'step:QSTP-0002': 1});
      expect(isStepComplete(db, save, 'QST-0001', '', 'QSTP-0002'), isTrue);
      expect(getCurrentStepId(db, save, feast), 'QSTP-9202');
      expect(stepProgressGroup(db, save, 'QST-0001', 'QSTP-0002')?.done, isTrue);
    });

    test('stays unfinished when only a partial hand-in counter is present', () {
      final save = withQuest('QST-0001', {
        'step:QSTP-0001': 1,
        'handIn:QSTP-0002:ITEM-0058': 4,
        'step:QSTP-9202': 1,
      });
      expect(isStepComplete(db, save, 'QST-0001', '', 'QSTP-0002'), isFalse);
      expect(getCurrentStepId(db, save, feast), 'QSTP-0002');
      expect(stepProgressGroup(db, save, 'QST-0001', 'QSTP-0002')?.done, isFalse);
    });
  });
}
