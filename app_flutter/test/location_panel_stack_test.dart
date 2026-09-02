import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/location_view.dart';
import 'package:ik_content/ik_content.dart';

void main() {
  const npcA = NpcOpen(
    NpcRow({'NPC ID': 'NPC-0001', 'Display Name': 'King', 'Location ID': 'LOC-0016'}),
  );
  const npcB = NpcOpen(
    NpcRow({'NPC ID': 'NPC-0002', 'Display Name': 'Rose', 'Location ID': 'LOC-0023'}),
  );

  test('opening a shop from an NPC keeps the NPC under the new shop', () {
    final stacked = pushLocationPanel(
      const [npcA, ShopOpen('SHP-0001')],
      const ShopOpen('SHP-0003'),
      nest: true,
    );
    expect(stacked, hasLength(2));
    expect(stacked.first, same(npcA));
    expect((stacked.last as ShopOpen).shopId, 'SHP-0003');
  });

  test('opening a shop from the band replaces the last shop', () {
    final stacked = pushLocationPanel(const [ShopOpen('SHP-0001')], const ShopOpen('SHP-0002'));
    expect(stacked, hasLength(1));
    expect((stacked.single as ShopOpen).shopId, 'SHP-0002');
  });

  test('talking to a new NPC closes the previous NPC', () {
    final stacked = pushLocationPanel(const [npcA], npcB);
    expect(stacked, hasLength(1));
    expect((stacked.single as NpcOpen).npc.npcId, 'NPC-0002');
  });

  test('opening arena from the band closes the NPC underneath', () {
    final stacked = pushLocationPanel(const [npcA], const ArenaOpen());
    expect(stacked, hasLength(1));
    expect(stacked.single, isA<ArenaOpen>());
  });

  test('opening the bank from the guild hall keeps the hall underneath', () {
    final stacked = pushLocationPanel(const [GuildHallOpen()], const BankOpen(), nest: true);
    expect(stacked, hasLength(2));
    expect(stacked.first, isA<GuildHallOpen>());
    expect(stacked.last, isA<BankOpen>());
  });
}
