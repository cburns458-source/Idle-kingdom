import 'dart:convert';
import 'dart:io';

import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

LocationRow _loc(String id, [String? mapId]) {
  return LocationRow({'Location ID': id, 'Map ID': ?mapId});
}

Object? _loadRawDatabase() {
  final file = File('../../content/data/game-database.json');
  return jsonDecode(file.readAsStringSync());
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
    final loaded = prepareDatabase(_loadRawDatabase());
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

    final withdrawn = withdrawFromBank(save, 0, 2);
    expect(withdrawn.ok, isTrue);
    expect(withdrawn.save!.bank.single.quantity, 1);
    expect(withdrawn.save!.inventory.single.quantity, 4);
  });
}
