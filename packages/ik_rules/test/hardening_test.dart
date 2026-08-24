import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

GameDatabase _db() => filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));

GameDatabase _withCurrency(GameDatabase db, String itemId) {
  final raw = Map<String, Object?>.of(db.raw);
  raw['Config'] = [
    for (final row in db.config)
      if (row.raw['Key'] == 'currency_item_id')
        <String, Object?>{...row.raw, 'Value': itemId}
      else
        row.raw,
  ];
  return GameDatabase(raw);
}

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = _db();
  });

  test('unknown requirement types fail closed', () {
    final requirement = RequirementRow({
      'Requirement ID': 'REQ-BAD',
      'Requirement Type': 'Made Up',
      'Entity Type': 'Activity',
      'Entity ID': 'ACT-0001',
      'Reference ID / Value': 'x',
    });
    final result = evaluateRequirement(db, createNewSave(db, 0), requirement);
    expect(result.met, isFalse);
    expect(result.detail, 'Unknown requirement.');
  });

  test('Config currency items convert to gold even when they are not ITEM-0001', () {
    final alt = _withCurrency(db, 'ITEM-9999');
    final save = createNewSave(alt, 0);
    final next = addItemToInventory(save, 'ITEM-9999', 40, null, false, alt);
    expect(next.gold, save.gold + 40);
    expect(next.inventory.any((stack) => stack.itemId == 'ITEM-9999'), isFalse);
  });

  test('a due craft pauses when the bag cannot hold the output', () {
    var save = addItemToInventory(createNewSave(db, 0), 'ITEM-0025', 5);
    save = save.copyWith(currentLocationId: 'LOC-0023');
    final queued = beginProductionQueue(db, save, 'ACT-0017', 'RCP-0001', 2, 0);
    expect(queued.ok, isTrue);
    final filled = queued.save!.copyWith(
      inventory: [for (var i = 0; i < 180; i++) InventoryStack(itemId: 'FILL-$i', quantity: 1)],
    );
    expect(completeProductionCraft(db, filled, 1_000_000), isNull);

    final room = filled.copyWith(inventory: filled.inventory.take(179).toList());
    final cancelled = cancelProductionActivity(db, room);
    expect(
      cancelled.inventory
          .where((stack) => stack.itemId == 'ITEM-0025')
          .fold<num>(0, (sum, stack) => sum + stack.quantity),
      2,
    );
  });

  test('unattended production reports a full bag', () {
    var save = addItemToInventory(createNewSave(db, 0), 'ITEM-0025', 20);
    save = save.copyWith(currentLocationId: 'LOC-0023');
    final startedAt = DateTime.utc(2026).millisecondsSinceEpoch;
    final queued = beginProductionQueue(db, save, 'ACT-0017', 'RCP-0001', 2, startedAt);
    expect(queued.ok, isTrue);
    save = queued.save!.copyWith(
      unattendedProgressAt: isoFromMs(startedAt),
      inventory: [for (var i = 0; i < 180; i++) InventoryStack(itemId: 'FILL-$i', quantity: 1)],
    );
    final resolved = resolveUnattendedProgress(
      db,
      save,
      startedAt + queued.save!.actionDurationMs! + 100,
      () => 0,
    );
    expect(resolved.craftsCompleted, 0);
    expect(resolved.messages, contains('Crafting paused: inventory is full.'));
    expect(resolved.save.productionQuantityRemaining, 2);
  });
}
