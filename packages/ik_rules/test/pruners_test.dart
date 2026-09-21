import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  PlayerSave _withPruners(PlayerSave save) {
    return save.copyWith(
      equipment: save.equipment.copyWith(
        slots: <String, EquippedStack?>{
          ...save.equipment.slots,
          weaponToolSlotId: const EquippedStack(itemId: 'ITEM-0363', quantity: 1),
        },
      ),
    );
  }

  num _xp(PlayerSave save, String skillId) {
    for (final row in save.skills) {
      if (row.skillId == skillId) return row.xp;
    }
    return 0;
  }

  test('Pruners satisfy woodcutting_tool and grant only Botany XP', () {
    final requirement = db.requirements.firstWhere((row) => row.requirementId == 'REQ-0110');
    expect(requirement.referenceIdValue, 'woodcutting_tool');
    final base = createNewSave(db, 0);
    expect(evaluateRequirement(db, base, requirement).met, isFalse);
    expect(evaluateRequirement(db, _withPruners(base), requirement).met, isTrue);

    final action = db.actions.firstWhere((row) => row.raw['Action ID'] == 'ACN-0035');
    final completed = completeGatheringAction(db, _withPruners(base), action, () => 0, 0);
    expect(completed.result.skillId, botanySkillId);
    expect(completed.result.xpGained, 200);
    expect(completed.result.bonusXp, isEmpty);
    expect(_xp(completed.save, 'SKL-0004'), 0);
    expect(_xp(completed.save, botanySkillId), 200);
  });
}
