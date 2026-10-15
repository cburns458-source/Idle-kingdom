import 'package:ik_content/ik_content.dart';

import '../achievements/progress.dart';
import '../cosmetics/cosmetics.dart';
import '../equipment/vitals.dart';
import '../js_compat.dart';
import '../quests/miniquests.dart';
import '../save/generated/save_models.dart';
import 'religion.dart';

class ChooseReligionResult {
  const ChooseReligionResult.ok(this.save, {required this.goldCost}) : reason = null;

  const ChooseReligionResult.failed(this.reason) : save = null, goldCost = 0;

  final PlayerSave? save;
  final String? reason;
  final num goldCost;

  bool get ok => reason == null;
}

List<String> _withReligionHistory(PlayerSave save, String religionId) {
  final current = save.religionHistory;
  if (current.contains(religionId)) return current;
  return [...current, religionId];
}

PlayerSave _unequipLockedFaithTitle(GameDatabase db, PlayerSave save) {
  final equippedId = save.cosmetics.equipped[titleCosmeticSlotId];
  if (equippedId == null || !isFaithTitleLocked(db, save, equippedId)) return save;
  return save.copyWith(
    cosmetics: save.cosmetics.copyWith(
      equipped: {...save.cosmetics.equipped, titleCosmeticSlotId: null},
    ),
  );
}

/// Pick or change faith at the Temple.
///
/// Same-faith retry is a no-op (no gold, no cooldown reset) so a queued hosted
/// command cannot double-charge. First pick is free; later changes cost gold
/// from [religionChangeGoldCost] and share a 7-day server-clock cooldown.
ChooseReligionResult chooseReligion(
  GameDatabase db,
  PlayerSave save,
  String religionId,
  num nowMs,
) {
  if (save.religionId == religionId) {
    return ChooseReligionResult.ok(save, goldCost: 0);
  }

  final religion = religionById(db, religionId);
  if (religion == null) return const ChooseReligionResult.failed('Unknown faith.');

  final templeId = religionChooseLocationId(db);
  if (save.currentLocationId != templeId) {
    return const ChooseReligionResult.failed('Choose a faith at the Temple.');
  }
  if (!religionChooseUnlocked(save)) {
    return const ChooseReligionResult.failed('Reach total level 100 to choose a faith.');
  }

  final readyAt = religionChangeReadyAt(db, save);
  if (readyAt != null && nowMs < readyAt) {
    return ChooseReligionResult.failed('Wait ${formatDurationRemaining(readyAt - nowMs)}.');
  }

  final goldCost = religionChangeGoldCost(db, save);
  if (save.gold < goldCost) {
    return ChooseReligionResult.failed('Need ${jsLocaleNumber(goldCost)} gold.');
  }

  final previousCount = jsNumberOrZero(save.religionChangeCount).floor();
  var next = save.copyWith(
    gold: save.gold - goldCost,
    religionId: religionId,
    religionChangedAt: nowMs,
    religionChangeCount: (previousCount < 0 ? 0 : previousCount) + 1,
    religionHistory: _withReligionHistory(save, religionId),
  );

  final titleId = religion.raw['Title Cosmetic ID'];
  if (titleId is String && titleId.isNotEmpty) {
    next = grantCosmetic(next, titleId).save;
  }
  next = _unequipLockedFaithTitle(db, next);
  next = withRecalculatedVitals(db, next);
  next = syncProgressionMeta(db, next, nowMs);
  return ChooseReligionResult.ok(next, goldCost: goldCost);
}
