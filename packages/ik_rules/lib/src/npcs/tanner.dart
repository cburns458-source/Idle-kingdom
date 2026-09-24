import 'package:ik_content/ik_content.dart';

import '../inventory/add_items.dart';
import '../js_compat.dart';
import '../production/recipes.dart';
import '../save/generated/save_models.dart';

const String leatherItemId = 'ITEM-0045';
const num tannerGoldPerLeather = 2;
const String craftingWorkshopFacilityId = 'FAC-0003';

/// Leather produced per hide, keyed by Internal Key.
const Map<String, num> hideLeatherYields = <String, num>{
  'cow_hide': 3,
  'goat_hide': 2,
  'elk_hide': 3,
  'boar_hide': 2,
  'great_stag_hide': 4,
  'moonhorn_hide': 4,
};

class TannerHideOption {
  const TannerHideOption({
    required this.itemId,
    required this.displayName,
    required this.owned,
    required this.leatherEach,
  });

  final String itemId;
  final String displayName;
  final num owned;
  final num leatherEach;

  Map<String, Object?> toJson() => <String, Object?>{
    'itemId': itemId,
    'displayName': displayName,
    'owned': owned,
    'leatherEach': leatherEach,
  };
}

class TannerOffer {
  const TannerOffer({
    required this.prompt,
    required this.feeEach,
    required this.leatherItemId,
    required this.hides,
  });

  final String prompt;
  final num feeEach;
  final String leatherItemId;
  final List<TannerHideOption> hides;

  Map<String, Object?> toJson() => <String, Object?>{
    'prompt': prompt,
    'feeEach': feeEach,
    'leatherItemId': leatherItemId,
    'hides': hides.map((hide) => hide.toJson()).toList(),
  };
}

class TannerQuote {
  const TannerQuote({required this.leather, required this.gold, required this.hideCount});

  final num leather;
  final num gold;
  final num hideCount;
}

class TannerJobResult {
  const TannerJobResult.ok({required this.save, required this.message}) : reason = null;

  const TannerJobResult.failed(this.reason) : save = null, message = null;

  final PlayerSave? save;
  final String? message;
  final String? reason;

  bool get ok => reason == null;
}

num _stackQuantity(InventoryStack stack) {
  return jsNumber(stack.quantity).floor().clamp(0, 1 << 30);
}

num _quantityIn(Iterable<InventoryStack> stacks, String itemId) {
  var sum = 0.0;
  for (final stack in stacks) {
    if (stack.itemId != itemId) continue;
    sum += _stackQuantity(stack);
  }
  return sum;
}

num _ownedQuantity(PlayerSave save, String itemId) {
  return _quantityIn(save.inventory, itemId) + _quantityIn(save.bank, itemId);
}

({List<InventoryStack> stacks, num remaining}) _takeFromStacks(
  List<InventoryStack> stacks,
  String itemId,
  num need,
) {
  var remaining = need;
  final next = <InventoryStack>[];
  for (final stack in stacks) {
    if (stack.itemId != itemId || remaining <= 0) {
      next.add(stack);
      continue;
    }
    final have = _stackQuantity(stack);
    final take = have < remaining ? have : remaining;
    remaining -= take;
    final left = have - take;
    if (left > 0) next.add(stack.copyWith(quantity: left));
  }
  return (stacks: next, remaining: remaining);
}

PlayerSave? _removeHides(PlayerSave save, List<RecipeIngredient> ingredients) {
  var inventory = [...save.inventory];
  var bank = [...save.bank];
  for (final row in ingredients) {
    final fromBag = _takeFromStacks(inventory, row.itemId, row.quantity);
    inventory = fromBag.stacks;
    if (fromBag.remaining <= 0) continue;
    final fromBank = _takeFromStacks(bank, row.itemId, fromBag.remaining);
    if (fromBank.remaining > 0) return null;
    bank = fromBank.stacks;
  }
  return save.copyWith(inventory: inventory, bank: bank);
}

String? _hideInternalKey(ItemRow item) {
  final key = item.internalKey;
  if (key.endsWith('_hide')) return key;
  return null;
}

bool isTannerNpc(NpcRow? npc) {
  if (npc == null) return false;
  return jsString(npc.raw['Role']).toLowerCase() == 'tanner';
}

bool isCraftingWorkshopLocation(GameDatabase db, String locationId) {
  return db.facilities.any((facility) {
    if (facility.locationId != locationId) return false;
    if (projectFacilityIdForLookup(facility.facilityId) == craftingWorkshopFacilityId) {
      return true;
    }
    return facility.internalKey.endsWith('crafting_workshop');
  });
}

