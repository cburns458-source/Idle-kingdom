import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/rewards.dart';
import '../activity/xp.dart';
import '../inventory/add_items.dart';
import '../inventory/capacity.dart';
import '../production/inventory.dart';
import '../production/recipes.dart';
import '../quests/quests.dart';
import '../save/generated/save_models.dart';
import '../trackers/trackers.dart';

const String botanySkillId = 'SKL-0014';
const String thieverySkillId = 'SKL-0015';
const String glovesSlotId = 'SLOT-0007';
const String courtyardLocationId = 'LOC-0014';
const String grandFeastQuestId = 'QST-0001';
const String shallowsLocationId = 'LOC-0043';

const String fishingPotItemId = 'ITEM-0347';

/// Ready botany timers stay in place when the bag cannot take the haul.
const String timerInventoryFullHarvestReason = 'Come back with more room to collect your harvest.';

/// Ready fishing pots stay in place when the bag cannot take the haul.
const String timerInventoryFullCatchReason = 'Come back with more room to collect your catch.';

String timerInventoryFullReasonFor(String kind) =>
    kind == 'fishing_pot' ? timerInventoryFullCatchReason : timerInventoryFullHarvestReason;

bool isTimerInventoryFullReason(String reason) =>
    reason == timerInventoryFullHarvestReason || reason == timerInventoryFullCatchReason;

/// Deprecated alias for [fishingPotItemId].
const String fishingTrapItemId = fishingPotItemId;

/// Botany patches: Farm, Courtyard, Gathering Outskirts, Mountains, Shallows, Temple, Meadow.
const Set<String> botanyPatchLocations = <String>{
  'LOC-0001',
  'LOC-0014',
  'LOC-0031',
  'LOC-0006',
  'LOC-0043',
  'LOC-0036',
  'LOC-0009',
};

const Set<String> fishingPotLocations = <String>{'LOC-0003', 'LOC-0004'};

/// Deprecated alias for [fishingPotLocations].
const Set<String> fishingTrapLocations = fishingPotLocations;

const num trapDurationMs = 6 * 60 * 60 * 1000;

class BotanySeedSpec {
  const BotanySeedSpec({
    required this.outputItemId,
    required this.growSeconds,
    required this.xp,
    required this.requiresLevel,
    required this.shallowsOnly,
    required this.isSapling,
  });

  final String outputItemId;
  final num growSeconds;
  final num xp;
  final num requiresLevel;
  final bool shallowsOnly;
  final bool isSapling;
}

ItemRow? _itemById(GameDatabase db, String itemId) =>
    db.items.firstWhereOrNull((row) => row.raw['Item ID'] == itemId);

String _itemTags(ItemRow? item) {
  return (item?.functionalSourceTags ?? '').toLowerCase();
}

bool isBotanySeedItem(GameDatabase db, String itemId) {
  final tags = _itemTags(_itemById(db, itemId));
  return tags.contains('botany_seed') || tags.contains('botany_sapling');
}

BotanySeedSpec? parseBotanySeedSpec(GameDatabase db, String itemId) {
  final item = _itemById(db, itemId);
  if (item == null || !isBotanySeedItem(db, itemId)) return null;
  final notes = item.raw['Notes'];
  final text = notes is String ? notes : '';
  final output = RegExp(r'Output:([A-Z0-9-]+)', caseSensitive: false).firstMatch(text)?.group(1);
  final grow =
      num.tryParse(
        RegExp(r'GrowSeconds:(\d+)', caseSensitive: false).firstMatch(text)?.group(1) ?? '',
      ) ??
      0;
  final xp =
      num.tryParse(RegExp(r'Xp:(\d+)', caseSensitive: false).firstMatch(text)?.group(1) ?? '') ?? 0;
  final requiresLevel =
      num.tryParse(
        RegExp(r'RequiresLevel:(\d+)', caseSensitive: false).firstMatch(text)?.group(1) ?? '',
      ) ??
      1;
  if (output == null || grow <= 0) return null;
  final tags = _itemTags(item);
  return BotanySeedSpec(
    outputItemId: output,
    growSeconds: grow,
    xp: xp < 0 ? 0 : xp,
    requiresLevel: requiresLevel < 1 ? 1 : requiresLevel,
    shallowsOnly:
        RegExp(r'ShallowsOnly', caseSensitive: false).hasMatch(text) ||
        tags.contains('shallows_only'),
    isSapling: tags.contains('botany_sapling'),
  );
}

