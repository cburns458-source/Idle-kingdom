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

  test('lists every launch item and enemy except pets, cosmetics, and quest items', () {
    final catalogIds = db.items
        .where((row) => includeInCodexCatalog(category: row.category, subtype: row.subtype))
        .map((row) => row.itemId)
        .toSet();
    expect(codex.items.map((row) => row.itemId).toSet(), catalogIds);
    expect(catalogIds.contains('ITEM-0299'), isFalse);
    expect(catalogIds.contains('ITEM-0296'), isFalse);
    expect(catalogIds.contains('ITEM-0320'), isFalse);
    expect(codex.item('ITEM-0299')?.displayName, 'Stolen Coin Purse');
    expect(codex.item('ITEM-0296')?.displayName, "Traveler's Tunic");
    expect(codex.item('ITEM-0320')?.displayName, 'Chick Pet');
    expect(
      codex.enemies.map((row) => row.enemyId).toSet(),
      db.enemies.map((row) => row.enemyId).toSet(),
    );
    expect(codex.item('ITEM-0209'), isNull);
    expect(codex.item('ITEM-0276')?.displayName, 'Ancient Alloy Sword');
    expect(codex.item('ITEM-0325'), isNull);
    expect(codex.item('ITEM-0346'), isNull);
    expect(codex.item('ITEM-0091'), isNull);
    expect(codex.item('ITEM-0096'), isNull);
    expect(codex.item('ITEM-0144'), isNull);
    expect(codex.item('ITEM-0286'), isNull);
    expect(db.items.firstWhere((row) => row.itemId == 'ITEM-0263').baseSellValue, 550);
    expect(db.items.firstWhere((row) => row.itemId == 'ITEM-0250').baseSellValue, 850);
    expect(db.items.firstWhere((row) => row.itemId == 'ITEM-0009').baseSellValue, 280);
    expect(db.items.firstWhere((row) => row.itemId == 'ITEM-0010').baseSellValue, 180);
    expect(
      db.items.firstWhere((row) => row.itemId == 'ITEM-0250').baseSellValue!,
      greaterThan(db.items.firstWhere((row) => row.itemId == 'ITEM-0263').baseSellValue!),
    );
  });

  test('lists gathering actions with primary, secondary, and gem tables', () {
    expect(codex.actions.any((row) => row.actionId == 'ACN-0018'), isTrue);
    expect(codex.actions.every((row) => row.category == 'Gathering'), isTrue);
    expect(codex.action('ACN-0001'), isNull);
    expect(codex.action('ACN-0036'), isNull);
    expect(codex.action('ACN-0166'), isNull);
    expect(codex.action('ACN-0167'), isNull);
    expect(codex.action('ACN-0168'), isNull);
    final mine = codex.action('ACN-0018')!;
    expect(mine.displayName.toLowerCase(), contains('copper'));
    expect(mine.tables.map((table) => table.label), ['Primary', 'Gems']);
    final ore = mine.tables.firstWhere((table) => table.label == 'Primary');
    expect(ore.dropChance, 47.5);
    expect(ore.drops.map((row) => row.displayName), contains('Copper Ore'));
    expect(ore.drops.firstWhere((row) => row.displayName == 'Copper Ore').dropRatePercent, 100);
    expect(ore.drops.map((row) => row.displayName), isNot(contains('Sapphire')));
    final gems = mine.tables.firstWhere((table) => table.label == 'Gems');
    expect(gems.dropChance, 0.5);
    expect(gems.drops.map((row) => row.displayName), contains('Sapphire'));
    expect(gems.drops.firstWhere((row) => row.displayName == 'Sapphire').dropRatePercent, 100);
    expect(codex.actionsMatching('mine copper').map((row) => row.actionId), contains('ACN-0018'));
  });

  test('merges per-location Chop vines actions into one codex row', () {
    final vineRows = codex.actions.where((row) => row.displayName == 'Chop vines').toList();
    expect(vineRows.map((row) => row.actionId), ['ACN-0179']);
    expect(codex.action('ACN-0231'), isNull);
    expect(codex.action('ACN-0232'), isNull);
    expect(codex.action('ACN-0233'), isNull);
    final places = vineRows.first.locations.map((row) => row.displayName).toList();
    expect(
      places,
      containsAll(['Forest Path', 'Small Clearing', 'Starlight Glade', 'Mirror Lake']),
    );
    expect(places.toSet().length, places.length);
  });

  test('keeps hunting primary and secondary tables separate', () {
    final hunt = codex.action('ACN-0014')!;
    expect(hunt.tables.map((table) => table.label), ['Primary', 'Secondary']);
    final primary = hunt.tables.first;
    expect(primary.dropChance, 42.5);
    expect(
      primary.drops.map((row) => row.displayName),
      containsAll(['Venison', 'Elk Hide', 'Elk Horns']),
    );
    expect(primary.drops.firstWhere((row) => row.displayName == 'Venison').dropRatePercent, 45);
    expect(primary.drops.firstWhere((row) => row.displayName == 'Elk Hide').dropRatePercent, 50);
    expect(primary.drops.firstWhere((row) => row.displayName == 'Elk Horns').dropRatePercent, 5);
    expect(primary.drops.map((row) => row.displayName), isNot(contains('Animal Tendons')));
    final secondary = hunt.tables.last;
    expect(secondary.dropChance, 5);
    expect(secondary.drops.map((row) => row.displayName), ['Animal Tendons']);
    expect(secondary.drops.single.dropRatePercent, 100);
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
    final iron = codex.item('ITEM-0128')!;
    expect(iron.craftedBy, isNotEmpty);
    expect(iron.craftedBy.every((row) => row.isProject), isTrue);
    expect(iron.craftedBy.first.id, 'PRJ-0003');

    final steel = codex.item('ITEM-0130')!;
    expect(steel.craftedBy, isNotEmpty);
    expect(steel.craftedBy.every((row) => row.isProject), isTrue);
    expect(steel.craftedBy.map((row) => row.id), contains('PRJ-0005'));
    expect(steel.craftedBy.every((row) => !row.id.startsWith('RCP-')), isTrue);

    final leather = codex.item('ITEM-0045')!;
    expect(leather.usedIn.any((row) => row.output.itemId == 'ITEM-0308'), isTrue);

    final hide = codex.item('ITEM-0197')!;
    expect(hide.usedIn.any((row) => row.id == 'PRJ-0049'), isTrue);
  });

  test('lists cow drops on the bestiary and as item obtain sources', () {
    final beef = codex.item('ITEM-0054')!;
    expect(beef.obtainedFrom.any((row) => row.enemyId == 'ENM-0001'), isTrue);
    expect(beef.obtainedFrom.where((row) => row.enemyId == 'ENM-0001').length, 1);
    expect(beef.obtainedFrom.any((row) => row.actionId == 'ACN-0001'), isFalse);
    expect(beef.obtainedFrom.any((row) => row.kind == CodexObtainKind.enemy), isTrue);

    final cow = codex.enemy('ENM-0001')!;
    expect(cow.drops.map((row) => row.itemId), containsAll(['ITEM-0054', 'ITEM-0378']));
    expect(cow.drops.map((row) => row.itemId), isNot(contains('ITEM-0045')));
    expect(cow.drops.where((row) => row.itemId == 'ITEM-0054').length, 1);
    expect(cow.drops.firstWhere((row) => row.itemId == 'ITEM-0054').dropRatePercent, isNotNull);
    expect(cow.locations.map((row) => row.displayName), contains('The Farm'));

    final skeleton = codex.enemy('ENM-0008')!;
    expect(
      skeleton.locations.map((row) => row.displayName),
      containsAll(['Wizard\'s Tower', 'Castle Crypt']),
    );
    expect(skeleton.drops.map((row) => row.itemId), containsAll(['ITEM-0129', 'ITEM-0012']));
    expect(skeleton.drops.map((row) => row.itemId), isNot(contains('ITEM-0286')));
    expect(skeleton.drops.firstWhere((row) => row.itemId == 'ITEM-0129').dropRatePercent, 80);
    expect(codex.enemy('ENM-0009')!.drops.map((row) => row.itemId), isNot(contains('ITEM-0286')));
    expect(codex.enemy('ENM-0006')!.drops.map((row) => row.itemId), isNot(contains('ITEM-0144')));

    final scout = codex.enemy('ENM-0003')!;
    expect(scout.combatLevel, 17);
    expect(scout.maximumHp, 462);
    expect(scout.minDamage, 33);
    expect(scout.maxDamage, 67);

    final rat = codex.enemy('ENM-0025')!;
    expect(rat.displayName, 'Giant Rat');
    expect(rat.combatLevel, 6);
    expect(rat.maximumHp, 150);
    expect(rat.drops, isEmpty);
    expect(rat.tables, isEmpty);
    expect(rat.locations.map((row) => row.displayName), contains('Deep Mines'));
  });

  test('lists secondary combat action loot as obtain sources that open the bestiary enemy', () {
    final staff = codex.item('ITEM-0122')!;
    final fight = staff.obtainedFrom.firstWhere((row) => row.enemyId == 'ENM-0004');
    expect(fight.kind, CodexObtainKind.enemy);
    expect(fight.actionId, isNull);
    expect(fight.title.toLowerCase(), contains('goblin'));
  });

  test('lists enemy primary and secondary drop tables on the bestiary', () {
    final cow = codex.enemy('ENM-0001')!;
    expect(cow.tables.map((table) => table.label), ['Primary']);
    expect(cow.tables.first.dropChance, 40);
    expect(
      cow.tables.first.drops.map((row) => row.itemId),
      containsAll(['ITEM-0054', 'ITEM-0378']),
    );

    final chief = codex.enemy('ENM-0004')!;
    expect(chief.tables.map((table) => table.label), ['Primary', 'Secondary']);
    expect(chief.tables.first.dropChance, 30);
    expect(chief.tables.first.drops.map((row) => row.itemId), isNot(contains('ITEM-0122')));
    final secondary = chief.tables.last;
    expect(secondary.dropChance, 50);
    expect(secondary.drops.map((row) => row.itemId), ['ITEM-0122']);
    expect(secondary.drops.single.dropRatePercent, 100);

    final pirate = codex.enemy('ENM-0005')!;
    expect(pirate.tables.map((table) => table.label), ['Primary', 'Secondary']);
    expect(pirate.tables.last.dropChance, 10);
    expect(pirate.tables.last.drops.map((row) => row.displayName), ['Pirate Insignia']);
    expect(pirate.tables.last.drops.single.dropRatePercent, 100);

    final dragon = codex.enemy('ENM-0006')!;
    expect(dragon.tables.map((table) => table.label), ['Primary']);
    expect(
      dragon.tables.expand((table) => table.drops.map((row) => row.itemId)),
      isNot(contains('COS-0012')),
    );
    expect(codex.enemy('ENM-0025')!.tables, isEmpty);
  });

  test('lists excavator pickaxe quest reward but not chef hat quest', () {
    final pick = codex.item('ITEM-0313')!;
    expect(
      pick.obtainedFrom.any(
        (row) => row.kind == CodexObtainKind.quest && row.questId == 'QST-0008',
      ),
      isTrue,
    );
    final hat = codex.item('ITEM-0165')!;
    expect(hat.obtainedFrom.any((row) => row.kind == CodexObtainKind.quest), isFalse);
  });

  test('hides golden spud sources and mystery harvest action', () {
    final spud = codex.item('ITEM-0026')!;
    expect(spud.obtainedFrom, isEmpty);
    expect(
      codex.items.any((row) => row.obtainedFrom.any((source) => source.actionId == 'ACN-0036')),
      isFalse,
    );
  });

  test('labels Mother Squid and Squidling XP as Fishing', () {
    final mother = codex.enemy('ENM-0023');
    final squidling = codex.enemy('ENM-0024');
    if (mother != null) {
      expect(mother.xpSkillLabel, 'Fishing');
    }
    if (squidling != null) {
      expect(squidling.xpSkillLabel, 'Fishing');
    }
  });

  test('lists Combat XP and Might/Vitality on every other enemy', () {
    final cow = codex.enemy('ENM-0001')!;
    expect(cow.xpSkillLabel, 'Combat');
    expect(cow.mightLevel, 2);
    expect(cow.vitalityLevel, 3);
    final harpy = codex.enemy('ENM-0030')!;
    expect(harpy.xpSkillLabel, 'Combat');
    expect(harpy.mightLevel, 70);
    expect(harpy.vitalityLevel, 40);
  });
}
