import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../production/inventory.dart';
import '../production/recipes.dart';
import '../quests/miniquests.dart';
import '../quests/quests.dart';
import '../save/generated/save_models.dart';
import '../skills/totals.dart';
import '../time.dart';
import 'assign_race.dart';
import 'races.dart';

const String vesperId = 'NPC-0016';
const String raceChangeMiniquestId = 'QST-0009';
const num raceChangeTotalLevel = 500;

class RaceChangeItemCost {
  const RaceChangeItemCost({required this.itemId, required this.quantity});

  final String itemId;
  final num quantity;
}

class RaceChangeCost {
  const RaceChangeCost({required this.gold, required this.items});

  final num gold;
  final List<RaceChangeItemCost> items;
}

/// Mid-level (30–55) costs. No gems or ruby. Human stays tuna and maple.
const Map<String, RaceChangeCost> raceChangeCosts = <String, RaceChangeCost>{
  'RACE-0001': RaceChangeCost(
    gold: 0,
    items: [
      RaceChangeItemCost(itemId: 'ITEM-0050', quantity: 40),
      RaceChangeItemCost(itemId: 'ITEM-0018', quantity: 40),
    ],
  ),
  'RACE-0002': RaceChangeCost(
    gold: 0,
    items: [
      RaceChangeItemCost(itemId: 'ITEM-0041', quantity: 20),
      RaceChangeItemCost(itemId: 'ITEM-0196', quantity: 20),
    ],
  ),
  'RACE-0003': RaceChangeCost(
    gold: 0,
    items: [
      RaceChangeItemCost(itemId: 'ITEM-0099', quantity: 15),
      RaceChangeItemCost(itemId: 'ITEM-0071', quantity: 10),
      RaceChangeItemCost(itemId: 'ITEM-0062', quantity: 15),
    ],
  ),
  'RACE-0004': RaceChangeCost(
    gold: 0,
    items: [
      RaceChangeItemCost(itemId: 'ITEM-0045', quantity: 20),
      RaceChangeItemCost(itemId: 'ITEM-0041', quantity: 15),
    ],
  ),
  'RACE-0005': RaceChangeCost(
    gold: 5000,
    items: [RaceChangeItemCost(itemId: 'ITEM-0077', quantity: 20)],
  ),
  'RACE-0006': RaceChangeCost(
    gold: 0,
    items: [
      RaceChangeItemCost(itemId: 'ITEM-0005', quantity: 60),
      RaceChangeItemCost(itemId: 'ITEM-0006', quantity: 20),
      RaceChangeItemCost(itemId: 'ITEM-0007', quantity: 20),
    ],
  ),
  'RACE-0007': RaceChangeCost(
    gold: 0,
    items: [
      RaceChangeItemCost(itemId: 'ITEM-0028', quantity: 40),
      RaceChangeItemCost(itemId: 'ITEM-0033', quantity: 20),
    ],
  ),
};

RaceChangeCost? raceChangeCostFor(String raceId) => raceChangeCosts[raceId];

bool raceChangeUnlocked(PlayerSave save) => totalLevel(save) >= raceChangeTotalLevel;

QuestRow? raceChangeQuest(GameDatabase db) => getQuest(db, raceChangeMiniquestId);

bool raceChangeReady(GameDatabase db, PlayerSave save, num nowMs) {
  if (!raceChangeUnlocked(save)) return false;
  final quest = raceChangeQuest(db);
  if (quest == null) return false;
  final notes = quest['Notes'] is String ? quest['Notes']! as String : null;
  if (!meetsTotalLevelRequirement(save, notes)) return false;
  return miniquestCanRepeat(save, quest, nowMs);
}

String? raceChangeCooldownLabel(GameDatabase db, PlayerSave save, num nowMs) {
  final quest = raceChangeQuest(db);
  if (quest == null) return null;
  final readyAt = miniquestRepeatReadyAt(save, quest);
  if (readyAt == null || nowMs >= readyAt) return null;
  return 'Come back in ${formatDurationRemaining(readyAt - nowMs)}.';
}