bool inventoryHasAnyBotanySeed(GameDatabase db, PlayerSave save) {
  return save.inventory.any((stack) => stack.quantity > 0 && isBotanySeedItem(db, stack.itemId));
}

class PlantableBotanyOption {
  const PlantableBotanyOption({
    required this.itemId,
    required this.displayName,
    required this.spec,
    required this.owned,
    required this.plantQuantity,
    required this.canPlant,
    required this.reason,
  });

  final String itemId;
  final String displayName;
  final BotanySeedSpec spec;
  final num owned;
  final num plantQuantity;
  final bool canPlant;
  final String reason;
}

/// Seeds/saplings the player owns that could be offered on a patch menu.
List<PlantableBotanyOption> listPlantableBotanyOptions(
  GameDatabase db,
  PlayerSave save, {
  String? locationId,
}) {
  final loc = locationId ?? save.currentLocationId;
  final options = <PlantableBotanyOption>[];
  final seen = <String>{};
  for (final stack in save.inventory) {
    if (stack.quantity <= 0) continue;
    if (!seen.add(stack.itemId)) continue;
    final spec = parseBotanySeedSpec(db, stack.itemId);
    if (spec == null) continue;
    final owned = save.inventory
        .where((row) => row.itemId == stack.itemId)
        .fold<num>(0, (sum, row) => sum + row.quantity);
    final desired = spec.isSapling ? 1 : (owned < 3 ? owned : 3);
    final gate = canPlantBotanySeed(
      db,
      save,
      stack.itemId,
      locationId: loc,
      plantQuantity: desired,
    );
    final item = _itemById(db, stack.itemId);
    options.add(
      PlantableBotanyOption(
        itemId: stack.itemId,
        displayName: item?.displayName ?? stack.itemId,
        spec: spec,
        owned: owned,
        plantQuantity: gate.ok ? gate.quantity : desired,
        canPlant: gate.ok,
        reason: gate.reason,
      ),
    );
  }
  options.sort((a, b) {
    final level = a.spec.requiresLevel.compareTo(b.spec.requiresLevel);
    if (level != 0) return level;
    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  });
  return options;
}

/// Any timer at a location (first match). Prefer [timerAtLocationKind] when kind matters.
LocationTimer? timerAtLocation(PlayerSave save, String locationId) {
  return save.locationTimers.firstWhereOrNull((timer) => timer.locationId == locationId);
}

/// Timer matching both location and kind (at most one of each kind per spot).
LocationTimer? timerAtLocationKind(PlayerSave save, String locationId, String kind) {
  return save.locationTimers.firstWhereOrNull(
    (timer) => timer.locationId == locationId && timer.kind == kind,
  );
}

List<LocationTimer> _withoutLocationTimerKind(
  List<LocationTimer> timers,
  String locationId,
  String kind,
) {
  return timers.where((row) => !(row.locationId == locationId && row.kind == kind)).toList();
}

/// Stable key for a timer spot in [PlayerSave.discoveredTimerSpotIds].
String timerSpotKey(String kind, String locationId) => '$kind:$locationId';

/// Split a spot key back into kind + location, or null if malformed.
({String kind, String locationId})? parseTimerSpotKey(String key) {
  final sep = key.indexOf(':');
  if (sep <= 0) return null;
  final kind = key.substring(0, sep);
  final locationId = key.substring(sep + 1);
  if (locationId.isEmpty) return null;
  if (kind != 'botany' && kind != 'fishing_pot') return null;
  return (kind: kind, locationId: locationId);
}

