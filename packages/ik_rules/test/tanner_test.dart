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

  test('quotes 2 gold per leather and the listed hide yields', () {
    final tanner = db.npcs.firstWhere((row) => row.npcId == 'NPC-0018');
    final save = createNewSave(db, 0).copyWith(
      currentLocationId: 'LOC-0025',
      gold: 100,
      inventory: const [
        InventoryStack(itemId: 'ITEM-0378', quantity: 2),
        InventoryStack(itemId: 'ITEM-0196', quantity: 1),
      ],
    );
    final offer = tannerOffer(db, save);
    expect(offer.feeEach, 2);
    expect(offer.hides.map((row) => row.itemId).toList()..sort(), ['ITEM-0196', 'ITEM-0378']);
    final quote = quoteTannerJob(db, save, {'ITEM-0378': 2, 'ITEM-0196': 1});
    expect(quote.hideCount, 3);
    expect(quote.leather, 8);
    expect(quote.gold, 16);

    final done = confirmTannerJob(db, save, tanner, {'ITEM-0378': 2, 'ITEM-0196': 1});
    expect(done.ok, isTrue);
    expect(done.save!.gold, 84);
    expect(done.save!.inventory.where((stack) => stack.itemId == 'ITEM-0045').single.quantity, 8);
    expect(done.save!.inventory.any((stack) => stack.itemId == 'ITEM-0378'), isFalse);
  });

  test('refuses when the player cannot pay', () {
    final tanner = db.npcs.firstWhere((row) => row.npcId == 'NPC-0018');
    final save = createNewSave(db, 0).copyWith(
      currentLocationId: 'LOC-0025',
      gold: 3,
      inventory: const [InventoryStack(itemId: 'ITEM-0195', quantity: 1)],
    );
    final quote = quoteTannerJob(db, save, {'ITEM-0195': 1});
    expect(quote.leather, 2);
    expect(quote.gold, 4);
    final refused = confirmTannerJob(db, save, tanner, {'ITEM-0195': 1});
    expect(refused.ok, isFalse);
    expect(refused.reason, 'Need 4 gold.');
  });

  test('stands at both crafting workshops', () {
    expect(db.npcs.where((row) => row.role == 'Tanner').map((row) => row.locationId), [
      'LOC-0025',
      'LOC-0030',
    ]);
    expect(db.npcs.where((row) => row.role == 'Tanner').map((row) => row.displayName), [
      'Tanner',
      'Tanner',
    ]);
  });

  test('counts bank hides and spends the bag first', () {
    final tanner = db.npcs.firstWhere((row) => row.npcId == 'NPC-0018');
    final save = createNewSave(db, 0).copyWith(
      currentLocationId: 'LOC-0025',
      gold: 20,
      inventory: const [InventoryStack(itemId: 'ITEM-0378', quantity: 1)],
      bank: const [InventoryStack(itemId: 'ITEM-0378', quantity: 1)],
    );
    expect(tannerOffer(db, save).hides.single.owned, 2);
    final done = confirmTannerJob(db, save, tanner, {'ITEM-0378': 2});
    expect(done.ok, isTrue);
    expect(done.save!.gold, 8);
    expect(done.save!.inventory.where((stack) => stack.itemId == 'ITEM-0045').single.quantity, 6);
    expect(done.save!.inventory.any((stack) => stack.itemId == 'ITEM-0378'), isFalse);
    expect(done.save!.bank.any((stack) => stack.itemId == 'ITEM-0378'), isFalse);
  });

  test('stands at a future crafting workshop without a database NPC row', () {
    final raw = Map<String, Object?>.from(db.raw);
    raw['Facilities'] = [
      ...(raw['Facilities']! as List<Object?>),
      <String, Object?>{
        'Facility ID': 'FAC-9999',
        'Internal Key': 'outpost_crafting_workshop',
        'Display Name': 'Outpost Crafting Workshop',
        'Facility Type': 'Production Station',
        'Location ID': 'LOC-9999',
        'Skill ID': 'SKL-0009',
        'Status': 'Planned',
        'Release Phase': 'Launch',
      },
    ];
    final extra = GameDatabase(raw);
    expect(tannerNpcAtLocation(extra, 'LOC-9999')!.displayName, 'Tanner');
    expect(
      npcsAtLocation(extra, 'LOC-9999', 0).map((row) => row.npcId),
      contains('NPC-TANNER-LOC-9999'),
    );
  });
}
