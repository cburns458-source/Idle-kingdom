import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

GameDatabase _db() => assertGameDatabaseShape(contentDatabaseJson());

void main() {
  final db = _db();
  final nowMs = DateTime.utc(2026, 8, 13, 18).millisecondsSinceEpoch;

  test('ranked win grants exactly 25 points and 0 gold', () {
    final save = createNewSave(db, nowMs);
    final applied = applyRankedPvpResult(save, true, nowMs);
    expect(applied.goldGained, 0);
    expect(applied.pointsGained, rankedPvpWinPoints);
    expect(applied.pointsGained, 25);
    expect(applied.save.gold, save.gold);
    expect(plazaPointsOf(applied.save), 25);
  });

  test('bounty points round down', () {
    final save = createNewSave(db, nowMs);
    const bounty = BountyDefinition(
      id: 'BNT-TEST-FRACTION',
      title: 'Fraction',
      description: 'Round down.',
      kind: 'defeat',
      targetId: 'ENM-0001',
      amount: 1,
      rewardGold: 40.9,
      firstPlaceBonusGold: 0.8,
    );
    expect(bountyPointsFor(bounty, true), 41);
    expect(bountyPointsFor(bounty, false), 40);
    final first = applyBountyReward(save, bounty, true);
    expect(first.goldGained, 0);
    expect(first.pointsGained, 41);
    expect(plazaPointsOf(first.save), 41);
    expect(first.save.gold, save.gold);
  });

  test('shop purchase with insufficient points is refused and nothing deducted', () {
    final save = createNewSave(
      db,
      nowMs,
    ).copyWith(currentLocationId: citadelPlazaId, plazaPoints: 209);
    final result = purchasePlazaShopItem(db, save, hearthguardCuirassId, 1);
    expect(result.ok, isFalse);
    expect(result.reason, plazaShopInsufficientPoints);
    expect(plazaPointsOf(save), 209);
    expect(save.inventory.any((stack) => stack.itemId == hearthguardCuirassId), isFalse);
  });

  test('client-supplied amounts are ignored', () {
    final save = createNewSave(
      db,
      nowMs,
    ).copyWith(currentLocationId: citadelPlazaId, plazaPoints: 210);
    final bought = purchasePlazaShopItem(db, save, hearthguardCuirassId, 1);
    expect(bought.ok, isTrue);
    expect(bought.pointsSpent, 210);
    expect(bought.plazaPoints, 0);
  });

  test('refuses gold shop_confirm for the Hearthguard shop', () {
    final save = createNewSave(db, nowMs).copyWith(currentLocationId: citadelPlazaId, gold: 10000);
    final result = confirmShopOffer(
      db,
      save,
      plazaShopId,
      const ShopOffer(
        buys: <ShopOfferLine>[ShopOfferLine(itemId: hearthguardCuirassId, quantity: 1)],
      ),
      nowMs: nowMs,
    );
    expect(result.ok, isFalse);
    expect(result.reason, 'Buy this with plaza points.');
    expect(save.gold, 10000);
    expect(save.inventory.any((stack) => stack.itemId == hearthguardCuirassId), isFalse);
  });

  test('prints the Hearthguard set bonus only at 5/5', () {
    final save = createNewSave(db, nowMs);
    expect(hearthguardSetBonusText(save), isNull);
    final worn = save.copyWith(
      equipment: EquipmentLoadout(
        slots: <String, EquippedStack?>{
          ...save.equipment.slots,
          'SLOT-0003': const EquippedStack(itemId: hearthguardHelmId, quantity: 1),
          'SLOT-0004': const EquippedStack(itemId: hearthguardCuirassId, quantity: 1),
          'SLOT-0005': const EquippedStack(itemId: hearthguardGreavesId, quantity: 1),
          'SLOT-0007': const EquippedStack(itemId: hearthguardGauntletsId, quantity: 1),
          'SLOT-0006': const EquippedStack(itemId: hearthguardBootsId, quantity: 1),
        },
      ),
    );
    expect(hearthguardSetBonusText(worn), hearthguardSetBonusTextExact);
    expect(hearthguardSetBonusTextExact, 'Hearthguard (5/5): +10% max HP.');
  });
}
