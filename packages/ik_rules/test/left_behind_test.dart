import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));
  });

  PlayerSave fullBag(PlayerSave save) {
    return save.copyWith(
      inventory: [
        for (var index = 0; index < inventorySlotLimit; index++)
          InventoryStack(itemId: 'FILL-$index', quantity: 1),
      ],
    );
  }

  RandomFn seqRandom(List<num> values) {
    var i = 0;
    return () {
      final value = values[i < values.length ? i : values.length - 1];
      i += 1;
      return value.toDouble();
    };
  }

  test('reports gathering drops that do not fit and does not add them', () {
    final save = fullBag(createNewSave(db, 0).copyWith(inventory: const <InventoryStack>[]));
    final action = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0035');
    final rewarded = resolveActionRewards(db, save, action, seqRandom([0, 0, 1]));
    expect(rewarded.loot, isEmpty);
    expect(rewarded.leftBehind, hasLength(1));
    expect(rewarded.leftBehind.single.itemId, 'ITEM-0025');
    expect(rewarded.leftBehind.single.quantity, 1);
    expect(rewarded.save.inventory, hasLength(inventorySlotLimit));
    expect(rewarded.save.inventory.any((stack) => stack.itemId == 'ITEM-0025'), isFalse);
  });

  test('still grows an existing stack when the bag is full', () {
    final save = createNewSave(db, 0).copyWith(
      inventory: [
        const InventoryStack(itemId: 'ITEM-0025', quantity: 2),
        for (var index = 0; index < inventorySlotLimit - 1; index++)
          InventoryStack(itemId: 'FILL-$index', quantity: 1),
      ],
    );
    final action = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0035');
    final rewarded = resolveActionRewards(db, save, action, seqRandom([0, 0, 1]));
    expect(rewarded.leftBehind, isEmpty);
    expect(rewarded.loot, hasLength(1));
    expect(rewarded.loot.single.itemId, 'ITEM-0025');
    expect(rewarded.loot.single.quantity, 1);
    expect(rewarded.save.inventory.firstWhere((stack) => stack.itemId == 'ITEM-0025').quantity, 3);
  });

  test('threads left-behind through a completed gathering action', () {
    final save = fullBag(createNewSave(db, 0).copyWith(inventory: const <InventoryStack>[]));
    final action = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0035');
    final completed = completeGatheringAction(db, save, action, seqRandom([0, 0, 0, 1]), 0);
    expect(completed.result.loot, isEmpty);
    expect(completed.result.leftBehind, hasLength(1));
    expect(completed.result.leftBehind.single.itemId, 'ITEM-0025');
    expect(completed.save.inventory.any((stack) => stack.itemId == 'ITEM-0025'), isFalse);
  });

  test('reports combat drops that do not fit and does not add them', () {
    final save = fullBag(createNewSave(db, 0));
    final action = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0001');
    final enemy = db.enemies.firstWhere((row) => row.raw['Enemy ID'] == 'ENM-0001');
    final victory = applyCombatVictory(db, save, action, enemy, () => 0, 0);
    expect(victory.loot, isEmpty);
    expect(victory.leftBehind, hasLength(1));
    expect(victory.leftBehind.single.itemId, 'ITEM-0054');
    expect(victory.leftBehind.single.quantity, 1);
    expect(victory.save.inventory, hasLength(inventorySlotLimit));
    expect(victory.save.inventory.any((stack) => stack.itemId == 'ITEM-0054'), isFalse);
  });
}
