import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

const String _lowlyBeggar = 'QST-0003';
const String _beggar = 'NPC-0011';
const String _guard = 'NPC-0012';
const String _generalStoreMerchant = 'NPC-0007';
const String _barracks = 'LOC-0017';
const String _townBank = 'LOC-0034';
const String _generalStore = 'LOC-0024';

/// The Barracks Guard's shipped closing line for Lowly Beggar.
const String _guardClosingLineId = 'QDL-0031';
const Map<String, Object?> _guardClosingLine = <String, Object?>{
  'Dialogue ID': _guardClosingLineId,
  'Quest ID': _lowlyBeggar,
  'NPC ID': _guard,
  'Line': 'Hmph.',
  'Status': 'Confirmed',
  'Release Phase': 'Launch',
  'Notes': 'When: completed',
};

void main() {
  late GameDatabase db;
  late GameDatabase withoutLine;

  setUpAll(() {
    final raw = asJsonMap(contentDatabaseJson());
    db = filterLaunchContent(assertGameDatabaseShape(raw));
    // The shipped content minus the guard's line, to show what that line alone adds.
    final patched = Map<String, Object?>.of(raw);
    patched['QuestDialogue'] = <Object?>[
      for (final row in raw['QuestDialogue']! as List<Object?>)
        if ((row as Map<String, Object?>)['Dialogue ID'] != _guardClosingLineId) row,
    ];
    withoutLine = filterLaunchContent(assertGameDatabaseShape(patched));
  });

  NpcRow npcRow(GameDatabase database, String npcId) =>
      database.npcs.firstWhere((row) => row.raw['NPC ID'] == npcId);

  PlayerSave saveWith(String locationId, QuestProgress quest) =>
      createNewSave(db, 0).copyWith(currentLocationId: locationId, quests: [quest]);

  final done = QuestProgress(
    questId: _lowlyBeggar,
    status: 'completed',
    progress: 3,
    counters: const <String, num>{},
  );
  final heard = QuestProgress(
    questId: _lowlyBeggar,
    status: 'active',
    progress: 1,
    counters: const <String, num>{'talk:$_beggar': 1},
  );

  test('keeps a bystander\u2019s closing line on the panel once the quest is done', () {
    final save = saveWith(_barracks, done);
    // Without his closing line the finished quest leaves the guard's panel.
    expect(npcConversation(withoutLine, save, npcRow(withoutLine, _guard), 0).quests, isEmpty);

    // QDL-0031 ships that line, so the real content shows the block.
    expect(
      db.questDialogue.firstWhere((row) => row.dialogueId == _guardClosingLineId).raw,
      _guardClosingLine,
    );
    final guard = npcConversation(db, save, npcRow(db, _guard), 0);
    expect(guard.quests.map((quest) => quest.questId), [_lowlyBeggar]);
    final block = guard.quests.single;
    expect(block.status, 'completed');
    expect(block.completedNote, 'Hmph.');
    expect(block.talkLine, 'Hmph.');
    expect(block.canTalk, isFalse);
    expect(block.canTurnIn, isFalse);
    expect(block.canBribe, isFalse);
    expect(block.canChooseCombat, isFalse);
    expect(block.canAccept, isFalse);
    expect(block.canDonate, isFalse);
    expect(guard.greeting, isNull);

    final beggar = npcConversation(
      db,
      save.copyWith(currentLocationId: _townBank),
      npcRow(db, _beggar),
      0,
    );
    expect(beggar.quests.map((quest) => quest.questId), [_lowlyBeggar]);
    expect(beggar.quests.single.status, 'completed');
    expect(beggar.quests.single.completedNote, isNot('Hmph.'));
  });

  test('leaves a bystander\u2019s closing line out until the quest is done', () {
    final fresh = createNewSave(db, 0).copyWith(currentLocationId: _barracks);
    expect(npcConversation(db, fresh, npcRow(db, _guard), 0).quests, isEmpty);

    final guard = npcConversation(db, saveWith(_barracks, heard), npcRow(db, _guard), 0);
    expect(guard.quests.map((quest) => quest.questId), [_lowlyBeggar]);
    expect(guard.quests.single.status, 'active');
    expect(guard.quests.single.talkLine, contains('gossip'));
    expect(guard.quests.single.talkLine, isNot('Hmph.'));
    expect(guard.quests.single.canBribe, isTrue);
  });

  test('does not surface a finished quest to a bystander whose lines were all mid-quest', () {
    final merchant = npcConversation(
      db,
      saveWith(_generalStore, done),
      npcRow(db, _generalStoreMerchant),
      0,
    );
    expect(merchant.quests, isEmpty);
  });
}
