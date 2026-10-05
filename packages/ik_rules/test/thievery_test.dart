import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  ActionRow action(String id) => db.actions.firstWhere((row) => row.actionId == id);

  test('lockpick break chance is its own reducible roll', () {
    expect(lockpickBreakChancePercent(1), 50);
    expect(lockpickBreakChancePercent(100), 99.5);
    expect(lockpickBreakChancePercent(1, 20), 30);
    expect(lockpickBreakChancePercent(1, 80), 0);
    expect(parseLockpickBreakChanceReductionPercent('-20% lockpick break chance'), 20);
    expect(parseLockpickBreakChanceReductionPercent('lockpick_break:-15'), 15);
  });

  test('a missed steal is a catch: damage, no XP, no loot', () {
    final steal = action('ACN-0185');
    expect(jsString(steal.raw['Notes']), isNot(contains('FailChance:')));
    final save = createNewSave(db, 0);
    final beforeXp = getSkillProgress(save, 'SKL-0015').xp;
    final completed = completeGatheringAction(db, save, steal, () => 0.81, 0);
    expect(completed.result.thieveryFailed, isTrue);
    expect(completed.result.xpGained, 0);
    expect(completed.result.loot, isEmpty);
    expect(completed.result.damageTaken, greaterThan(0));
    expect(completed.save.currentHp, save.currentHp - completed.result.damageTaken);
    expect(getSkillProgress(completed.save, 'SKL-0015').xp, beforeXp);
  });

  test('successful lockpicks keep the pick; a catch can snap it', () {
    final pick = action('ACN-0187');
    expect(jsString(pick.raw['Notes']), contains('RequiresLockpick'));
    expect(jsString(pick.raw['Notes']), isNot(contains('FailChance:')));

    PlayerSave withPicks() {
      final base = createNewSave(db, 0);
      return base.copyWith(
        currentHp: base.maxHp,
        skills: [
          for (final skill in base.skills)
            if (skill.skillId == 'SKL-0015')
              const SkillProgress(skillId: 'SKL-0015', level: 45, xp: 0)
            else
              skill,
        ],
        equipment: base.equipment.copyWith(
          slots: <String, EquippedStack?>{
            ...base.equipment.slots,
            weaponToolSlotId: const EquippedStack(itemId: lockpickItemId, quantity: 3),
          },
        ),
      );
    }

    final intact = completeGatheringAction(db, withPicks(), pick, () => 0, 0);
    expect(intact.result.thieveryFailed, isFalse);
    expect(intact.result.lockpickBroke, isFalse);
    expect(intact.result.damageTaken, 0);
    expect(intact.result.xpGained, greaterThan(0));
    expect(intact.save.equipment.slots[weaponToolSlotId]?.quantity, 3);

    final rolls = <num>[0.81, 0];
    var i = 0;
    final caught = completeGatheringAction(
      db,
      withPicks(),
      pick,
      () => rolls[i < rolls.length ? i++ : rolls.length - 1],
      0,
    );
    expect(caught.result.thieveryFailed, isTrue);
    expect(caught.result.lockpickBroke, isTrue);
    expect(caught.result.xpGained, 0);
    expect(caught.save.equipment.slots[weaponToolSlotId]?.quantity, 2);
  });

  test('a missed kitchen steal is a catch like other thievery', () {
    final kitchen = action('ACN-0188');
    expect(jsString(kitchen.raw['Notes']), contains('FailDamagePercent:10'));
    expect(jsString(kitchen.raw['Notes']), isNot(contains('NoConsequences')));
    final save = createNewSave(db, 0);
    final completed = completeGatheringAction(db, save, kitchen, () => 0.81, 0);
    expect(completed.result.thieveryFailed, isTrue);
    expect(completed.result.damageTaken, greaterThan(0));
    expect(completed.result.xpGained, 0);
    expect(completed.save.currentHp, save.currentHp - completed.result.damageTaken);
  });
}
