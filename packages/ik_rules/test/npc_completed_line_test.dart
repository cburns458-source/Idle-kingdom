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

/// A closing line for the Barracks Guard, who only takes part in Lowly Beggar.
const Map<String, Object?> _guardClosingLine = <String, Object?>{
  'Dialogue ID': 'QDL-9001',
  'Quest ID': _lowlyBeggar,
  'NPC ID': _guard,
  'Line': 'Hmph.',
  'Status': 'Confirmed',
  'Release Phase': 'Launch',
  'Notes': 'When: completed',
};

void main() {
  late GameDatabase db;
  late GameDatabase withLine;

  setUpAll(() {
    final raw = asJsonMap(contentDatabaseJson());
    db = filterLaunchContent(assertGameDatabaseShape(raw));
    final patched = Map<String, Object?>.of(raw);
    patched['QuestDialogue'] = <Object?>[
      ...raw['QuestDialogue']! as List<Object?>,
      _guardClosingLine,
    ];
    withLine = filterLaunchContent(assertGameDatabaseShape(patched));
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
    expect(npcConversation(db, save, npcRow(db, _guard), 0).quests, isEmpty);

    final guard = npcConversation(withLine, save, npcRow(withLine, _guard), 0);
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
      withLine,
      save.copyWith(currentLocationId: _townBank),
      npcRow(withLine, _beggar),
      0,
    );
    expect(beggar.quests.map((quest) => quest.questId), [_lowlyBeggar]);
    expect(beggar.quests.single.status, 'completed');
    expect(beggar.quests.single.completedNote, isNot('Hmph.'));
  });

  test('leaves a bystander\u2019s closing line out until the quest is done', () {
    final fresh = createNewSave(db, 0).copyWith(currentLocationId: _barracks);
    expect(npcConversation(withLine, fresh, npcRow(withLine, _guard), 0).quests, isEmpty);

    final guard = npcConversation(
      withLine,
      saveWith(_barracks, heard),
      npcRow(withLine, _guard),
      0,
    );
    expect(guard.quests.map((quest) => quest.questId), [_lowlyBeggar]);
    expect(guard.quests.single.status, 'active');
    expect(guard.quests.single.talkLine, contains('gossip'));
    expect(guard.quests.single.canBribe, isTrue);
  });

  test('does not surface a finished quest to a bystander whose lines were all mid-quest', () {
    final merchant = npcConversation(
      withLine,
      saveWith(_generalStore, done),
      npcRow(withLine, _generalStoreMerchant),
      0,
    );
    expect(merchant.quests, isEmpty);
  });
}
