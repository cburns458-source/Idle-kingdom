import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/rewards.dart';
import '../activity/xp.dart';
import '../inventory/add_items.dart';
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

const String huntingTrapItemId = 'ITEM-0346';
const String fishingTrapItemId = 'ITEM-0347';

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

const Set<String> huntingTrapLocations = <String>{'LOC-0008', 'LOC-0009'};
const Set<String> fishingTrapLocations = <String>{'LOC-0003', 'LOC-0004'};

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
  if (kind != 'botany' && kind != 'hunting_trap' && kind != 'fishing_trap') return null;
  return (kind: kind, locationId: locationId);
}

/// Marks Botany / hunting / fishing spots at [locationId] as discovered when the
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
  if (huntingTrapLocations.contains(locationId)) add('hunting_trap');
  if (fishingTrapLocations.contains(locationId)) add('fishing_trap');
  if (!changed) return save;
  return save.copyWith(discoveredTimerSpotIds: discovered.toList());
}

num timerCompletesAtMs(LocationTimer timer) {
  return DateTime.parse(timer.startedAt).millisecondsSinceEpoch + timer.durationMs;
}

bool timerIsReady(LocationTimer timer, [num? nowMs]) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  return now >= timerCompletesAtMs(timer);
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
  num? nowMs,
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
  final started = DateTime.fromMillisecondsSinceEpoch(
    (nowMs ?? DateTime.now().millisecondsSinceEpoch).round(),
  ).toIso8601String();
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
  num? nowMs,
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

({bool ok, String? kind, String reason}) canPlaceTrap(
  GameDatabase db,
  PlayerSave save,
  String trapItemId, {
  String? locationId,
}) {
  final loc = locationId ?? save.currentLocationId;
  if (trapItemId == huntingTrapItemId) {
    if (!huntingTrapLocations.contains(loc)) {
      return (
        ok: false,
        kind: null,
        reason: 'Hunting traps only work in the Kingswoods and Meadow.',
      );
    }
    if (timerAtLocationKind(save, loc, 'hunting_trap') != null) {
      return (ok: false, kind: null, reason: 'A hunting trap is already set here.');
    }
    final have = save.inventory
        .where((stack) => stack.itemId == trapItemId)
        .fold<num>(0, (sum, stack) => sum + stack.quantity);
    if (have < 1) return (ok: false, kind: null, reason: 'You do not have that trap.');
    return (ok: true, kind: 'hunting_trap', reason: '');
  }
  if (trapItemId == fishingTrapItemId) {
    if (!fishingTrapLocations.contains(loc)) {
      return (
        ok: false,
        kind: null,
        reason: 'Fishing traps only work at the Goblin Camp and Docks.',
      );
    }
    if (timerAtLocationKind(save, loc, 'fishing_trap') != null) {
      return (ok: false, kind: null, reason: 'A fishing trap is already set here.');
    }
    final have = save.inventory
        .where((stack) => stack.itemId == trapItemId)
        .fold<num>(0, (sum, stack) => sum + stack.quantity);
    if (have < 1) return (ok: false, kind: null, reason: 'You do not have that trap.');
    return (ok: true, kind: 'fishing_trap', reason: '');
  }
  return (ok: false, kind: null, reason: 'That is not a placeable trap.');
}

({bool ok, PlayerSave? save, String reason}) placeTrap(
  GameDatabase db,
  PlayerSave save,
  String trapItemId, {
  num? nowMs,
}) {
  final loc = save.currentLocationId;
  final gate = canPlaceTrap(db, save, trapItemId, locationId: loc);
  if (!gate.ok) return (ok: false, save: null, reason: gate.reason);
  final removed = removeIngredients(save, [RecipeIngredient(itemId: trapItemId, quantity: 1)]);
  if (removed == null) return (ok: false, save: null, reason: 'You do not have that trap.');
  final kind = gate.kind!;
  final skillId = kind == 'hunting_trap' ? 'SKL-0005' : 'SKL-0003';
  final started = DateTime.fromMillisecondsSinceEpoch(
    (nowMs ?? DateTime.now().millisecondsSinceEpoch).round(),
  ).toIso8601String();
  final timer = LocationTimer(
    locationId: loc,
    kind: kind,
    inputItemId: trapItemId,
    outputItemId: null,
    outputQuantity: 1,
    skillId: skillId,
    xpReward: kind == 'hunting_trap' ? 200 : 150,
    startedAt: started,
    durationMs: trapDurationMs,
  );
  return (
    ok: true,
    save: discoverTimerSpotsForLocation(
      removed.copyWith(
        locationTimers: [..._withoutLocationTimerKind(removed.locationTimers, loc, kind), timer],
      ),
      loc,
    ),
    reason: '',
  );
}

