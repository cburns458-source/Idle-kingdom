import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

GameDatabase _db() => filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = _db();
  });

  PlayerSave fresh() => createNewSave(db, 0);

  test('starts the citadel welcome dialogue', () {
    final started = startDialogue(db, fresh(), 'DLG-0001');
    expect(started.ok, isTrue, reason: started.reason);
    expect(started.view?.line, contains('Citadel'));
    expect(started.view?.choices, hasLength(2));
  });

  test('grants an item and completes a one-time dialogue', () {
    var save = fresh();
    final started = startDialogue(db, save, 'DLG-0001');
    expect(started.ok, isTrue);
    final yes = chooseDialogue(db, save, 'DLG-0001', started.view!.nodeId, 'DCH-0001');
    expect(yes.ok, isTrue, reason: yes.reason);
    expect(yes.message, contains('Potato'));
    expect(yes.view?.nodeId, 'DNODE-0002');
    save = yes.save;
    expect(save.inventory.any((stack) => stack.itemId == 'ITEM-0058'), isTrue);

    final thanks = chooseDialogue(db, save, 'DLG-0001', yes.view!.nodeId, 'DCH-0003');
    expect(thanks.ok, isTrue, reason: thanks.reason);
    expect(thanks.completed, isTrue);
    expect(thanks.save.completedDialogueIds, contains('DLG-0001'));

    final again = startDialogue(db, thanks.save, 'DLG-0001');
    expect(again.ok, isFalse);
  });

  test('declining still completes the one-time conversation', () {
    final started = startDialogue(db, fresh(), 'DLG-0001');
    final no = chooseDialogue(db, fresh(), 'DLG-0001', started.view!.nodeId, 'DCH-0002');
    expect(no.ok, isTrue, reason: no.reason);
    expect(no.completed, isTrue);
    expect(no.save.completedDialogueIds, contains('DLG-0001'));
  });

  test('refuses an invalid choice', () {
    final started = startDialogue(db, fresh(), 'DLG-0001');
    final bad = chooseDialogue(db, fresh(), 'DLG-0001', started.view!.nodeId, 'DCH-9999');
    expect(bad.ok, isFalse);
  });

  test('lists the dialogue for the citadel guide', () {
    final ids = dialoguesForNpc(db, fresh(), 'NPC-0013');
    expect(ids, contains('DLG-0001'));
  });
}
