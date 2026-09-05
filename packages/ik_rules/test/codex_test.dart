import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;
  late CodexIndex codex;
  late InventorySorter sorter;

  setUpAll(() {
    db = filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));
    sorter = InventorySorter(db);
    codex = CodexIndex(db);
  });

  test('lists every launch item and enemy', () {
    expect(codex.items.map((row) => row.itemId).toSet(), db.items.map((row) => row.itemId).toSet());
    expect(
      codex.enemies.map((row) => row.enemyId).toSet(),
      db.enemies.map((row) => row.enemyId).toSet(),
    );
    expect(codex.item('ITEM-0209')?.displayName, 'Ancient Alloy');
    expect(codex.item('ITEM-0276')?.displayName, 'Ancient Alloy Sword');
  });

  test('uses the same inventory groups as the bag', () {
    for (final item in db.items) {
      expect(codex.item(item.itemId)!.group, sorter.groupOf(item.itemId), reason: item.displayName);
      expect(codex.item(item.itemId)!.groupLabel, inventoryGroupLabel(sorter.groupOf(item.itemId)));
    }
    expect(
      codex.itemsMatching(group: groupMining).every((row) => row.group == groupMining),
      isTrue,
    );
    expect(codex.itemsMatching(query: 'copper').map((row) => row.itemId), contains('ITEM-0003'));
  });

  test('links copper ore to its mine action', () {
    final ore = codex.item('ITEM-0003')!;
    expect(ore.obtainedFrom.any((row) => row.actionId == 'ACN-0018'), isTrue);
    final mine = ore.obtainedFrom.firstWhere((row) => row.actionId == 'ACN-0018');
    expect(mine.title.toLowerCase(), contains('copper'));
    expect(mine.locations.map((row) => row.displayName), isNotEmpty);
  });

  test('shows recipes that make and use items', () {
    final potato = codex.item('ITEM-0058')!;
    expect(potato.craftedBy, isNotEmpty);
    expect(potato.craftedBy.first.isProject, isFalse);
    expect(potato.craftedBy.first.ingredients.map((row) => row.itemId), contains('ITEM-0025'));

    final raw = codex.item('ITEM-0025')!;
    expect(raw.usedIn.any((row) => row.output.itemId == 'ITEM-0058'), isTrue);
  });

  test('shows projects that make and use items', () {
    final sword = codex.item('ITEM-0128')!;
    expect(sword.craftedBy, isNotEmpty);
    expect(sword.craftedBy.first.isProject, isTrue);
    expect(sword.craftedBy.first.id, 'PRJ-0003');

    final leather = codex.item('ITEM-0045')!;
    expect(leather.usedIn.any((row) => row.output.itemId == 'ITEM-0308'), isTrue);
  });

  test('lists cow drops and skeleton locations', () {
    final beef = codex.item('ITEM-0054')!;
    expect(beef.obtainedFrom.any((row) => row.enemyId == 'ENM-0001'), isTrue);

    final cow = codex.enemy('ENM-0001')!;
    expect(cow.drops.map((row) => row.itemId), containsAll(['ITEM-0054', 'ITEM-0045']));
    expect(cow.drops.where((row) => row.itemId == 'ITEM-0054').length, 1);
    expect(cow.locations.map((row) => row.displayName), contains('The Farm'));

    final skeleton = codex.enemy('ENM-0008')!;
    expect(
      skeleton.locations.map((row) => row.displayName),
      containsAll(['Wizard\'s Tower', 'Castle Crypt']),
    );
  });
}