const Map<String, List<({String itemId, num weight, num xp})>> _trapLoot =
    <String, List<({String itemId, num weight, num xp})>>{
      'LOC-0008': [
        (itemId: 'ITEM-0053', weight: 50, xp: 200),
        (itemId: 'ITEM-0055', weight: 30, xp: 350),
        (itemId: 'ITEM-0052', weight: 20, xp: 180),
      ],
      'LOC-0009': [
        (itemId: 'ITEM-0052', weight: 45, xp: 180),
        (itemId: 'ITEM-0193', weight: 45, xp: 180),
        (itemId: 'ITEM-0053', weight: 10, xp: 200),
      ],
      'LOC-0003': [
        (itemId: 'ITEM-0047', weight: 50, xp: 120),
        (itemId: 'ITEM-0048', weight: 35, xp: 200),
        (itemId: 'ITEM-0049', weight: 15, xp: 300),
      ],
      'LOC-0004': [
        (itemId: 'ITEM-0050', weight: 40, xp: 350),
        (itemId: 'ITEM-0049', weight: 35, xp: 300),
        (itemId: 'ITEM-0048', weight: 25, xp: 200),
      ],
    };

({String itemId, num xp})? _rollTrapLoot(String locationId, num Function() random) {
  final table = _trapLoot[locationId];
  if (table == null || table.isEmpty) return null;
  final total = table.fold<num>(0, (sum, row) => sum + row.weight);
  var roll = random() * total;
  for (final row in table) {
    roll -= row.weight;
    if (roll <= 0) return (itemId: row.itemId, xp: row.xp);
  }
  final last = table.last;
  return (itemId: last.itemId, xp: last.xp);
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
  num? nowMs,
  num Function()? random,
}) {
  final rng = random ?? () => 0.5;
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final timer = timerAtLocationKind(save, locationId, kind);
  if (timer == null) {
    return const LocationTimerCollectResult(ok: false, reason: 'No timer at this location.');
  }
  if (!timerIsReady(timer, now)) {
    final remainSec = ((timerCompletesAtMs(timer) - now) / 1000).ceil();
    return LocationTimerCollectResult(ok: false, reason: 'Not ready yet (${remainSec}s left).');
  }

  var next = save.copyWith(
    locationTimers: _withoutLocationTimerKind(save.locationTimers, locationId, kind),
  );
  final loot = <LootGrant>[];
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
    final granted = addItemsToInventory(next, outputId, produceQty, null, false, db);
    next = granted.save;
    final produceName = db.items
        .firstWhereOrNull((item) => item.raw['Item ID'] == outputId)
        ?.raw['Display Name'];
    loot.add(
      LootGrant(
        itemId: outputId,
        quantity: produceQty,
        displayName: produceName is String ? produceName : outputId,
      ),
    );
    var returned = 0;
    for (var i = 0; i < plantedCount; i++) {
      if (rng() < 0.5) returned += 1;
    }
    if (returned > 0) {
      final back = addItemsToInventory(next, timer.inputItemId, returned, null, false, db);
      next = back.save;
      final seedName = db.items
          .firstWhereOrNull((item) => item.raw['Item ID'] == timer.inputItemId)
          ?.raw['Display Name'];
      loot.add(
        LootGrant(
          itemId: timer.inputItemId,
          quantity: returned,
          displayName: seedName is String ? seedName : timer.inputItemId,
        ),
      );
    }
  } else {
    final rolled = _rollTrapLoot(timer.locationId, rng);
    if (rolled != null) {
      final granted = addItemsToInventory(next, rolled.itemId, 1, null, false, db);
      next = granted.save;
      xpGained = rolled.xp;
      final name = db.items
          .firstWhereOrNull((item) => item.raw['Item ID'] == rolled.itemId)
          ?.raw['Display Name'];
      loot.add(
        LootGrant(
          itemId: rolled.itemId,
          quantity: 1,
          displayName: name is String ? name : rolled.itemId,
        ),
      );
    }
    next = addItemsToInventory(next, timer.inputItemId, 1, null, false, db).save;
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