/// Marks Botany / fishing pot spots at [locationId] as discovered when the
/// location supports them. Safe to call on plant, place, or travel arrival.
PlayerSave discoverTimerSpotsForLocation(PlayerSave save, String locationId) {
  final discovered = <String>{...save.discoveredTimerSpotIds};
  var changed = false;
  void add(String kind) {
    final key = timerSpotKey(kind, locationId);
    if (discovered.contains(key)) return;
    discovered.add(key);
    changed = true;
  }

  if (botanyPatchLocations.contains(locationId)) add('botany');
  if (fishingTrapLocations.contains(locationId)) add('fishing_pot');
  if (!changed) return save;
  return save.copyWith(discoveredTimerSpotIds: discovered.toList());
}

num timerCompletesAtMs(LocationTimer timer) {
  return DateTime.parse(timer.startedAt).millisecondsSinceEpoch + timer.durationMs;
}

bool timerIsReady(LocationTimer timer, num nowMs) {
  return nowMs >= timerCompletesAtMs(timer);
}

bool courtyardBotanyUnlocked(PlayerSave save) {
  return getQuestProgress(save, grandFeastQuestId).status == 'completed';
}

bool locationHasBotanyPatch(String locationId) => botanyPatchLocations.contains(locationId);

({bool ok, num quantity, String reason}) canPlantBotanySeed(
  GameDatabase db,
  PlayerSave save,
  String seedItemId, {
  String? locationId,
  num plantQuantity = 1,
}) {
  final loc = locationId ?? save.currentLocationId;
  if (!locationHasBotanyPatch(loc)) {
    return (ok: false, quantity: 0, reason: 'There is no Botany patch here.');
  }
  if (loc == courtyardLocationId && !courtyardBotanyUnlocked(save)) {
    return (
      ok: false,
      quantity: 0,
      reason: 'Complete The Grand Feast to unlock the Courtyard plot.',
    );
  }
  if (timerAtLocationKind(save, loc, 'botany') != null) {
    return (ok: false, quantity: 0, reason: 'This patch is already growing.');
  }
  final spec = parseBotanySeedSpec(db, seedItemId);
  if (spec == null) {
    return (ok: false, quantity: 0, reason: 'That item cannot be planted.');
  }
  if (spec.shallowsOnly && loc != shallowsLocationId) {
    return (ok: false, quantity: 0, reason: 'Kelp only grows in The Shallows.');
  }
  if (!spec.shallowsOnly && loc == shallowsLocationId) {
    return (ok: false, quantity: 0, reason: 'The Shallows plot only accepts kelp.');
  }
  final botanyLevel = getSkillProgress(save, botanySkillId).level;
  if (botanyLevel < spec.requiresLevel) {
    return (ok: false, quantity: 0, reason: 'Requires Botany level ${spec.requiresLevel}.');
  }
  final have = save.inventory
      .where((stack) => stack.itemId == seedItemId)
      .fold<num>(0, (sum, stack) => sum + stack.quantity);
  if (have < 1) return (ok: false, quantity: 0, reason: 'You do not have that seed.');
  final maxQty = spec.isSapling ? 1 : 3;
  // Math.max(1, Math.min(maxQty, Math.floor(plantQuantity), have))
  var quantity = plantQuantity.floor();
  if (quantity > maxQty) quantity = maxQty;
  if (quantity > have.floor()) quantity = have.floor();
  if (quantity < 1) quantity = 1;
  if (spec.isSapling && quantity != 1) {
    return (ok: false, quantity: 0, reason: 'A patch holds one sapling.');
  }
  return (ok: true, quantity: quantity, reason: '');
}

