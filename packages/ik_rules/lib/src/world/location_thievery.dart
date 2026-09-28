import 'package:ik_content/ik_content.dart';

import '../activity/pools.dart';
import '../activity/requirements.dart';
import '../js_compat.dart';
import '../production/recipes.dart';
import '../save/generated/save_models.dart';
import '../skills/skill_actions.dart';

List<ActionRow> _thieveryActionsForActivity(GameDatabase db, ActivityRow activity) {
  final poolId = activity.poolId;
  if (poolId == null || poolId.isEmpty) return const <ActionRow>[];
  return eligiblePoolEntries(db, poolId)
      .map((entry) => entry.action)
      .where((action) => jsString(action.raw['Relevant Skill ID']) == thieverySkillMenuId)
      .toList();
}

bool _isBankThieveryAction(ActionRow action) {
  return RegExp(r'BankThievery', caseSensitive: false).hasMatch(action.notes ?? '');
}

/// Deposit-box / vault picks that belong with the Bank panel.
bool isBankThieveryActivity(GameDatabase db, ActivityRow activity) {
  return _thieveryActionsForActivity(db, activity).any(_isBankThieveryAction);
}

/// Shop steals listed under the Shops tab when this location has a merchant.
///
/// Kitchen steals stay in Activities (no shop row; production blocks People routing).
bool isShopThieveryActivity(GameDatabase db, PlayerSave save, ActivityRow activity) {
  if (!_thieveryActionsForActivity(db, activity).any(isThieveryShopAction)) return false;
  return db.shops.any((shop) => jsString(shop.raw['Location ID']) == activity.locationId);
}

/// NPC-targeted steals when there is no shop (barracks).
///
/// Kitchen / production sites keep steals in Activities even if an NPC is present.
bool isNpcThieveryActivity(GameDatabase db, PlayerSave save, ActivityRow activity) {
  if (!_thieveryActionsForActivity(db, activity).any(isThieveryShopAction)) return false;
  if (isShopThieveryActivity(db, save, activity)) return false;
  if (_locationHasProductionWorkstation(db, save, activity.locationId)) return false;
  return db.npcs.any((npc) => jsString(npc.raw['Location ID']) == activity.locationId);
}

bool _locationHasProductionWorkstation(GameDatabase db, PlayerSave save, String locationId) {
  return db.activities.any(
    (row) =>
        row.locationId == locationId &&
        isStandardProductionActivity(db, row) &&
        activityVisibleForSave(db, save, row.activityId),
  );
}

bool isThieveryActivity(GameDatabase db, ActivityRow activity) {
  return _thieveryActionsForActivity(db, activity).isNotEmpty;
}

/// Activities-band thievery: kitchen steals and non-bank lockpicks.
bool isActivityBandThievery(GameDatabase db, PlayerSave save, ActivityRow activity) {
  final actions = _thieveryActionsForActivity(db, activity);
  if (actions.isEmpty) return false;
  if (isBankThieveryActivity(db, activity)) return false;
  if (isShopThieveryActivity(db, save, activity)) return false;
  if (isNpcThieveryActivity(db, save, activity)) return false;
  return actions.any(isThieveryLockpickAction) || actions.any(isThieveryShopAction);
}
