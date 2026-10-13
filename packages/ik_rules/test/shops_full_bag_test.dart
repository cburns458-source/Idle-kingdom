import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;
  const now = 1767225600000;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  test('refuses a new item with no_room and leaves gold untouched', () {
    const gold = 10000;
    final save = createNewSave(db, now).copyWith(
      currentLocationId: 'LOC-0024',
      gold: gold,
      inventory: [
        for (var index = 0; index < inventorySlotLimit; index += 1)
          InventoryStack(itemId: 'FILL-$index', quantity: 1),
      ],
    );
    final result = confirmShopOffer(
      db,
      save,
      'SHP-0001',
      const ShopOffer(buys: [ShopOfferLine(itemId: 'ITEM-0102', quantity: 1)]),
      nowMs: now,
    );
    expect(result.ok, isFalse);
    expect(result.code, 'no_room');
    expect(result.reason, 'No room in your bag. Free 1 slot and try again.');
    expect(result.noRoom?.toJson(), {'slotsNeeded': 1, 'slotsFree': 0});
    expect(save.gold, gold);
    expect(save.inventory, hasLength(inventorySlotLimit));
  });

  test('refuses a 3-item basket when only one slot is free', () {
    const gold = 10000;
    final save = createNewSave(db, now).copyWith(
      currentLocationId: 'LOC-0024',
      gold: gold,
      inventory: [
        for (var index = 0; index < inventorySlotLimit - 1; index += 1)
          InventoryStack(itemId: 'FILL-$index', quantity: 1),
      ],
    );
    final result = confirmShopOffer(
      db,
      save,
      'SHP-0001',
      const ShopOffer(
        buys: [
          ShopOfferLine(itemId: 'ITEM-0102', quantity: 1),
          ShopOfferLine(itemId: 'ITEM-0108', quantity: 1),
          ShopOfferLine(itemId: 'ITEM-0100', quantity: 1),
        ],
      ),
      nowMs: now,
    );
    expect(result.ok, isFalse);
    expect(result.code, 'no_room');
    expect(result.noRoom?.toJson(), {'slotsNeeded': 3, 'slotsFree': 1});
    expect(save.gold, gold);
    expect(save.inventory, hasLength(inventorySlotLimit - 1));
  });

  test('still buys onto an existing stack when the bag is full', () {
    final save = createNewSave(db, now).copyWith(
      currentLocationId: 'LOC-0024',
      gold: 10000,
      inventory: [
        const InventoryStack(itemId: 'ITEM-0102', quantity: 1),
        for (var index = 0; index < inventorySlotLimit - 1; index += 1)
          InventoryStack(itemId: 'FILL-$index', quantity: 1),
      ],
    );
    final result = confirmShopOffer(
      db,
      save,
      'SHP-0001',
      const ShopOffer(buys: [ShopOfferLine(itemId: 'ITEM-0102', quantity: 1)]),
      nowMs: now,
    );
    expect(result.ok, isTrue);
    expect(result.save!.inventory.where((stack) => stack.itemId == 'ITEM-0102').first.quantity, 2);
    expect(result.save!.gold, lessThan(save.gold));
  });
}