class RaceChangeCostLine {
  const RaceChangeCostLine({
    required this.itemId,
    required this.name,
    required this.owned,
    required this.required,
  });

  final String? itemId;
  final String name;
  final num owned;
  final num required;

  Map<String, Object?> toJson() => <String, Object?>{
    'itemId': itemId,
    'name': name,
    'owned': owned,
    'required': required,
  };
}

class RaceChangeOption {
  const RaceChangeOption({
    required this.raceId,
    required this.name,
    required this.summary,
    required this.current,
    required this.goldRequired,
    required this.lines,
    required this.canAfford,
  });

  final String raceId;
  final String name;
  final String summary;
  final bool current;
  final num goldRequired;
  final List<RaceChangeCostLine> lines;
  final bool canAfford;

  Map<String, Object?> toJson() => <String, Object?>{
    'raceId': raceId,
    'name': name,
    'summary': summary,
    'current': current,
    'goldRequired': goldRequired,
    'lines': lines.map((line) => line.toJson()).toList(),
    'canAfford': canAfford,
  };
}

class RaceChangeOffer {
  const RaceChangeOffer({
    required this.questId,
    required this.ready,
    required this.cooldownEndsAt,
    required this.cooldownLabel,
    required this.warning,
    required this.prompt,
    required this.currentRaceId,
    required this.currentRaceName,
    required this.options,
  });

  final String questId;
  final bool ready;
  final String? cooldownEndsAt;
  final String? cooldownLabel;
  final String warning;
  final String prompt;
  final String? currentRaceId;
  final String? currentRaceName;
  final List<RaceChangeOption> options;

  Map<String, Object?> toJson() => <String, Object?>{
    'questId': questId,
    'ready': ready,
    'cooldownEndsAt': cooldownEndsAt,
    'cooldownLabel': cooldownLabel,
    'warning': warning,
    'prompt': prompt,
    'currentRaceId': currentRaceId,
    'currentRaceName': currentRaceName,
    'options': options.map((option) => option.toJson()).toList(),
  };
}

const String _raceChangeWarning =
    'The change lasts. Old gifts fade and new ones take their place. I can do this once a week — the weave needs time to settle.';

const String _raceChangePrompt =
    "You've grown into yourself, haven't you? I can change the blood you wear, if you still want a different kind of life. Bring what I ask.";

String _itemName(GameDatabase db, String itemId) {
  final name = db.items
      .firstWhereOrNull((row) => row.raw['Item ID'] == itemId)
      ?.raw['Display Name'];
  return name is String ? name : itemId;
}

List<RaceChangeCostLine> _costLines(GameDatabase db, PlayerSave save, RaceChangeCost cost) {
  final lines = <RaceChangeCostLine>[];
  if (cost.gold > 0) {
    lines.add(
      RaceChangeCostLine(itemId: null, name: 'Gold', owned: save.gold, required: cost.gold),
    );
  }
  for (final item in cost.items) {
    lines.add(
      RaceChangeCostLine(
        itemId: item.itemId,
        name: _itemName(db, item.itemId),
        owned: inventoryCount(save, item.itemId),
        required: item.quantity,
      ),
    );
  }
  return lines;
}

bool _canAfford(PlayerSave save, RaceChangeCost cost) {
  if (save.gold < cost.gold) return false;
  return cost.items.every((item) => inventoryCount(save, item.itemId) >= item.quantity);
}

