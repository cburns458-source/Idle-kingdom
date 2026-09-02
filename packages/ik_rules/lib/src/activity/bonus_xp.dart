import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../config.dart';
import '../js_compat.dart';
import '../save/generated/save_models.dart';
import '../tags.dart';

/// A skill XP grant beyond an action's own Relevant Skill reward.
class BonusXpGrant {
  const BonusXpGrant({required this.skillId, required this.xp});

  final String skillId;
  final num xp;

  Map<String, Object?> toJson() => <String, Object?>{'skillId': skillId, 'xp': xp};
}

/// Extra skill XP granted on specific Actions beyond Relevant Skill ID / XP Reward.
const Map<String, BonusXpGrant> _bonusSkillXp = <String, BonusXpGrant>{};

BonusXpGrant? bonusSkillXpForAction(String actionId) => _bonusSkillXp[actionId];

const String _huntingSkillId = 'SKL-0005';
const String _combatSkillId = 'SKL-0001';
const String _bowCapabilityTag = 'bow_combat_xp';

bool _equippedWeaponHasCapability(GameDatabase db, PlayerSave save, String tag) {
  final stack = save.equipment.slots[weaponToolSlotId];
  if (stack == null || isBlank(stack.itemId)) return false;
  final equipment = db.equipment.firstWhereOrNull((row) => row.raw['Item ID'] == stack.itemId);
  return capabilityTags(equipment?.raw['Capabilities / Effects']).contains(tag);
}

/// Combat XP earned alongside Hunting XP when a bow is equipped.
///
/// Qualifying bow-based Hunting Actions grant Combat XP equal to a percentage
/// (default 10%, see Config `bow_hunting_combat_xp_percent`) of the Hunting XP
/// just awarded, whenever the equipped Weapon/Tool carries the `bow_combat_xp`
/// capability. See docs/Game_Bible.txt section 8.4.
BonusXpGrant? bowHuntingCombatXpBonus(
  GameDatabase db,
  PlayerSave save,
  String relevantSkillId,
  num huntingXpAwarded,
) {
  if (relevantSkillId != _huntingSkillId) return null;
  if (huntingXpAwarded <= 0) return null;
  if (!_equippedWeaponHasCapability(db, save, _bowCapabilityTag)) return null;
  final percent = configNumber(db, 'bow_hunting_combat_xp_percent', 10);
  final xp = (huntingXpAwarded * (percent / 100)).floor();
  return xp > 0 ? BonusXpGrant(skillId: _combatSkillId, xp: xp) : null;
}
