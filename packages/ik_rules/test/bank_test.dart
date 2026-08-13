import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

LocationRow _loc(String id, [String? mapId]) {
  return LocationRow({'Location ID': id, if (mapId != null) 'Map ID': mapId});
}

void main() {
  test('Town, Castle, and Citadel have a bank', () {
    expect(locationHasBank(_loc('LOC-0002')), isTrue);
    expect(locationHasBank(_loc('LOC-0013')), isTrue);
    expect(locationHasBank(_loc('LOC-0027')), isTrue);
    expect(locationHasBank(_loc('LOC-0024', 'MAP-0006')), isTrue);
    expect(locationHasBank(_loc('LOC-0014', 'MAP-0003')), isTrue);
    expect(locationHasBank(_loc('LOC-0028', 'MAP-0007')), isTrue);
    expect(locationHasBank(_loc('LOC-0009', 'MAP-0001')), isFalse);
    expect(locationHasBank(null), isFalse);
  });

  test('deposits, withdraws, and refuses gold', () {
    final db = databaseOf(loadParityFixtures('save/roundtrip').first);
    var save = createNewSave(db, 0).copyWith(
      inventory: const [InventoryStack(itemId: 'ITEM-0002', quantity: 5)],
      bank: const <InventoryStack>[],
    );

    final deposited = depositToBank(save, 0, 3);
    expect(deposited.ok, isTrue);
    save = deposited.save!;
    expect(save.inventory.single.quantity, 2);
    expect(save.bank.single.quantity, 3);

    final gold = depositToBank(
      save.copyWith(inventory: const [InventoryStack(itemId: 'ITEM-0001', quantity: 10)]),
      0,
      10,
    );
    expect(gold.ok, isFalse);
    expect(gold.reason, 'Gold stays on you.');

    final withdrawn = withdrawFromBank(save, 0, 2);
    expect(withdrawn.ok, isTrue);
    expect(withdrawn.save!.bank.single.quantity, 1);
    expect(withdrawn.save!.inventory.single.quantity, 4);
  });
}
