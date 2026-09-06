import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/rewards.dart';
import '../activity/xp.dart';
import '../inventory/add_items.dart';
import '../production/inventory.dart';
import '../production/recipes.dart';
import '../quests/quests.dart';
import '../save/generated/save_models.dart';

const String botanySkillId = 'SKL-0014';
const String thieverySkillId = 'SKL-0015';
const String glovesSlotId = 'SLOT-0007';
const String courtyardLocationId = 'LOC-0014';
const String grandFeastQuestId = 'QST-0001';

const String huntingTrapItemId = 'ITEM-0346';
const String fishingTrapItemId = 'ITEM-0347';

const Set<String> huntingTrapLocations = <String>{'LOC-0008', 'LOC-0009'};
const Set<String> fishingTrapLocations = <String>{'LOC-0003', 'LOC-0004'};

const num trapDurationMs = 5 * 60 * 1000;

class BotanySeedSpec {
  const BotanySeedSpec({
    required this.outputItemId,
    required this.growSeconds,
    required this.xp,
  });

  final String outputItemId;
  final num growSeconds;
  final num xp;
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
  if (output == null || grow <= 0) return null;
  return BotanySeedSpec(outputItemId: output, growSeconds: grow, xp: xp < 0 ? 0 : xp);
}

bool inventoryHasAnyBotanySeed(GameDatabase db, PlayerSave save) {
  return save.inventory.any((stack) => stack.quantity > 0 && isBotanySeedItem(db, stack.itemId));
}

