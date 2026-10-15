import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

const _farmerDescription = 'A farmer who lives at the farm.';
const _fennelId = 'NPC-0014';
const _greenThumb = 'QST-0011';
const _feast = 'QST-0001';
const _potatoSeed = 'ITEM-0324';
const _compost = 'ITEM-0377';
const _compostAction = 'ACN-0199';
const _talk = 'QSTP-0023';
const _compostStep = 'QSTP-0024';
const _plant = 'QSTP-0034';
const _returnStep = 'QSTP-0035';

void main() {
  late GameDatabase db;
  late Map<String, Object?> raw;
  late NpcRow fennel;

  setUpAll(() {
    raw = asJsonMap(contentDatabaseJson());
    db = filterLaunchContent(assertGameDatabaseShape(raw));
    fennel = db.npcs.singleWhere((row) => row.npcId == _fennelId);
  });

  PlayerSave startGreenThumb() {
    final save = applyQuestAutoStartOnSeed(
      db,
      createNewSave(db, 0).copyWith(
        currentLocationId: 'LOC-0001',
        inventory: const [InventoryStack(itemId: _potatoSeed, quantity: 1)],
        quests: const [QuestProgress(questId: 'QST-0006', status: 'completed', progress: 1)],
      ),
    );
    expect(getQuestProgress(save, _greenThumb).status, 'active');
    return save;
  }

  MiniQuestJournalRow journalRow(PlayerSave save) =>
      miniQuestJournal(db, save, 0).singleWhere((row) => row.questId == _greenThumb);

  List<Map<String, Object?>> stepJson(Iterable<QuestJournalStep> steps) => [
    for (final step in steps) step.toJson(),
  ];

  NpcQuestBlock greenThumb(PlayerSave save) =>
      npcConversation(db, save, fennel, 0).quests.singleWhere((row) => row.questId == _greenThumb);

  LogSectionCompletion questsSection(PlayerSave save) => logCompletion(db, save).section('quests')!;

  String nodeLine(String nodeId) =>
      db.dialogueNodes.singleWhere((row) => row.nodeId == nodeId).line;

  NpcQuestBlock spokenBlock({String? talkLine, String idlePrompt = ''}) => NpcQuestBlock(
    questId: _greenThumb,
    name: 'Green Thumb',
    summary: null,
    status: 'active',
    completedNote: '',
    acceptLabel: 'Accept',
    donateLabel: 'Donate',
    pitchLine: null,
    lines: const <QuestDeliverLine>[],
    progressLines: const <QuestProgressLine>[],
    goldOwned: 0,
    goldRequired: 0,
    ready: false,
    canAccept: false,
    canDonate: false,
    donated: false,
    canTurnIn: false,
    canTalk: talkLine != null,
    talkLabel: 'Talk',
    talkLine: talkLine,
    canBribe: false,
    bribeLabel: 'Bribe',
    canChooseCombat: false,
    combatLabel: 'Fight',
    idlePrompt: idlePrompt,
  );

  void expectNoFarmerLine(Iterable<String?> parts) {
    for (final part in parts) {
      expect(part ?? '', isNot(contains(_farmerDescription)));
    }
  }

  test('lists and ticks Green Thumb steps through the shared journal logic', () {
    var save = startGreenThumb();
    final quest = getQuest(db, _greenThumb)!;
    expect(questLog(db, save).any((row) => row.questId == _greenThumb), isFalse);

    var row = journalRow(save);
    expect(stepJson(row.steps), stepJson(questJournalSteps(db, save, quest)));
    expect(stepJson(row.steps), stepJson(questStepJournal(db, save, quest)));
    expect(getCurrentStepId(db, save, quest), _talk);
    expect(row.steps.singleWhere((step) => step.key == _talk).toJson(), {
      'key': _talk,
      'label': 'Speak with Fennel at the farm',
      'state': 'current',
    });

    save = chooseDialogue(db, save, 'DLG-0007', 'DNODE-0011', 'DCH-0014').save;
    row = journalRow(save);
    expect(stepJson(row.steps), stepJson(questJournalSteps(db, save, quest)));
    expect(stepJson(row.steps), stepJson(questStepJournal(db, save, quest)));
    expect(row.steps.singleWhere((step) => step.key == _talk).state, 'done');
    expect(row.steps.singleWhere((step) => step.key == _compostStep).toJson(), {
      'key': _compostStep,
      'label': 'Gather compost and speak with Fennel',
      'state': 'current',
    });

    save = applyQuestActionProgress(db, addItemToInventory(save, _compost, 1), _compostAction);
    save = chooseDialogue(db, save, 'DLG-0008', 'DNODE-0013', 'DCH-0017').save;
    row = journalRow(save);
    expect(stepJson(row.steps), stepJson(questJournalSteps(db, save, quest)));
    expect(getCurrentStepId(db, save, quest), _plant);
    expect(row.steps.singleWhere((step) => step.key == _compostStep).state, 'done');
    expect(row.steps.singleWhere((step) => step.key == _plant).toJson(), {
      'key': _plant,
      'label': 'Plant a potato seed with compost',
      'state': 'current',
    });

    final planted = plantBotanySelection(
      db,
      save,
      const [_potatoSeed],
      nowMs: 0,
      usedCompost: true,
    );
    expect(planted.ok, isTrue, reason: planted.reason);
    save = planted.save!;
    row = journalRow(save);
    expect(stepJson(row.steps), stepJson(questJournalSteps(db, save, quest)));
    expect(getCurrentStepId(db, save, quest), _returnStep);
    expect(row.steps.singleWhere((step) => step.key == _plant).state, 'done');
    expect(row.steps.singleWhere((step) => step.key == _returnStep).toJson(), {
      'key': _returnStep,
      'label': 'Return to Fennel',
      'state': 'current',
    });

    save = chooseDialogue(db, save, 'DLG-0010', 'DNODE-0016', 'DCH-0021').save;
    row = journalRow(save);
    expect(row.completed, isTrue);
    expect(stepJson(row.steps), stepJson(questJournalSteps(db, save, quest)));
    expect(
      row.steps.where((step) => step.key.startsWith('QSTP-')).every((step) => step.state == 'done'),
      isTrue,
    );
  });

  test('keeps quest-log % still when a miniquest completes, and raises it for a normal quest', () {
    final save = startGreenThumb();
    final before = questsSection(save);
    expect(before.total, greaterThan(0));

    final miniDone = save.copyWith(
      quests: [
        for (final row in save.quests)
          if (row.questId == _greenThumb) row.copyWith(status: 'completed') else row,
      ],
    );
    final afterMini = questsSection(miniDone);
    expect(afterMini.done, before.done);
    expect(afterMini.total, before.total);
    expect(afterMini.percent, before.percent);
    expect(afterMini.label, before.label);

    final feastDone = miniDone.copyWith(
      quests: [
        ...miniDone.quests.where((row) => row.questId != _feast),
        const QuestProgress(questId: _feast, status: 'completed', progress: 10),
      ],
    );
    final afterFeast = questsSection(feastDone);
    expect(afterFeast.done, before.done + 1);
    expect(afterFeast.total, before.total);
    expect(afterFeast.percent, greaterThanOrEqualTo(before.percent));
    expect(afterFeast.label, isNot(before.label));
  });

  test(
    'never shows Fennel description on a full run, and questSpokenLine has no description fallback',
    () {
      expect(questSpokenLine(spokenBlock()), '');
      expect(questSpokenLine(spokenBlock(talkLine: '  ', idlePrompt: '  ')), '');
      expect(questSpokenLine(spokenBlock(idlePrompt: 'Idle copy')), 'Idle copy');
      expect(
        questSpokenLine(spokenBlock(talkLine: 'Talk copy', idlePrompt: 'Idle copy')),
        'Talk copy',
      );
      expect(questSpokenLine(spokenBlock()), isNot(_farmerDescription));

      final lines = <String?>[];
      void record(PlayerSave save, [List<String?> extra = const <String?>[]]) {
        final conversation = npcConversation(db, save, fennel, 0);
        final block = conversation.quests.where((row) => row.questId == _greenThumb).firstOrNull;
        if (block != null) {
          lines.addAll([
            questSpokenLine(block),
            block.talkLine,
            block.idlePrompt,
            block.completedNote,
          ]);
        }
        lines
          ..add(conversation.description)
          ..addAll(extra);
      }

      var save = startGreenThumb();
      record(save, [greenThumb(save).talkLine, startDialogue(db, save, 'DLG-0007').view?.line]);
      expect(questSpokenLine(greenThumb(save)), contains('found a seed'));

      final firstTalk = chooseDialogue(db, save, 'DLG-0007', 'DNODE-0011', 'DCH-0014');
      expect(firstTalk.ok, isTrue, reason: firstTalk.reason);
      save = firstTalk.save;
      record(save, [firstTalk.message]);
      expect(questSpokenLine(greenThumb(save)), '');
      expect(greenThumb(save).talkLine, isNull);
      expect(greenThumb(save).idlePrompt, '');

      save = applyQuestActionProgress(db, addItemToInventory(save, _compost, 1), _compostAction);
      record(save, [startDialogue(db, save, 'DLG-0008').view?.line]);
      expect(questSpokenLine(greenThumb(save)), contains('compost'));

      final compostTalk = chooseDialogue(db, save, 'DLG-0008', 'DNODE-0013', 'DCH-0017');
      expect(compostTalk.ok, isTrue, reason: compostTalk.reason);
      save = compostTalk.save;
      record(save, [compostTalk.message, startDialogue(db, save, 'DLG-0009').view?.line]);
      expect(questSpokenLine(greenThumb(save)), '');

      final planted = plantBotanySelection(
        db,
        save,
        const [_potatoSeed],
        nowMs: 0,
        usedCompost: true,
      );
      expect(planted.ok, isTrue, reason: planted.reason);
      save = planted.save!;
      record(save, [startDialogue(db, save, 'DLG-0010').view?.line]);
      expect(questSpokenLine(greenThumb(save)), contains('Well done'));

      final finished = chooseDialogue(db, save, 'DLG-0010', 'DNODE-0016', 'DCH-0021');
      expect(finished.ok, isTrue, reason: finished.reason);
      save = finished.save;
      record(save, [finished.message]);

      expectNoFarmerLine(lines);
      expect(fennel.raw['Description'], '');
    },
  );

  test(
    'speaks Green Thumb lines in step order: talk, compost, plant reminder, return and reward',
    () {
      expect(
        [
          for (final row in db.dialogues)
            if (row.npcId == _fennelId && (row.condition ?? '').contains(_greenThumb))
              (row.dialogueId, row.condition),
        ],
        [
          ('DLG-0007', 'quest_step:$_greenThumb:$_talk'),
          ('DLG-0008', 'quest_step:$_greenThumb:$_compostStep'),
          ('DLG-0009', 'quest_step:$_greenThumb:$_plant'),
          ('DLG-0010', 'quest_step:$_greenThumb:$_returnStep'),
        ],
      );

      expect(
        [
          for (final row in db.questDialogue)
            if (row.questId == _greenThumb) (row.notes, row.line),
        ],
        [
          ('RequiresStep: $_talk', nodeLine('DNODE-0011')),
          ('RequiresStep: $_compostStep', nodeLine('DNODE-0013')),
          ('When: completed', nodeLine('DNODE-0017')),
          ('RequiresStep: $_returnStep', nodeLine('DNODE-0016')),
        ],
      );

      var save = startGreenThumb();
      expect(getCurrentStepId(db, save, getQuest(db, _greenThumb)!), _talk);
      expect(dialoguesForNpc(db, save, _fennelId).first, 'DLG-0007');
      expect(startDialogue(db, save, 'DLG-0007').view?.line, nodeLine('DNODE-0011'));
      expect(greenThumb(save).talkLine, nodeLine('DNODE-0011'));

      save = chooseDialogue(db, save, 'DLG-0007', 'DNODE-0011', 'DCH-0014').save;
      save = applyQuestActionProgress(db, addItemToInventory(save, _compost, 1), _compostAction);
      expect(getCurrentStepId(db, save, getQuest(db, _greenThumb)!), _compostStep);
      expect(dialoguesForNpc(db, save, _fennelId).first, 'DLG-0008');
      expect(startDialogue(db, save, 'DLG-0008').view?.line, nodeLine('DNODE-0013'));
      expect(greenThumb(save).talkLine, nodeLine('DNODE-0013'));

      save = chooseDialogue(db, save, 'DLG-0008', 'DNODE-0013', 'DCH-0017').save;
      expect(getCurrentStepId(db, save, getQuest(db, _greenThumb)!), _plant);
      expect(dialoguesForNpc(db, save, _fennelId).first, 'DLG-0009');
      expect(startDialogue(db, save, 'DLG-0009').view?.line, nodeLine('DNODE-0015'));
      expect(startDialogue(db, save, 'DLG-0009').view?.line, contains('patch'));

      final planted = plantBotanySelection(
        db,
        save,
        const [_potatoSeed],
        nowMs: 0,
        usedCompost: true,
      );
      expect(planted.ok, isTrue, reason: planted.reason);
      save = planted.save!;
      expect(getCurrentStepId(db, save, getQuest(db, _greenThumb)!), _returnStep);
      expect(dialoguesForNpc(db, save, _fennelId).first, 'DLG-0010');
      expect(startDialogue(db, save, 'DLG-0010').view?.line, nodeLine('DNODE-0016'));
      expect(greenThumb(save).talkLine, nodeLine('DNODE-0016'));

      save = chooseDialogue(db, save, 'DLG-0010', 'DNODE-0016', 'DCH-0021').save;
      expect(getQuestProgress(save, _greenThumb).status, 'completed');
      expect(greenThumb(save).completedNote, nodeLine('DNODE-0017'));
    },
  );

  test('clears Fennel description and drops the old farm line', () {
    expect(fennel.raw['Description'], '');
    expect(fennel.raw['Description'], isNot(_farmerDescription));
    final npcRows = raw['NPCs']! as List<Object?>;
    expect([
      for (final row in npcRows)
        if (row case final Map<String, Object?> npc)
          if (npc['Description'] == _farmerDescription) npc['NPC ID'],
    ], isEmpty);
    expect(npcRows.toString(), isNot(contains(_farmerDescription)));
  });
}
