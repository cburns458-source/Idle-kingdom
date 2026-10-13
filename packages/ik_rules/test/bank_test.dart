import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

LocationRow _loc(String id, [String? mapId]) {
  return LocationRow({'Location ID': id, 'Map ID': ?mapId});
}

void main() {
  test('Town Bank, Citadel Bank, and future *_bank locations have a bank', () {
    expect(locationHasBank(_loc('LOC-0034', 'MAP-0006')), isTrue);
    expect(locationHasBank(_loc('LOC-0035', 'MAP-0007')), isTrue);
    expect(locationHasBank(_loc('LOC-0002')), isFalse);
    expect(locationHasBank(_loc('LOC-0013')), isFalse);
    expect(locationHasBank(_loc('LOC-0027')), isFalse);
    expect(locationHasBank(_loc('LOC-0024', 'MAP-0006')), isFalse);
    expect(locationHasBank(_loc('LOC-0009', 'MAP-0001')), isFalse);
    expect(locationHasBank(null), isFalse);
    expect(
      locationHasBank(
        LocationRow({
          'Location ID': 'LOC-9999',
          'Internal Key': 'west_bank',
          'Display Name': 'West Bank',
        }),
      ),
      isTrue,
    );
  });

  test('prepared databases expose deposit-box thievery at every bank', () {
    final loaded = prepareDatabase(contentDatabaseJson());
    final depositActs = loaded.launch.activities.where((row) => row.poolId == depositBoxPoolId);
    final bankLocs = loaded.launch.locations.where(locationLooksLikeBank);
    for (final location in bankLocs) {
      expect(
        depositActs.any((row) => row.locationId == location.locationId),
        isTrue,
        reason: location.locationId,
      );
    }

    final withFuture = withBankDepositBoxActivities(
      GameDatabase({
        ...loaded.launch.raw,
        'Locations': [
          ...loaded.launch.locations.map((row) => row.raw),
          {
            'Location ID': 'LOC-9999',
            'Internal Key': 'west_bank',
            'Display Name': 'West Bank',
            'Map ID': 'MAP-0006',
            'Location Type': 'Settlement',
            'Status': 'Planned',
            'Release Phase': 'Launch',
          },
        ],
      }),
    );
    expect(
      withFuture.activities.any(
        (row) => row.poolId == depositBoxPoolId && row.locationId == 'LOC-9999',
      ),
      isTrue,
    );
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
    expect(gold.reason, 'Gold cannot be deposited.');

    final compost = depositToBank(
      createNewSave(db, 0).copyWith(
        inventory: const [InventoryStack(itemId: 'ITEM-0377', quantity: 4)],
        bank: const <InventoryStack>[],
      ),
      0,
      4,
    );
    expect(compost.ok, isTrue);
    expect(compost.save!.inventory, isEmpty);
    expect(compost.save!.bank.single.itemId, 'ITEM-0377');
    expect(compost.save!.bank.single.quantity, 4);

    final withdrawn = withdrawFromBank(save, 0, 2);
    expect(withdrawn.ok, isTrue);
    expect(withdrawn.save!.bank.single.quantity, 1);
    expect(withdrawn.save!.inventory.single.quantity, 4);
  });

  test('caps the chest at 168 slots, past the 84-slot bag', () {
    final db = databaseOf(loadParityFixtures('save/roundtrip').first);
    final blocked = depositToBank(
      createNewSave(db, 0).copyWith(
        inventory: const [InventoryStack(itemId: 'ITEM-0002', quantity: 1)],
        bank: [
          for (var index = 0; index < bankSlotLimit; index++)
            InventoryStack(itemId: 'ITEM-fake-$index', quantity: 1),
        ],
      ),
      0,
      1,
    );
    expect(blocked.ok, isFalse);
    expect(blocked.reason, 'Bank is full ($bankSlotLimit slots).');

    final accepted = depositToBank(
      createNewSave(db, 0).copyWith(
        inventory: const [InventoryStack(itemId: 'ITEM-0002', quantity: 1)],
        bank: [
          for (var index = 0; index < bankSlotLimit - 1; index++)
            InventoryStack(itemId: 'ITEM-fake-$index', quantity: 1),
        ],
      ),
      0,
      1,
    );
    expect(accepted.ok, isTrue);
    expect(accepted.save!.bank, hasLength(bankSlotLimit));
  });

  test('refuses a new-stack withdraw with no_room and leaves bag and bank unchanged', () {
    final db = databaseOf(loadParityFixtures('save/roundtrip').first);
    final save = createNewSave(db, 0).copyWith(
      inventory: [
        for (var index = 0; index < inventorySlotLimit; index += 1)
          InventoryStack(itemId: 'FILL-$index', quantity: 1),
      ],
      bank: const [InventoryStack(itemId: 'ITEM-0002', quantity: 3)],
    );
    final blocked = withdrawFromBank(save, 0, 1);
    expect(blocked.ok, isFalse);
    expect(blocked.code, 'no_room');
    expect(blocked.reason, 'No room in your bag. Free 1 slot and try again.');
    expect(blocked.noRoom?.toJson(), {'slotsNeeded': 1, 'slotsFree': 0});
    expect(save.inventory, hasLength(inventorySlotLimit));
    expect(save.bank.single.quantity, 3);
  });

  test('withdraws onto an existing stack when the bag is full', () {
    final db = databaseOf(loadParityFixtures('save/roundtrip').first);
    final save = createNewSave(db, 0).copyWith(
      inventory: [
        const InventoryStack(itemId: 'ITEM-0002', quantity: 2),
        for (var index = 0; index < inventorySlotLimit - 1; index += 1)
          InventoryStack(itemId: 'FILL-$index', quantity: 1),
      ],
      bank: const [InventoryStack(itemId: 'ITEM-0002', quantity: 4)],
    );
    final withdrawn = withdrawFromBank(save, 0, 2);
    expect(withdrawn.ok, isTrue);
    expect(
      withdrawn.save!.inventory.where((stack) => stack.itemId == 'ITEM-0002').first.quantity,
      4,
    );
    expect(withdrawn.save!.bank.single.quantity, 2);
  });
}
