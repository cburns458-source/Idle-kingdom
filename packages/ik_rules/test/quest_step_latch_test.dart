import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

// BUG-01: completed quest steps latch via a `step:<stepId>` counter so live
// `Hold:` checks can't send Getting Started (QST-0006) back to step 1.

const _quest = 'QST-0006';
const _fennel = 'NPC-0014';
const _raw = 'ITEM-0025';
const _cooked = 'ITEM-0058';
const _kitchen = 'LOC-0023';
const _recipe = 'RCP-0001';

PlayerSave _setCount(PlayerSave save, String itemId, num quantity) {
  final cleared = save.copyWith(
    inventory: save.inventory.where((stack) => stack.itemId != itemId).toList(),
  );
  return quantity > 0 ? addItemToInventory(cleared, itemId, quantity) : cleared;
}

PlayerSave _activeGettingStarted(GameDatabase db) {
  final save = createNewSave(db, 0);
  return save.copyWith(
    quests: [
      ...save.quests.where((row) => row.questId != _quest),
      const QuestProgress(questId: _quest, status: 'active', progress: 0, counters: {}),
    ],
  );
}

int _index(GameDatabase db, PlayerSave save) =>
    getCurrentStepIndex(db, save, getQuest(db, _quest)!);

/// Fennel's Show choices: the raw potatoes (QSTP-0014) and the baked ones (QSTP-0016).
PlayerSave _showFennel(GameDatabase db, PlayerSave save, {required bool cooked}) {
  final shown = cooked
      ? chooseDialogue(db, save, 'DLG-0005', 'DNODE-0007', 'DCH-0009')
      : chooseDialogue(db, save, 'DLG-0003', 'DNODE-0004', 'DCH-0005');
  expect(shown.ok, isTrue, reason: shown.reason);
  return shown.save;
}

/// Hold 5 raw, show Fennel, visit the kitchen, cook all 5.
PlayerSave _throughCooking(GameDatabase db) {
  var save = _setCount(_activeGettingStarted(db), _raw, 5);
  save = applyQuestStepUnlocks(db, save);
  expect(_index(db, save), 1);
  save = applyQuestTalkProgress(db, save, _fennel);
  expect(_index(db, save), 1);
  save = _showFennel(db, save, cooked: false);
  expect(_index(db, save), 2);
  save = applyQuestVisitProgress(db, save, _kitchen);
  for (var cooked = 1; cooked <= 5; cooked++) {
    save = _setCount(save, _raw, 5 - cooked);
    save = _setCount(save, _cooked, cooked);
    save = applyQuestProcessProgress(db, save, _recipe);
    expect(_index(db, save), cooked < 5 ? 2 : 3, reason: 'after cooking $cooked');
  }
  return save;
}

void main() {
  late GameDatabase db;
  setUpAll(() => db = assertGameDatabaseShape(contentDatabaseJson()));

  test('hold, talk, cook 5 reaches step 3 then 4 without regressing', () {
    var save = _throughCooking(db);
    final counters = getQuestProgress(save, _quest).counters!;
    expect(counters['step:QSTP-0013'], 1);
    expect(counters['step:QSTP-0014'], 1);
    expect(counters['step:QSTP-0015'], 1);
    expect(inventoryCount(save, _raw), 0);
    save = _showFennel(db, save, cooked: true);
    expect(_index(db, save), 4);
    expect(inventoryCount(save, _cooked), 5);
  });

  test('selling the cooked potatoes at step 5 does not regress', () {
    var save = _showFennel(db, _throughCooking(db), cooked: true);
    expect(_index(db, save), 4);
    save = applyQuestStepUnlocks(db, _setCount(save, _cooked, 0));
    expect(_index(db, save), 4);
  });

  test('steps only latch in order', () {
    // Cooked potatoes in the bag do not latch step 4 while step 1 is open.
    var save = _setCount(_activeGettingStarted(db), _cooked, 5);
    save = applyQuestStepUnlocks(db, save);
    expect(getQuestProgress(save, _quest).counters?['step:QSTP-0016'], isNull);
    expect(_index(db, save), 0);
  });

  test('the old panel talk does not mark QSTP-0014 or QSTP-0016 done', () {
    void showDone(PlayerSave save, String stepId) {
      final step = getQuestStep(db, _quest, stepId);
      expect(isStepLatched(save, _quest, stepId), isFalse);
      expect(isStepComplete(db, save, _quest, step?.notes ?? '', stepId), isFalse);
      expect(getQuestProgress(save, _quest).counters?['step:$stepId'], isNull);
    }

    var save = applyQuestStepUnlocks(db, _setCount(_activeGettingStarted(db), _raw, 5));
    expect(_index(db, save), 1);
    save = applyQuestTalkProgress(db, save, _fennel);
    expect(_index(db, save), 1);
    showDone(save, 'QSTP-0014');
    showDone(save, 'QSTP-0016');

    final panel = talkWithQuestNpc(
      db,
      applyQuestStepUnlocks(db, _setCount(_activeGettingStarted(db), _raw, 5)),
      _fennel,
    );
    expect(panel.ok, isTrue);
    showDone(panel.save!, 'QSTP-0014');
    showDone(panel.save!, 'QSTP-0016');
    expect(_index(db, panel.save!), 1);
  });

  test('unlocks from a latched step stay applied', () {
    final raw = Map<String, Object?>.from(contentDatabaseJson()! as Map);
    final steps = (raw['QuestSteps']! as List).map((row) {
      final step = Map<String, Object?>.from(row as Map);
      if (step['Step ID'] == 'QSTP-0013')
        step['Notes'] = 'Hold: $_raw x5; UnlockLocation: LOC-9999';
      return step;
    }).toList();
    raw['QuestSteps'] = steps;
    final patched = assertGameDatabaseShape(raw);

    var save = applyQuestStepUnlocks(patched, _setCount(_activeGettingStarted(patched), _raw, 5));
    expect(save.unlockedLocationIds, contains('LOC-9999'));
    save = _setCount(save, _raw, 0).copyWith(
      unlockedLocationIds: save.unlockedLocationIds.where((id) => id != 'LOC-9999').toList(),
    );
    save = applyQuestStepUnlocks(patched, save);
    expect(save.unlockedLocationIds, contains('LOC-9999'));
    expect(getCurrentStepIndex(patched, save, getQuest(patched, _quest)!), 1);
  });
}