({bool ok, PlayerSave? save, String reason}) plantBotanySeed(
  GameDatabase db,
  PlayerSave save,
  String seedItemId, {
  required num nowMs,
  num plantQuantity = 3,
}) {
  final loc = save.currentLocationId;
  final gate = canPlantBotanySeed(
    db,
    save,
    seedItemId,
    locationId: loc,
    plantQuantity: plantQuantity,
  );
  if (!gate.ok) return (ok: false, save: null, reason: gate.reason);
  final spec = parseBotanySeedSpec(db, seedItemId)!;
  final removed = removeIngredients(save, [
    RecipeIngredient(itemId: seedItemId, quantity: gate.quantity),
  ]);
  if (removed == null) return (ok: false, save: null, reason: 'You do not have that seed.');
  final started = DateTime.fromMillisecondsSinceEpoch(nowMs.round()).toIso8601String();
  final timer = LocationTimer(
    locationId: loc,
    kind: 'botany',
    inputItemId: seedItemId,
    outputItemId: spec.outputItemId,
    // Planted count; yield is rolled on collect.
    outputQuantity: gate.quantity,
    skillId: botanySkillId,
    xpReward: spec.xp * gate.quantity,
    startedAt: started,
    durationMs: spec.growSeconds * 1000,
  );
  return (
    ok: true,
    save: discoverTimerSpotsForLocation(
      removed.copyWith(
        locationTimers: [
          ..._withoutLocationTimerKind(removed.locationTimers, loc, 'botany'),
          timer,
        ],
      ),
      loc,
    ),
    reason: '',
  );
}

({bool ok, PlayerSave? save, String reason}) plantBestBotanySeed(
  GameDatabase db,
  PlayerSave save, {
  required num nowMs,
}) {
  for (final stack in save.inventory) {
    if (stack.quantity <= 0) continue;
    final spec = parseBotanySeedSpec(db, stack.itemId);
    if (spec == null) continue;
    final qty = spec.isSapling ? 1 : (stack.quantity < 3 ? stack.quantity : 3);
    final planted = plantBotanySeed(db, save, stack.itemId, nowMs: nowMs, plantQuantity: qty);
    if (planted.ok) return planted;
  }
  return (ok: false, save: null, reason: 'You have no plantable seeds or saplings for this patch.');
}

String fishingPotUtcDayKey(num nowMs) {
  return DateTime.fromMillisecondsSinceEpoch(
    nowMs.round(),
    isUtc: true,
  ).toIso8601String().substring(0, 10);
}

/// Ms until the next UTC midnight after [nowMs].
num msUntilNextUtcDay(num nowMs) {
  final now = DateTime.fromMillisecondsSinceEpoch(nowMs.round(), isUtc: true);
  final next = DateTime.utc(now.year, now.month, now.day + 1);
  final delta = next.millisecondsSinceEpoch - nowMs;
  return delta < 0 ? 0 : delta;
}

({bool locked, String dayKey, num msRemaining}) fishingPotLockedUntilDay(
  PlayerSave save,
  String locationId, {
  required num nowMs,
}) {
  final now = nowMs;
  final dayKey = fishingPotUtcDayKey(now);
  final used = save.fishingPotDayKeyByLocationId[locationId];
  if (used == dayKey) {
    return (locked: true, dayKey: dayKey, msRemaining: msUntilNextUtcDay(now));
  }
  return (locked: false, dayKey: dayKey, msRemaining: 0);
}

({bool ok, String? kind, String reason}) canPlaceTrap(
  GameDatabase db,
  PlayerSave save,
  String trapItemId, {
  String? locationId,
  required num nowMs,
}) {
  final loc = locationId ?? save.currentLocationId;
  final now = nowMs;
  if (trapItemId == fishingPotItemId) {
    if (!fishingPotLocations.contains(loc)) {
      return (
        ok: false,
        kind: null,
        reason: 'Fishing pots only work at the Goblin Camp and Docks.',
      );
    }
    if (timerAtLocationKind(save, loc, 'fishing_pot') != null) {
      return (ok: false, kind: null, reason: 'A fishing pot is already set here.');
    }
    final lock = fishingPotLockedUntilDay(save, loc, nowMs: now);
    if (lock.locked) {
      return (
        ok: false,
        kind: null,
        reason: 'You should not overfish. Come back after the daily reset.',
      );
    }
    final fishingLevel = getSkillProgress(save, 'SKL-0003').level;
    final unlocked = potFishOptionsForLocation(loc, fishingLevel);
    if (unlocked.isEmpty) {
      final need = loc == 'LOC-0004' ? 35 : 14;
      return (
        ok: false,
        kind: null,
        reason: 'You need Fishing $need before this pot will catch anything.',
      );
    }
    final have = save.inventory
        .where((stack) => stack.itemId == trapItemId)
        .fold<num>(0, (sum, stack) => sum + stack.quantity);
    if (have < 1) return (ok: false, kind: null, reason: 'You do not have a fishing pot.');
    return (ok: true, kind: 'fishing_pot', reason: '');
  }
  return (ok: false, kind: null, reason: 'That is not a placeable trap.');
}