NpcRow? tannerNpcAtLocation(GameDatabase db, String locationId) {
  if (!isCraftingWorkshopLocation(db, locationId)) return null;
  for (final npc in db.npcs) {
    if (npc.locationId == locationId && isTannerNpc(npc)) return npc;
  }
  return NpcRow(<String, Object?>{
    'NPC ID': 'NPC-TANNER-$locationId',
    'Internal Key': 'tanner_${locationId.toLowerCase()}',
    'Display Name': 'Tanner',
    'Location ID': locationId,
    'Role': 'Tanner',
    'Status': 'Planned',
    'Release Phase': 'Launch',
    'Description': 'Tans animal hides into leather at the crafting workshop, for a small gold fee.',
    'Notes': 'Trades hides for leather. 2 gold per leather produced.',
  });
}

num leatherPerHide(ItemRow item) {
  final key = _hideInternalKey(item);
  if (key == null) return 0;
  final listed = hideLeatherYields[key];
  if (listed != null && listed > 0) return listed;
  return 1;
}

List<TannerHideOption> tannerHideOptions(GameDatabase db, PlayerSave save) {
  final options = <TannerHideOption>[];
  for (final item in db.items) {
    final leatherEach = leatherPerHide(item);
    if (leatherEach <= 0) continue;
    final owned = _ownedQuantity(save, item.itemId);
    if (owned <= 0) continue;
    options.add(
      TannerHideOption(
        itemId: item.itemId,
        displayName: item.displayName,
        owned: owned,
        leatherEach: leatherEach,
      ),
    );
  }
  options.sort((a, b) => a.displayName.compareTo(b.displayName));
  return options;
}

TannerOffer tannerOffer(GameDatabase db, PlayerSave save) {
  final hides = tannerHideOptions(db, save);
  return TannerOffer(
    prompt: hides.isEmpty
        ? 'Bring me animal hides and a little gold. I will tan them into leather.'
        : 'Which hides should I tan?',
    feeEach: tannerGoldPerLeather,
    leatherItemId: leatherItemId,
    hides: hides,
  );
}

TannerQuote quoteTannerJob(GameDatabase db, PlayerSave save, Map<String, num> quantities) {
  var leather = 0.0;
  var hideCount = 0.0;
  final yields = <String, num>{for (final item in db.items) item.itemId: leatherPerHide(item)};
  for (final entry in quantities.entries) {
    final want = jsNumber(entry.value).floor();
    if (want <= 0) continue;
    final take = want < _ownedQuantity(save, entry.key) ? want : _ownedQuantity(save, entry.key);
    final each = yields[entry.key] ?? 0;
    if (each <= 0 || take <= 0) continue;
    hideCount += take;
    leather += take * each;
  }
  return TannerQuote(leather: leather, gold: leather * tannerGoldPerLeather, hideCount: hideCount);
}

TannerJobResult confirmTannerJob(
  GameDatabase db,
  PlayerSave save,
  NpcRow npc,
  Map<String, num> quantities,
) {
  if (!isTannerNpc(npc)) {
    return const TannerJobResult.failed('This person does not tan hides.');
  }
  if (save.currentLocationId != npc.locationId || !isCraftingWorkshopLocation(db, npc.locationId)) {
    return const TannerJobResult.failed('Speak with the tanner at a crafting workshop.');
  }

  final quote = quoteTannerJob(db, save, quantities);
  if (quote.leather <= 0) {
    return const TannerJobResult.failed('Select some hides first.');
  }
  if (save.gold < quote.gold) {
    return TannerJobResult.failed('Need ${jsLocaleNumber(quote.gold)} gold.');
  }

  final yields = <String, num>{for (final item in db.items) item.itemId: leatherPerHide(item)};
  final ingredients = <RecipeIngredient>[];
  for (final entry in quantities.entries) {
    final want = jsNumber(entry.value).floor();
    if (want <= 0) continue;
    final take = want < _ownedQuantity(save, entry.key) ? want : _ownedQuantity(save, entry.key);
    if (take <= 0 || (yields[entry.key] ?? 0) <= 0) continue;
    ingredients.add(RecipeIngredient(itemId: entry.key, quantity: take));
  }

  final spentItems = _removeHides(save, ingredients);
  if (spentItems == null) {
    return const TannerJobResult.failed('You do not have those hides.');
  }
  final spentGold = spentItems.copyWith(gold: spentItems.gold - quote.gold);
  final granted = addItemToInventoryExact(spentGold, leatherItemId, quote.leather);
  if (!granted.ok) {
    return TannerJobResult.failed(granted.reason ?? 'Inventory is full.');
  }

  final hideWord = quote.hideCount == 1 ? 'hide' : 'hides';
  return TannerJobResult.ok(
    save: granted.save!,
    message:
        'Tanned ${quote.hideCount.toInt()} $hideWord into ${quote.leather.toInt()} leather for ${quote.gold.toInt()} gold.',
  );
}
