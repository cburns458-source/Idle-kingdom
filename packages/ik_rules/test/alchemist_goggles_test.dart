import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

/// Parity with the goggles cases in src/game/shops/shops.test.ts and
/// src/game/equipment/specialist.test.ts.
void main() {
  late GameDatabase db;
  const now = 1788350400000; // 2026-09-02T12:00:00.000Z
  const dayMs = 24 * 60 * 60 * 1000;

  setUpAll(() {
    db = filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));
  });

  PlayerSave atAlchemy(num level) {
    final save = createNewSave(db, now);
    return addItemToInventory(
      save.copyWith(
        skills: [
          for (final skill in save.skills)
            if (skill.skillId == 'SKL-0010')
              SkillProgress(skillId: skill.skillId, level: level, xp: skill.xp)
            else
              skill,
        ],
      ),
      alchemistGogglesItemId,
      1,
    );
  }

  test('requires Alchemy 30 to wear the Alchemist Goggles', () {
    final row = db.equipment.singleWhere((entry) => entry.equipmentId == 'EQP-0196');
    expect(row.itemId, alchemistGogglesItemId);
    expect(row.requiredSkillId, 'SKL-0010');
    expect(row.requiredLevel, 30);

    final tooLow = equipItemFromInventory(db, atAlchemy(29), alchemistGogglesItemId);
    expect(tooLow.ok, isFalse);
    expect(tooLow.reason, 'Requires Alchemy level 30');

    final enough = equipItemFromInventory(db, atAlchemy(30), alchemistGogglesItemId);
    expect(enough.ok, isTrue);
    expect(enough.save!.equipment.slots['SLOT-0003']?.itemId, alchemistGogglesItemId);
  });

  test('sells Alchemist Goggles at the Apothecary for 138 gold, one per day', () {
    final shop = getShop(db, 'SHP-0010')!;
    final entry = shopStockEntries(shop).singleWhere((row) => row.itemId == alchemistGogglesItemId);
    expect(entry.slot, 6);
    expect(entry.dailyLimit, 1);
    expect(shopDailyLimit(shop, alchemistGogglesItemId), 1);
    expect(playerBuyPrice(db, shop, alchemistGogglesItemId), 138);
    expect(playerSellPrice(db, shop, alchemistGogglesItemId), 69);

    PlayerSave shopper() =>
        createNewSave(db, now).copyWith(currentLocationId: shop.locationId, gold: 1000);
    const one = ShopOffer(
      buys: <ShopOfferLine>[ShopOfferLine(itemId: alchemistGogglesItemId, quantity: 1)],
    );

    final bought = confirmShopOffer(db, shopper(), 'SHP-0010', one, nowMs: now);
    expect(bought.ok, isTrue);
    final save = bought.save!;
    expect(save.gold, 1000 - 138);
    expect(
      save.inventory.singleWhere((stack) => stack.itemId == alchemistGogglesItemId).quantity,
      1,
    );

    final again = confirmShopOffer(db, save, 'SHP-0010', one, nowMs: now);
    expect(again.ok, isFalse);
    expect(again.reason, matches(RegExp('sold out', caseSensitive: false)));

    const two = ShopOffer(
      buys: <ShopOfferLine>[ShopOfferLine(itemId: alchemistGogglesItemId, quantity: 2)],
    );
    expect(confirmShopOffer(db, shopper(), 'SHP-0010', two, nowMs: now).ok, isFalse);

    expect(confirmShopOffer(db, save, 'SHP-0010', one, nowMs: now + dayMs).ok, isTrue);
  });
}
