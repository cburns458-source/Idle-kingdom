import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));
  });

  test('specialist gear knobs live in Config', () {
    expect(configString(db, 'specialist.chef_hat_item_id', ''), chefHatItemId);
    expect(configString(db, 'specialist.wizard_hat_item_id', ''), wizardHatItemId);
    expect(configString(db, 'specialist.quiver_item_id', ''), quiverItemId);
    expect(configString(db, 'specialist.alchemist_goggles_item_id', ''), alchemistGogglesItemId);
    expect(configNumber(db, 'specialist.chef_hat_double_chance', 0), chefHatDoubleChance);
    expect(configNumber(db, 'specialist.wizard_hat_essence_factor', 0), wizardHatEssenceFactor);
    expect(configNumber(db, 'specialist.quiver_hunting_xp_factor', 0), quiverHuntingXpFactor);
    expect(configNumber(db, 'specialist.alchemy_potion_output_max', 0), alchemyPotionOutputMax);
    expect(configNumber(db, 'specialist.alchemy_potion_output_min', 0), alchemyPotionOutputMin);
    expect(
      configNumber(db, 'specialist.alchemy_potion_output_goggles_min', 0),
      alchemyPotionOutputGogglesMin,
    );
  });

  test('wizard hat essence discount reads the Config factor', () {
    var save = createNewSave(db, 0);
    save = save.copyWith(
      equipment: save.equipment.copyWith(
        slots: <String, EquippedStack?>{
          ...save.equipment.slots,
          'SLOT-0003': const EquippedStack(itemId: wizardHatItemId, quantity: 1),
        },
      ),
    );
    expect(wizardEssenceCost(db, 100, save), 99);

    final raw = Map<String, Object?>.of(db.raw);
    raw['Config'] = [
      for (final row in db.config)
        if (row.raw['Key'] == 'specialist.wizard_hat_essence_factor')
          <String, Object?>{...row.raw, 'Value': 0.5}
        else
          row.raw,
    ];
    final cheaper = GameDatabase(raw);
    expect(wizardEssenceCost(cheaper, 100, save), 50);
  });
}
