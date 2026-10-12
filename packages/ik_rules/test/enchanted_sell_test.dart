import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  const sword = 'ITEM-0130';
  const enchantmentId = 'ENCH-0003';

  num baseOf(String itemId) {
    final item = db.items.firstWhere((row) => row.raw['Item ID'] == itemId);
    return item.raw['Base Sell Value'] as num;
  }

  ShopRow shop(String id) => db.shops.firstWhere((row) => row.raw['Shop ID'] == id);

  test('Wizard shop pays 2× for enchanted gear and refuses plain gear', () {
    final wizard = shop('SHP-0003');
    final base = baseOf(sword);
    expect(playerSellPrice(db, wizard, sword), isNull);
    expect(playerSellPrice(db, wizard, sword, enchanted: true), base * 2);
  });

  test('the three general merchants pay Base Sell Value for enchanted gear', () {
    final base = baseOf(sword);
    for (final id in <String>['SHP-0001', 'SHP-0004', 'SHP-0005']) {
      expect(playerSellPrice(db, shop(id), sword, enchanted: true), base);
    }
  });

  test('the Armory refuses enchanted gear at the counter', () {
    expect(playerSellPrice(db, shop('SHP-0007'), sword, enchanted: true), isNull);
    final save = createNewSave(db, 0).copyWith(
      currentLocationId: 'LOC-0032',
      gold: 0,
      inventory: const <InventoryStack>[
        InventoryStack(itemId: sword, quantity: 1, enchantmentId: enchantmentId),
      ],
    );
    final result = confirmShopOffer(
      db,
      save,
      'SHP-0007',
      const ShopOffer(sells: <ShopOfferLine>[ShopOfferLine(itemId: sword, quantity: 1)]),
      nowMs: 0,
    );
    expect(result.ok, isFalse);
  });

  test('bag sell pays Wizard 2×, general 1×, and field half for enchanted gear', () {
    final base = baseOf(sword);
    final enchanted = const InventoryStack(
      itemId: sword,
      quantity: 1,
      enchantmentId: enchantmentId,
    );

    final atWizard = createNewSave(
      db,
      0,
    ).copyWith(currentLocationId: 'LOC-0007', gold: 0, inventory: <InventoryStack>[enchanted]);
    final wizardSale = sellInventoryIndexes(db, atWizard, const <num>[0]);
    expect(wizardSale.ok, isTrue);
    expect(wizardSale.goldEarned, base * 2);

    final atGeneral = createNewSave(
      db,
      0,
    ).copyWith(currentLocationId: 'LOC-0024', gold: 0, inventory: <InventoryStack>[enchanted]);
    final generalSale = sellInventoryIndexes(db, atGeneral, const <num>[0]);
    expect(generalSale.ok, isTrue);
    expect(generalSale.goldEarned, base);

    final inField = createNewSave(
      db,
      0,
    ).copyWith(currentLocationId: 'LOC-0009', gold: 0, inventory: <InventoryStack>[enchanted]);
    final fieldSale = sellInventoryIndexes(db, inField, const <num>[0]);
    expect(fieldSale.ok, isTrue);
    expect(fieldSale.goldEarned, fieldSellPrice(db, sword));
  });
}
