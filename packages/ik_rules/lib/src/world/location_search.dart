import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../inventory/add_items.dart';
import '../js_compat.dart';
import '../save/generated/save_models.dart';
import '../time.dart';

/// Search spots (for example "Search around the entrance") at a location.
List<LocationSearchRow> locationSearchesAt(GameDatabase db, String locationId) {
  return db.locationSearches.where((row) => row.raw['Location ID'] == locationId).toList();
}

num? _lastClaimedAtMs(PlayerSave save, String searchId) {
  final claimedAt = save.locationSearchClaims[searchId];
  if (claimedAt == null || claimedAt.isEmpty) return null;
  final parsed = jsDateParse(claimedAt);
  return parsed.isFinite ? parsed : null;
}

/// Milliseconds left before this spot can be searched again; 0 when ready.
num locationSearchCooldownRemainingMs(PlayerSave save, LocationSearchRow search, num nowMs) {
  final lastClaimed = _lastClaimedAtMs(save, jsString(search.raw['Search ID']));
  if (lastClaimed == null) return 0;
  final cooldownMs = math.max(0, jsNumberOrZero(search.raw['Cooldown Hours'])) * 60 * 60 * 1000;
  return math.max(0, lastClaimed + cooldownMs - nowMs);
}

bool canClaimLocationSearch(PlayerSave save, LocationSearchRow search, num nowMs) {
  return locationSearchCooldownRemainingMs(save, search, nowMs) <= 0;
}

class LocationSearchClaimResult {
  const LocationSearchClaimResult.ok({
    required this.save,
    required this.itemId,
    required this.itemName,
    required this.quantity,
  }) : ok = true,
       reason = null;

  const LocationSearchClaimResult.failed({required this.save, required this.reason})
    : ok = false,
      itemId = null,
      itemName = null,
      quantity = null;

  final bool ok;
  final PlayerSave save;
  final String? reason;
  final String? itemId;
  final String? itemName;
  final num? quantity;

  Map<String, Object?> toJson() => <String, Object?>{
    'ok': ok,
    'save': save.toJson(),
    if (reason != null) 'reason': reason,
    if (itemId != null) 'itemId': itemId,
    if (itemName != null) 'itemName': itemName,
    if (quantity != null) 'quantity': quantity,
  };
}

/// Grants the search reward and stamps the claim.
///
/// A spot still on cooldown, or a bag with no room, leaves the save untouched
/// and keeps the cooldown unspent so a full bag cannot waste the search.
LocationSearchClaimResult claimLocationSearch(
  GameDatabase db,
  PlayerSave save,
  String searchId,
  num nowMs,
) {
  final search = db.locationSearches.firstWhereOrNull((row) => row.raw['Search ID'] == searchId);
  if (search == null) {
    return LocationSearchClaimResult.failed(save: save, reason: 'Unknown search spot.');
  }
  if (!canClaimLocationSearch(save, search, nowMs)) {
    return LocationSearchClaimResult.failed(
      save: save,
      reason: 'Already searched here today. Come back later.',
    );
  }

  final rewardItemId = jsString(search.raw['Reward Item ID']);
  final rewardQuantity = jsNumberOrZero(search.raw['Reward Quantity']);
  final granted = addItemToInventoryExact(save, rewardItemId, rewardQuantity);
  if (!granted.ok) {
    return LocationSearchClaimResult.failed(save: save, reason: granted.reason);
  }

  final displayName = db.items
      .firstWhereOrNull((item) => item.raw['Item ID'] == rewardItemId)
      ?.raw['Display Name'];

  return LocationSearchClaimResult.ok(
    save: granted.save!.copyWith(
      locationSearchClaims: {...granted.save!.locationSearchClaims, searchId: isoFromMs(nowMs)},
    ),
    itemId: rewardItemId,
    itemName: displayName is String ? displayName : rewardItemId,
    quantity: rewardQuantity,
  );
}
