import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'intent.dart';

/// How often the bot leaves gathering to cook/refine at the Citadel.
const num citadelProductionIntervalMs = 15 * 60 * 1000;

/// Start heading to a station when the bag is this full.
const int bagPressureSlots = 140;

/// Tools that speed gathering or production, highest ATR first.
const List<String> speedToolItemIds = <String>[
  'ITEM-0119', // Steel Pickaxe
  'ITEM-0115', // Iron Pickaxe
  'ITEM-0316', // Oven Mitts
  'ITEM-0111', // Copper Pickaxe
  'ITEM-0110', // Copper Hatchet
  'ITEM-0113', // Copper Harpoon
  'ITEM-0112', // Copper Fishing Rod
];

/// Play-time when the bot last started Citadel production, or null.
class BotMemory {
  const BotMemory({this.lastProductionPlayMs});

  final num? lastProductionPlayMs;

  BotMemory withProduction(num playMs) => BotMemory(lastProductionPlayMs: playMs);
}

/// Chooses the next intent. Pure: no clock or I/O besides [nowMs].
class BotPolicy {
  const BotPolicy();

  BotIntent decide(GameDatabase db, PlayerSave save, num nowMs, BotMemory memory) {
    if (isDeathPaused(save, nowMs)) return const BotWait('death-pause');
    if (save.combatEnemyId != null) return const BotWait('combat');

    final turnIn = _readyQuestTurnIn(db, save);
    if (turnIn != null) return turnIn;

    final accept = _acceptableQuestHere(db, save);
    if (accept != null) return accept;

    final project = _affordableProjectHere(db, save);
    if (project != null) return project;

    final buy = _neededToolPurchase(db, save);
    if (buy != null) return buy;

    if (_shouldProduce(save, memory)) {
      final produce = _citadelProduction(db, save);
      if (produce != null) return produce;
    }

    if (hasRunningPrimaryActivity(save)) return const BotWait('busy');

    return _gather(db, save);
  }

  BotIntent? _readyQuestTurnIn(GameDatabase db, PlayerSave save) {
    for (final progress in save.quests) {
      if (progress.status != 'active') continue;
      final quest = getQuest(db, progress.questId);
      if (quest == null) continue;
      if (!questObjectiveProgress(db, save, quest).ready) continue;
      final parsed = parseStructuredObjectives(quest);
      final npcId = parsed.turnInNpcId ?? quest['NPC ID'];
      final npc = db.npcs.where((row) => row.npcId == npcId).firstOrNull;
      final npcLoc = npc?.locationId;
      if (npcLoc == null) continue;
      if (save.currentLocationId != npcLoc) return _route(db, save, npcLoc);
      return BotCompleteQuest(progress.questId);
    }
    return null;
  }

  BotIntent? _acceptableQuestHere(GameDatabase db, PlayerSave save) {
    for (final npc in npcsAtLocationForSave(db, save, save.currentLocationId)) {
      for (final quest in questsForNpc(db, npc.npcId)) {
        if (getQuestProgress(save, quest['Quest ID']! as String).status != 'inactive') {
          continue;
        }
        if (!questAvailableForSave(db, save, quest)) continue;
        final parsed = parseStructuredObjectives(quest);
        if (parsed.acceptGoldCost > 0) continue;
        if (isMiniquest(quest)) continue;
        return BotAcceptQuest(quest['Quest ID']! as String);
      }
    }
    return null;
  }

  BotIntent? _affordableProjectHere(GameDatabase db, PlayerSave save) {
    for (final station in specialProductionStationsVisibleAt(db, save, save.currentLocationId)) {
      for (final project in projectsForFacility(db, station.facility.facilityId, station.skillId)) {
        final check = validateProjectCompletion(db, save, project.projectId, 1);
        if (!check.ok) continue;
        return BotCompleteProject(project.projectId);
      }
    }
    return null;
  }

  BotIntent? _neededToolPurchase(GameDatabase db, PlayerSave save) {
    for (final itemId in speedToolItemIds) {
      if (_owns(save, itemId)) continue;
      for (final shop in db.shops) {
        final stock = shopStockEntries(shop);
        if (!stock.any((entry) => entry.itemId == itemId)) continue;
        final price = playerBuyPrice(db, shop, itemId);
        if (price == null || save.gold < price) continue;
        final loc = shop.locationId;
        if (save.currentLocationId != loc) {
          final access = canAccessShop(db, save.copyWith(currentLocationId: loc), shop);
          if (!access.ok) continue;
          return _route(db, save, loc);
        }
        if (!canAccessShop(db, save, shop).ok) continue;
        return BotBuy(shop.shopId, itemId);
      }
    }
    return null;
  }

  bool _shouldProduce(PlayerSave save, BotMemory memory) {
    if (inventorySlotCount(save) >= bagPressureSlots) return true;
    final last = memory.lastProductionPlayMs;
    if (last == null) return save.playTimeMs >= citadelProductionIntervalMs;
    return save.playTimeMs - last >= citadelProductionIntervalMs;
  }

  BotIntent? _citadelProduction(GameDatabase db, PlayerSave save) {
    if (save.currentLocationId != citadelProcessingId) {
      return _route(db, save, citadelProcessingId);
    }
    if (hasRunningPrimaryActivity(save)) return const BotWait('producing');
    final activities = db.activities.where(
      (activity) => activity.locationId == citadelProcessingId,
    );
    for (final activity in activities) {
      if (!isStandardProductionActivity(db, activity)) continue;
      final ready = readyRecipesForActivity(db, save, activity.activityId);
      if (ready.isEmpty) continue;
      final recipe = ready.first;
      final qty = maxCraftsFromMaterials(save, recipe);
      if (qty < 1) continue;
      return BotStartProduction(activity.activityId, recipe.recipeId, qty);
    }
    return null;
  }