({bool ok, PlayerSave? save, String reason}) placeTrap(
  GameDatabase db,
  PlayerSave save,
  String trapItemId, {
  required num nowMs,
}) {
  final loc = save.currentLocationId;
  final now = nowMs;
  final gate = canPlaceTrap(db, save, trapItemId, locationId: loc, nowMs: now);
  if (!gate.ok) return (ok: false, save: null, reason: gate.reason);
  final removed = removeIngredients(save, [RecipeIngredient(itemId: trapItemId, quantity: 1)]);
  if (removed == null) {
    return (ok: false, save: null, reason: 'You do not have a fishing pot.');
  }
  final kind = gate.kind!;
  final started = DateTime.fromMillisecondsSinceEpoch(now.round()).toIso8601String();
  final timer = LocationTimer(
    locationId: loc,
    kind: kind,
    inputItemId: trapItemId,
    outputItemId: null,
    outputQuantity: 1,
    skillId: 'SKL-0003',
    xpReward: 150,
    startedAt: started,
    durationMs: trapDurationMs,
  );
  var next = removed.copyWith(
    locationTimers: [..._withoutLocationTimerKind(removed.locationTimers, loc, kind), timer],
  );
  next = next.copyWith(
    fishingPotDayKeyByLocationId: <String, String>{
      ...next.fishingPotDayKeyByLocationId,
      loc: fishingPotUtcDayKey(now),
    },
  );
  return (ok: true, save: discoverTimerSpotsForLocation(next, loc), reason: '');
}

/// Pot-fishing catches: Goblin Camp freshwater vs Docks saltwater.
const Map<String, List<({String itemId, num fishingLevel, num xpEach})>> potFishByLocation =
    <String, List<({String itemId, num fishingLevel, num xpEach})>>{
      'LOC-0003': [
        (itemId: 'ITEM-0352', fishingLevel: 14, xpEach: 150),
        (itemId: 'ITEM-0354', fishingLevel: 44, xpEach: 350),
        (itemId: 'ITEM-0356', fishingLevel: 64, xpEach: 520),
      ],
      'LOC-0004': [
        (itemId: 'ITEM-0353', fishingLevel: 35, xpEach: 280),
        (itemId: 'ITEM-0355', fishingLevel: 55, xpEach: 450),
        (itemId: 'ITEM-0357', fishingLevel: 75, xpEach: 650),
      ],
    };

List<({String itemId, num fishingLevel, num xpEach})> potFishOptionsForLocation(
  String locationId,
  num fishingLevel,
) {
  return [
    for (final row
        in potFishByLocation[locationId] ??
            const <({String itemId, num fishingLevel, num xpEach})>[])
      if (fishingLevel >= row.fishingLevel) row,
  ];
}

List<({String itemId, num quantity, num xp})> _rollFishingPotLoot(
  String locationId,
  num fishingLevel,
  num Function() random,
) {
  return potFishOptionsForLocation(locationId, fishingLevel).map((row) {
    final quantity = _rollInclusive(random, 1, 3);
    return (itemId: row.itemId, quantity: quantity, xp: row.xpEach * quantity);
  }).toList();
}

String _timerItemName(GameDatabase db, String itemId) {
  final name = db.items
      .firstWhereOrNull((item) => item.raw['Item ID'] == itemId)
      ?.raw['Display Name'];
  return name is String ? name : itemId;
}