RaceChangeOffer raceChangeOffer(GameDatabase db, PlayerSave save, [num? nowMs]) {
  final clock = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final quest = raceChangeQuest(db);
  final ready = raceChangeReady(db, save, clock);
  final readyAt = quest == null ? null : miniquestRepeatReadyAt(save, quest);
  final pitch = quest?['Pitch'];
  final options = races(db).map((race) {
    final raceId = jsString(race.raw['Race ID']);
    final cost = raceChangeCostFor(raceId) ?? const RaceChangeCost(gold: 0, items: []);
    final bonus = raceBonusSummaryLines(db, raceId).join(' · ');
    final description = race.raw['Description'];
    return RaceChangeOption(
      raceId: raceId,
      name: jsString(race.raw['Display Name']),
      summary: bonus.isNotEmpty ? bonus : (description is String ? description : ''),
      current: save.raceId == raceId,
      goldRequired: cost.gold,
      lines: _costLines(db, save, cost),
      canAfford: _canAfford(save, cost),
    );
  }).toList();
  return RaceChangeOffer(
    questId: raceChangeMiniquestId,
    ready: ready,
    cooldownEndsAt: readyAt != null && clock < readyAt ? isoFromMs(readyAt) : null,
    cooldownLabel: raceChangeCooldownLabel(db, save, clock),
    warning: _raceChangeWarning,
    prompt: pitch is String && pitch.isNotEmpty ? pitch : _raceChangePrompt,
    currentRaceId: save.raceId,
    currentRaceName: raceDisplayName(db, save.raceId),
    options: options,
  );
}

ChangeRaceResult changeRaceAtNpc(GameDatabase db, PlayerSave save, String raceId, [num? nowMs]) {
  final clock = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final npc = db.npcs.firstWhereOrNull((row) => row.raw['NPC ID'] == vesperId);
  if (npc == null) return const ChangeRaceResult.failed('Vesper is not here.');
  if (save.currentLocationId != npc.raw['Location ID']) {
    return const ChangeRaceResult.failed('Speak with Vesper in the Main Hall.');
  }
  if (save.raceId == null) {
    return const ChangeRaceResult.failed('Choose a race first.');
  }
  if (save.raceId == raceId) {
    return const ChangeRaceResult.failed('You already wear that blood.');
  }
  if (raceById(db, raceId) == null) {
    return const ChangeRaceResult.failed('Unknown race.');
  }
  if (!raceChangeUnlocked(save)) {
    return const ChangeRaceResult.failed('Vesper has nothing to say to you yet.');
  }
  final quest = raceChangeQuest(db);
  if (quest == null) {
    return const ChangeRaceResult.failed('This work is not ready.');
  }
  if (!miniquestCanRepeat(save, quest, clock)) {
    return ChangeRaceResult.failed(
      raceChangeCooldownLabel(db, save, clock) ?? 'The last change is still settling.',
    );
  }

  final cost = raceChangeCostFor(raceId);
  if (cost == null) {
    return const ChangeRaceResult.failed('Vesper will not weave that shape.');
  }
  if (save.gold < cost.gold) {
    return ChangeRaceResult.failed('Need ${jsLocaleNumber(cost.gold)} gold.');
  }
  final spentItems = cost.items.isEmpty
      ? save
      : removeIngredients(
          save,
          cost.items
              .map((item) => RecipeIngredient(itemId: item.itemId, quantity: item.quantity))
              .toList(),
        );
  if (spentItems == null) {
    return const ChangeRaceResult.failed('You do not have what the weave asks.');
  }
  final spentGold = spentItems.copyWith(gold: spentItems.gold - cost.gold);
  final assigned = assignRace(db, spentGold, raceId);
  if (!assigned.ok) {
    return ChangeRaceResult.failed(assigned.reason ?? 'Unknown race.');
  }
  final next = recordMiniquestCompletion(assigned.save!, raceChangeMiniquestId, clock);
  final name = raceDisplayName(db, raceId) ?? raceId;
  return ChangeRaceResult.ok(
    next,
    'There. Walk as $name now. The world will treat you accordingly.',
  );
}

class ChangeRaceResult {
  const ChangeRaceResult.ok(this.save, this.message) : reason = null;

  const ChangeRaceResult.failed(this.reason) : save = null, message = null;

  final PlayerSave? save;
  final String? message;
  final String? reason;

  bool get ok => reason == null;
}
