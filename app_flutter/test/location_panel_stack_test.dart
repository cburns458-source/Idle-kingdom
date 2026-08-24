import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/location_view.dart';
import 'package:ik_content/ik_content.dart';

void main() {
  test('opening a shop replaces the previous shop and keeps the NPC under it', () {
    const npc = NpcOpen(
      NpcRow({'NPC ID': 'NPC-0001', 'Display Name': 'King', 'Location ID': 'LOC-0016'}),
    );
    final stacked = pushLocationPanel(const [
      npc,
      ShopOpen('SHP-0001'),
    ], const ShopOpen('SHP-0003'));
    expect(stacked, hasLength(2));
    expect(stacked.first, same(npc));
    expect((stacked.last as ShopOpen).shopId, 'SHP-0003');
  });

  test('opening a shop with no NPC just replaces the last shop', () {
    final stacked = pushLocationPanel(const [ShopOpen('SHP-0001')], const ShopOpen('SHP-0002'));
    expect(stacked, hasLength(1));
    expect((stacked.single as ShopOpen).shopId, 'SHP-0002');
  });
}
