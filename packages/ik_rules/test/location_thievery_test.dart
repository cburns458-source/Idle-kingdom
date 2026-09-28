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

  test('kitchen steal stays in Activities even with an NPC on site', () {
    expect(isShopThieveryActivity(db, save, activity('ACT-0057')), isFalse);
    expect(isNpcThieveryActivity(db, save, activity('ACT-0057')), isFalse);
    expect(isActivityBandThievery(db, save, activity('ACT-0057')), isTrue);
  });

  test('barracks steal routes to People', () {
    expect(isNpcThieveryActivity(db, save, activity('ACT-0055')), isTrue);
    expect(isShopThieveryActivity(db, save, activity('ACT-0055')), isFalse);
  });

  test('deposit box and vault route to Bank; other lockpicks stay in Activities', () {
    expect(isBankThieveryActivity(db, activity('ACT-0059')), isTrue);
    expect(isBankThieveryActivity(db, activity('ACT-0076')), isTrue);
    expect(isActivityBandThievery(db, save, activity('ACT-0059')), isFalse);
    expect(isActivityBandThievery(db, save, activity('ACT-0056')), isTrue);
  });
}
