import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late InventorySorter sorter;

  setUpAll(() {
    sorter = InventorySorter(assertGameDatabaseShape(contentDatabaseJson()));
  });

  List<String> names(
    List<String> itemIds, [
    InventorySortMode mode = InventorySortMode.group,
    String query = '',
  ]) {
    final stacks = [for (final itemId in itemIds) InventoryStack(itemId: itemId, quantity: 1)];
    return [for (final index in sorter.displayIndexes(stacks, mode, query)) itemIds[index]];
  }

  test('pins favorites above every group', () {
    const stacks = [
      InventoryStack(itemId: 'ITEM-0003', quantity: 1),
      InventoryStack(itemId: 'ITEM-0128', quantity: 1, favorite: true),
      InventoryStack(itemId: 'ITEM-0074', quantity: 1),
    ];
    expect(
      [
        for (final index in sorter.displayIndexes(stacks, InventorySortMode.group))
          stacks[index].itemId,
      ],
      ['ITEM-0128', 'ITEM-0003', 'ITEM-0074'],
    );
    expect(
      [
        for (final index in sorter.displayIndexes(stacks, InventorySortMode.az))
          stacks[index].itemId,
      ],
      ['ITEM-0128', 'ITEM-0074', 'ITEM-0003'],
    );
  });

  test('keeps ores, bars, and swords in their skill groups', () {
    expect(sorter.groupOf('ITEM-0003'), groupMining);
    expect(sorter.groupOf('ITEM-0074'), groupMetallurgy);
    expect(sorter.groupOf('ITEM-0128'), groupSmithing);
    expect(names(['ITEM-0128', 'ITEM-0074', 'ITEM-0003']), ['ITEM-0003', 'ITEM-0074', 'ITEM-0128']);
  });

  test('places timber with logs and pickaxes with mining', () {
    expect(sorter.groupOf('ITEM-0015'), groupWoodcutting);
    expect(sorter.groupOf('ITEM-0214'), groupWoodcutting);
    expect(sorter.groupOf('ITEM-0102'), groupMining);
    expect(names(['ITEM-0214', 'ITEM-0015', 'ITEM-0102']), ['ITEM-0102', 'ITEM-0015', 'ITEM-0214']);
  });

  test('orders metal tiers and cook levels low to high', () {
    expect(names(['ITEM-0005', 'ITEM-0003', 'ITEM-0004']), ['ITEM-0003', 'ITEM-0004', 'ITEM-0005']);
    expect(sorter.groupOf('ITEM-0058'), groupCooking);
    expect(sorter.groupOf('ITEM-0061'), groupCooking);
    expect(names(['ITEM-0061', 'ITEM-0058']), ['ITEM-0058', 'ITEM-0061']);
  });

  test('places cooked food before raw fish', () {
    expect(sorter.groupOf('ITEM-0061'), groupCooking);
    expect(sorter.groupOf('ITEM-0049'), groupFishing);
    expect(names(['ITEM-0049', 'ITEM-0061']), ['ITEM-0061', 'ITEM-0049']);
  });

  test('puts hunting leftovers and crafting tablets in the intended groups', () {
    expect(sorter.groupOf('ITEM-0054'), groupHunting);
    expect(sorter.groupOf('ITEM-0025'), groupHarvesting);
    expect(sorter.groupOf('ITEM-0099'), groupArcana);
    expect(sorter.groupOf('ITEM-0083'), groupCrafting);
  });

  test('sorts A–Z by display name and filters Search by name only', () {
    const bag = ['ITEM-0128', 'ITEM-0003', 'ITEM-0074'];
    expect(names(bag, InventorySortMode.az), ['ITEM-0074', 'ITEM-0003', 'ITEM-0128']);
    expect(names(bag, InventorySortMode.search, 'copper'), ['ITEM-0003', 'ITEM-0074']);
    expect(names(bag, InventorySortMode.search, 'ITEM-0003'), isEmpty);
  });
}
