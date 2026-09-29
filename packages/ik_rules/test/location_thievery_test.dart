import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;
  late PlayerSave save;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
    save = createNewSave(db, 0);
  });

  ActivityRow activity(String id) => db.activities.firstWhere((row) => row.activityId == id);

  test('shop steals route to Shops when a shop row exists', () {
    expect(isShopThieveryActivity(db, save, activity('ACT-0054')), isTrue);
    expect(isShopThieveryActivity(db, save, activity('ACT-0073')), isTrue);
    expect(isNpcThieveryActivity(db, save, activity('ACT-0073')), isFalse);
    expect(isActivityBandThievery(db, save, activity('ACT-0073')), isFalse);
  });

  test('kitchen steal stays on Produce even with an NPC on site', () {
    expect(isShopThieveryActivity(db, save, activity('ACT-0057')), isFalse);
    expect(isNpcThieveryActivity(db, save, activity('ACT-0057')), isFalse);
    expect(isActivityBandThievery(db, save, activity('ACT-0057')), isTrue);
    expect(isProduceBandActivity(db, save, activity('ACT-0057')), isTrue);
    expect(isProduceBandActivity(db, save, activity('ACT-0017')), isTrue);
  });

  test('riverside manor kitchen and storeroom route to Produce', () {
    expect(isProduceBandActivity(db, save, activity('ACT-0088')), isTrue);
    expect(isProduceBandActivity(db, save, activity('ACT-0087')), isTrue);
    expect(isProduceBandActivity(db, save, activity('ACT-0084')), isFalse);
    expect(isProduceBandActivity(db, save, activity('ACT-0085')), isFalse);
    expect(isProduceBandActivity(db, save, activity('ACT-0086')), isFalse);
  });

  test('barracks steal routes to People', () {
    expect(isNpcThieveryActivity(db, save, activity('ACT-0055')), isTrue);
    expect(isShopThieveryActivity(db, save, activity('ACT-0055')), isFalse);
  });

  test('deposit box and vault route to Bank; other lockpicks stay on Produce', () {
    expect(isBankThieveryActivity(db, activity('ACT-0059')), isTrue);
    expect(isBankThieveryActivity(db, activity('ACT-0076')), isTrue);
    expect(isActivityBandThievery(db, save, activity('ACT-0059')), isFalse);
    expect(isActivityBandThievery(db, save, activity('ACT-0056')), isTrue);
    expect(isProduceBandActivity(db, save, activity('ACT-0056')), isTrue);
  });
}