  BotIntent _gather(GameDatabase db, PlayerSave save) {
    final here = _bestGatherHere(db, save, save.currentLocationId, allowBelow: true);
    final best = _bestGatherAnywhere(db, save);
    if (best != null &&
        (here == null || best.score > here.score) &&
        best.locationId != save.currentLocationId) {
      return _route(db, save, best.locationId);
    }
    if (here != null) return BotStartGather(here.activityId);
    if (best != null) {
      if (best.locationId != save.currentLocationId) return _route(db, save, best.locationId);
      return BotStartGather(best.activityId);
    }
    return const BotWait('no-gather');
  }

  _GatherPick? _bestGatherAnywhere(GameDatabase db, PlayerSave save) {
    _GatherPick? best;
    for (final location in db.locations) {
      final pick = _bestGatherHere(db, save, location.locationId, allowBelow: false);
      if (pick == null) continue;
      if (best == null || pick.score > best.score) best = pick;
    }
    return best;
  }

  _GatherPick? _bestGatherHere(
    GameDatabase db,
    PlayerSave save,
    String locationId, {
    required bool allowBelow,
  }) {
    _GatherPick? best;
    for (final activity in db.activities.where((row) => row.locationId == locationId)) {
      if (!activityVisibleForSave(db, save, activity.activityId)) continue;
      if (isStandardProductionActivity(db, activity)) continue;
      if (_isCombatActivity(db, activity)) continue;
      if (!validateActivityStart(db, save, activity.activityId).ok) continue;
      final scored = _scoreGather(db, save, activity, allowBelow: allowBelow);
      if (scored == null) continue;
      if (best == null || scored.score > best.score) best = scored;
    }
    return best;
  }

  _GatherPick? _scoreGather(
    GameDatabase db,
    PlayerSave save,
    ActivityRow activity, {
    required bool allowBelow,
  }) {
    final poolId = activity.poolId;
    if (poolId == null || poolId.isEmpty) return null;
    var best = 0.0;
    var any = false;
    var anyOnLevel = false;
    for (final entry in eligiblePoolEntries(db, poolId)) {
      final action = entry.action;
      if (action.category == 'Combat') continue;
      if (!isSelectableAction(action)) continue;
      final unmet = unmetHardRequirements(
        db,
        save,
        requirementsForEntity(db, 'Action', action.actionId),
      );
      if (unmet.isNotEmpty) continue;
      any = true;
      final below = isBelowProficiency(save, action);
      if (below && !allowBelow) continue;
      if (!below) anyOnLevel = true;
      final duration = gatheringDurationMs(db, save, action);
      final xp = gatheringXpReward(db, save, action);
      if (duration <= 0) continue;
      final score = (xp / duration) * (below ? 0.25 : 1);
      if (score > best) best = score;
    }
    if (!any) return null;
    if (!allowBelow && !anyOnLevel) return null;
    return _GatherPick(activity.activityId, activity.locationId, best);
  }

  bool _isCombatActivity(GameDatabase db, ActivityRow activity) {
    if ((activity.dangerWarningCombatLevel ?? 0) > 0) return true;
    final poolId = activity.poolId;
    if (poolId == null || poolId.isEmpty) return false;
    return eligiblePoolEntries(db, poolId).any((entry) => entry.action.category == 'Combat');
  }

  BotIntent _route(GameDatabase db, PlayerSave save, String destId) {
    if (save.currentLocationId == destId) return const BotWait('arrived');
    final dest = db.locations.where((row) => row.locationId == destId).firstOrNull;
    if (dest == null) return const BotWait('bad-dest');
    final destMap = getLocationMapId(dest);
    final here = db.locations.where((row) => row.locationId == save.currentLocationId).firstOrNull;
    final hereMap = here == null ? mainMapId : getLocationMapId(here);
    final hop = _gatewayFor(destMap, hereMap, save.currentLocationId);
    if (hop != null) return BotTravel(hop);
    return BotTravel(destId);
  }

  String? _gatewayFor(String destMap, String hereMap, String hereId) {
    if (destMap == hereMap) return null;
    if (destMap == citadelMapId) {
      return hereId == citadelGatewayId ? null : citadelGatewayId;
    }
    if (destMap == townMapId) {
      return hereId == townGatewayId ? null : townGatewayId;
    }
    if (destMap == caveMapId) {
      return hereId == caveEntranceId ? null : caveEntranceId;
    }
    if (destMap == castleMapId) {
      return hereId == castleGatewayId ? null : castleGatewayId;
    }
    if (destMap == forestMapId) {
      return hereId == forestGatewayId ? null : forestGatewayId;
    }
    if (destMap == depthsMapId) {
      return hereId == sunkenApproachId ? null : sunkenApproachId;
    }
    return null;
  }

  bool _owns(PlayerSave save, String itemId) {
    return save.inventory.any((stack) => stack.itemId == itemId && stack.quantity > 0) ||
        save.equipment.slots.values.any((slot) => slot?.itemId == itemId);
  }
}

class _GatherPick {
  const _GatherPick(this.activityId, this.locationId, this.score);

  final String activityId;
  final String locationId;
  final double score;
}