LocationTimer? timerAtLocation(PlayerSave save, String locationId) {
  return save.locationTimers.firstWhereOrNull((timer) => timer.locationId == locationId);
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

({bool ok, String reason}) canPlantBotanySeed(
  GameDatabase db,
  PlayerSave save,
  String seedItemId, {
  String? locationId,
}) {
  final loc = locationId ?? save.currentLocationId;
  if (loc != courtyardLocationId) {
    return (ok: false, reason: 'Botany plots are only in the Courtyard.');
  }
  if (!courtyardBotanyUnlocked(save)) {
    return (ok: false, reason: 'Complete The Grand Feast to unlock the Courtyard plot.');
  }
  if (timerAtLocation(save, loc) != null) {
    return (ok: false, reason: 'This location already has a timer running.');
  }
  if (parseBotanySeedSpec(db, seedItemId) == null) {
    return (ok: false, reason: 'That item cannot be planted.');
  }
  final have = save.inventory
      .where((stack) => stack.itemId == seedItemId)
      .fold<num>(0, (sum, stack) => sum + stack.quantity);
  if (have < 1) return (ok: false, reason: 'You do not have that seed.');
  return (ok: true, reason: '');
}

({bool ok, PlayerSave? save, String reason}) plantBotanySeed(
  GameDatabase db,
  PlayerSave save,
  String seedItemId, {
  num? nowMs,
}) {
  final loc = save.currentLocationId;
  final gate = canPlantBotanySeed(db, save, seedItemId, locationId: loc);
  if (!gate.ok) return (ok: false, save: null, reason: gate.reason);
  final spec = parseBotanySeedSpec(db, seedItemId)!;
  final removed = removeIngredients(save, [RecipeIngredient(itemId: seedItemId, quantity: 1)]);
  if (removed == null) return (ok: false, save: null, reason: 'You do not have that seed.');
  final started = DateTime.fromMillisecondsSinceEpoch(
    (nowMs ?? DateTime.now().millisecondsSinceEpoch).round(),
  ).toIso8601String();
  final timer = LocationTimer(
    locationId: loc,
    kind: 'botany',
    inputItemId: seedItemId,
    outputItemId: spec.outputItemId,
    outputQuantity: 1,
    skillId: botanySkillId,
    xpReward: spec.xp,
    startedAt: started,
    durationMs: spec.growSeconds * 1000,
  );
  return (
    ok: true,
    save: removed.copyWith(
      locationTimers: [
        ...removed.locationTimers.where((row) => row.locationId != loc),
        timer,
      ],
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
    if (parseBotanySeedSpec(db, stack.itemId) == null) continue;
    return plantBotanySeed(db, save, stack.itemId, nowMs: nowMs);
  }
  return (ok: false, save: null, reason: 'You have no plantable seeds or saplings.');
}

({bool ok, String? kind, String reason}) canPlaceTrap(
  GameDatabase db,
  PlayerSave save,
  String trapItemId, {
  String? locationId,
}) {
  final loc = locationId ?? save.currentLocationId;
  if (timerAtLocation(save, loc) != null) {
    return (ok: false, kind: null, reason: 'This location already has a timer running.');
  }
  final have = save.inventory
      .where((stack) => stack.itemId == trapItemId)
      .fold<num>(0, (sum, stack) => sum + stack.quantity);
  if (have < 1) return (ok: false, kind: null, reason: 'You do not have that trap.');
  if (trapItemId == huntingTrapItemId) {
    if (!huntingTrapLocations.contains(loc)) {
      return (ok: false, kind: null, reason: 'Hunting traps only work in the Kingswoods and Meadow.');
    }
    return (ok: true, kind: 'hunting_trap', reason: '');
  }
  if (trapItemId == fishingTrapItemId) {
    if (!fishingTrapLocations.contains(loc)) {
      return (ok: false, kind: null, reason: 'Fishing traps only work at the Goblin Camp and Docks.');
    }
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
    save: removed.copyWith(
      locationTimers: [
        ...removed.locationTimers.where((row) => row.locationId != loc),
        timer,
      ],
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
  String locationId, {
  num? nowMs,
  num Function()? random,
}) {
  final rng = random ?? () => 0.5;
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final timer = timerAtLocation(save, locationId);
  if (timer == null) {
    return const LocationTimerCollectResult(ok: false, reason: 'No timer at this location.');
  }
  if (!timerIsReady(timer, now)) {
    final remainSec = ((timerCompletesAtMs(timer) - now) / 1000).ceil();
    return LocationTimerCollectResult(ok: false, reason: 'Not ready yet (${remainSec}s left).');
  }

  var next = save.copyWith(
    locationTimers: save.locationTimers.where((row) => row.locationId != locationId).toList(),
  );
  final loot = <LootGrant>[];
  var xpGained = timer.xpReward;
  final skillId = timer.skillId;

  if (timer.kind == 'botany') {
    final outputId = timer.outputItemId;
    if (outputId == null) {
      return const LocationTimerCollectResult(ok: false, reason: 'Botany timer is missing its crop.');
    }
    final granted = addItemsToInventory(next, outputId, timer.outputQuantity, null, false, db);
    next = granted.save;
    if (granted.added > 0) {
      final name = db.items
              .firstWhereOrNull((item) => item.raw['Item ID'] == outputId)
              ?.raw['Display Name'];
      loot.add(
        LootGrant(
          itemId: outputId,
          quantity: granted.added,
          displayName: name is String ? name : outputId,
        ),
      );
    }
  } else {
    final rolled = _rollTrapLoot(locationId, rng);
    if (rolled != null) {
      final granted = addItemsToInventory(next, rolled.itemId, 1, null, false, db);
      next = granted.save;
      xpGained = rolled.xp;
      if (granted.added > 0) {
        final name = db.items
                .firstWhereOrNull((item) => item.raw['Item ID'] == rolled.itemId)
                ?.raw['Display Name'];
        loot.add(
          LootGrant(
            itemId: rolled.itemId,
            quantity: granted.added,
            displayName: name is String ? name : rolled.itemId,
          ),
        );
      }
    }
    next = addItemsToInventory(next, timer.inputItemId, 1, null, false, db).save;
  }

  if (xpGained > 0) {
    next = applyXp(next, db, skillId, xpGained).save;
  }

  return LocationTimerCollectResult(
    ok: true,
    save: next,
    loot: loot,
    xpGained: xpGained,
    skillId: skillId,
  );
}
