import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  test('counts an enchanted grant as a new slot even when a plain stack is present', () {
    final db = databaseOf(loadParityFixtures('save/roundtrip').first);
    final save = createNewSave(db, 0).copyWith(
      inventory: [
        const InventoryStack(itemId: 'ITEM-0100', quantity: 1),
        for (var index = 0; index < inventorySlotLimit - 1; index += 1)
          InventoryStack(itemId: 'FILL-$index', quantity: 1),
      ],
    );
    expect(noRoomFor(save, [const ItemGrant(itemId: 'ITEM-0100', quantity: 1)]), isNull);
    expect(
      noRoomFor(save, [
        const ItemGrant(itemId: 'ITEM-0100', quantity: 1, enchantmentId: 'ENCH-0001'),
      ])?.toJson(),
      {'slotsNeeded': 1, 'slotsFree': 0},
    );
  });

  test('returns stack_full with no slot count when only a capped stack blocks the grant', () {
    final db = databaseOf(loadParityFixtures('save/roundtrip').first);
    final save = createNewSave(db, 0).copyWith(
      inventory: const [InventoryStack(itemId: 'ITEM-0002', quantity: inventoryStackMax)],
    );
    final blocked = noRoomFor(save, [const ItemGrant(itemId: 'ITEM-0002', quantity: 1)]);
    expect(blocked?.toJson(), {'reason': 'stack_full'});
    expect(blocked?.slotsNeeded, isNull);
    expect(blocked?.slotsFree, isNull);
    expect(noRoomReason(blocked!), 'That stack cannot hold more of this item.');
  });

  test('still reports slot counts when the bag is also full', () {
    final db = databaseOf(loadParityFixtures('save/roundtrip').first);
    final save = createNewSave(db, 0).copyWith(
      inventory: [
        const InventoryStack(itemId: 'ITEM-0002', quantity: inventoryStackMax),
        for (var index = 0; index < inventorySlotLimit - 1; index += 1)
          InventoryStack(itemId: 'FILL-$index', quantity: 1),
      ],
    );
    expect(noRoomFor(save, [const ItemGrant(itemId: 'ITEM-0002', quantity: 1)])?.toJson(), {
      'slotsNeeded': 1,
      'slotsFree': 0,
    });
  });
}
