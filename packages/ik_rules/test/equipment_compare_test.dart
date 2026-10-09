import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

GameDatabase _db() => filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = _db();
  });

  PlayerSave _withSkill(PlayerSave save, String skillId, num level) {
    final skills = [...save.skills];
    final index = skills.indexWhere((skill) => skill.skillId == skillId);
    final progress = SkillProgress(skillId: skillId, level: level, xp: 0);
    if (index < 0) {
      skills.add(progress);
    } else {
      skills[index] = progress;
    }
    return save.copyWith(skills: skills);
  }

  test('compares a stronger hatchet against an empty weapon slot', () {
    var save = createNewSave(db, 0);
    save = _withSkill(save, 'SKL-0006', 20);
    final result = compareEquipmentCandidate(db, save, itemId: 'ITEM-0114');
    expect(result.ok, isTrue, reason: result.reason);
    expect(result.slotId, weaponToolSlotId);
    expect(result.slotEmpty, isTrue);
    expect(result.equippedName, isNull);
    final damage = result.lines.where((line) => line.label == 'Attack damage').single;
    expect(damage.kind, EquipCompareDeltaKind.improved);
  });

  test('shows improved damage when replacing a weaker weapon', () {
    var save = createNewSave(db, 0);
    save = _withSkill(save, mightSkillId, 20);
    save = equipStackToSlot(save, weaponToolSlotId, 'ITEM-0124', 1);
    final result = compareEquipmentCandidate(db, save, itemId: 'ITEM-0128');
    expect(result.ok, isTrue, reason: result.reason);
    expect(result.equippedItemId, 'ITEM-0124');
    expect(result.equippedName, 'Wooden Sword');
    expect(result.candidateName, 'Iron Sword');
    final damage = result.lines.where((line) => line.label == 'Attack damage').single;
    expect(damage.kind, EquipCompareDeltaKind.improved);
  });

  test('shows health and DR deltas for shields', () {
    var save = createNewSave(db, 0);
    save = _withSkill(save, vitalitySkillId, 35);
    save = equipStackToSlot(save, offhandSlotId, 'ITEM-0145', 1);
    final result = compareEquipmentCandidate(db, save, itemId: 'ITEM-0148');
    expect(result.ok, isTrue, reason: result.reason);
    expect(result.equippedItemId, 'ITEM-0145');
    final health = result.lines.where((line) => line.label == 'Health').single;
    expect(health.kind, EquipCompareDeltaKind.improved);
    final dr = result.lines.where((line) => line.label == 'Damage reduction').single;
    expect(dr.kind, EquipCompareDeltaKind.improved);
  });

  test('two-handed weapon notes clearing the off-hand', () {
    var save = createNewSave(db, 0);
    save = _withSkill(save, 'SKL-0008', 35);
    save = equipStackToSlot(save, offhandSlotId, 'ITEM-0145', 1);
    final result = compareEquipmentCandidate(db, save, itemId: 'ITEM-0123');
    expect(result.ok, isTrue, reason: result.reason);
    expect(result.displaced, isNotEmpty);
    expect(result.displaced.single.slotId, offhandSlotId);
    expect(result.displaced.single.itemId, 'ITEM-0145');
    expect(result.lines.any((line) => line.label.startsWith('Also clears')), isTrue);
  });

  test('off-hand item notes clearing a worn two-hander', () {
    var save = createNewSave(db, 0);
    save = _withSkill(save, 'SKL-0008', 35);
    save = equipStackToSlot(save, weaponToolSlotId, 'ITEM-0123', 1);
    final result = compareEquipmentCandidate(db, save, itemId: 'ITEM-0145');
    expect(result.ok, isTrue, reason: result.reason);
    expect(result.displaced.single.slotId, weaponToolSlotId);
    expect(result.displaced.single.itemId, 'ITEM-0123');
  });

  test('refuses non-equipment items', () {
    final save = createNewSave(db, 0);
    final result = compareEquipmentCandidate(db, save, itemId: 'ITEM-0003');
    expect(result.ok, isFalse);
    expect(result.reason, 'That item cannot be equipped.');
    expect(result.lines, isEmpty);
  });

  test('refuses gear that fails skill requirements', () {
    final save = createNewSave(db, 0);
    final result = compareEquipmentCandidate(db, save, itemId: 'ITEM-0255');
    expect(result.ok, isFalse);
    expect(result.reason, contains('Requires'));
  });

  test('preview does not mutate the original save', () {
    var save = createNewSave(db, 0);
    save = equipStackToSlot(save, weaponToolSlotId, 'ITEM-0124', 1);
    final before = save.toJson();
    compareEquipmentCandidate(db, save, itemId: 'ITEM-0128');
    expect(save.toJson(), before);
    expect(slotItemId(save, weaponToolSlotId), 'ITEM-0124');
  });

  test('daggers resolve to the off-hand slot', () {
    final save = createNewSave(db, 0);
    final resolved = resolveCompareSlot(db, save, 'ITEM-0125');
    expect(resolved.slotId, offhandSlotId);
    expect(resolved.reason, isNull);
  });
}