bool _canFitTimerGrants(
  GameDatabase db,
  PlayerSave save,
  List<({String itemId, num quantity})> grants,
) {
  var probe = save;
  for (final grant in grants) {
    if (!canFitItemQuantity(probe, grant.itemId, grant.quantity, null, false, db)) {
      return false;
    }
    probe = addItemsToInventory(probe, grant.itemId, grant.quantity, null, false, db).save;
  }
  return true;
}

num _rollInclusive(num Function() random, int min, int max) {
  return min + (random() * (max - min + 1)).floor();
}

class LocationTimerCollectResult {
  const LocationTimerCollectResult({
    required this.ok,
    this.save,
    this.loot = const <LootGrant>[],
    this.xpGained = 0,
    this.skillId = '',
    this.reason = '',
  });

  final bool ok;
  final PlayerSave? save;
  final List<LootGrant> loot;
  final num xpGained;
  final String skillId;
  final String reason;
}

LocationTimerCollectResult collectLocationTimer(
  GameDatabase db,
  PlayerSave save,
  String locationId,
  String kind, {
  required num nowMs,
  num Function()? random,
}) {
  final rng = random ?? () => 0.5;
  final now = nowMs;
  final timer = timerAtLocationKind(save, locationId, kind);
  if (timer == null) {
    return const LocationTimerCollectResult(ok: false, reason: 'No timer at this location.');
  }
  if (!timerIsReady(timer, now)) {
    final remainSec = ((timerCompletesAtMs(timer) - now) / 1000).ceil();
    return LocationTimerCollectResult(ok: false, reason: 'Not ready yet (${remainSec}s left).');
  }

  final grants = <({String itemId, num quantity})>[];
  var xpGained = timer.xpReward;
  final skillId = timer.skillId;

  if (timer.kind == 'botany') {
    final outputId = timer.outputItemId;
    if (outputId == null) {
      return const LocationTimerCollectResult(
        ok: false,
        reason: 'Botany timer is missing its crop.',
      );
    }
    final planted = timer.outputQuantity > 0 ? timer.outputQuantity.round() : 1;
    final plantedCount = planted < 1 ? 1 : planted;
    var produceQty = 0;
    for (var i = 0; i < plantedCount; i++) {
      produceQty += _rollInclusive(rng, 1, 5).round();
    }
    grants.add((itemId: outputId, quantity: produceQty));
    var returned = 0;
    for (var i = 0; i < plantedCount; i++) {
      if (rng() < 0.5) returned += 1;
    }
    if (returned > 0) grants.add((itemId: timer.inputItemId, quantity: returned));
  } else if (timer.kind == 'fishing_pot') {
    final fishingLevel = getSkillProgress(save, 'SKL-0003').level;
    final rolled = _rollFishingPotLoot(timer.locationId, fishingLevel, rng);
    xpGained = 0;
    for (final row in rolled) {
      grants.add((itemId: row.itemId, quantity: row.quantity));
      xpGained += row.xp;
    }
    grants.add((itemId: timer.inputItemId, quantity: 1));
  } else {
    return LocationTimerCollectResult(ok: false, reason: 'Unknown timer kind.');
  }

  if (!_canFitTimerGrants(db, save, grants)) {
    return LocationTimerCollectResult(ok: false, reason: timerInventoryFullReasonFor(timer.kind));
  }

  var next = save.copyWith(
    locationTimers: _withoutLocationTimerKind(save.locationTimers, locationId, kind),
  );
  final loot = <LootGrant>[];
  for (final grant in grants) {
    next = addItemsToInventory(next, grant.itemId, grant.quantity, null, false, db).save;
    loot.add(
      LootGrant(
        itemId: grant.itemId,
        quantity: grant.quantity,
        displayName: _timerItemName(db, grant.itemId),
      ),
    );
  }

  next = applyXp(next, db, skillId, xpGained).save;
  next = creditLootTracker(next, 'timer', '$kind:$locationId', loot, 0, now);
  next = creditXpAwards(next, [(skillId: skillId, xp: xpGained)], now);

  return LocationTimerCollectResult(
    ok: true,
    save: next,
    loot: loot,
    xpGained: xpGained,
    skillId: skillId,
  );
}
