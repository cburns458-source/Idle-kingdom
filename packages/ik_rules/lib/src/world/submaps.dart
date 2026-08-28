import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import 'constants.dart';

String _mapTypeOf(GameDatabase db, String mapId) {
  final map = db.maps.firstWhereOrNull((row) => row.raw['Map ID'] == mapId);
  final mapType = map?.raw['Map Type'];
  return mapType is String ? mapType : '';
}

/// True when Map Type marks a sub-map (unlimited; not hardcapped to cave/castle).
bool isSubMapType(Object? mapType) => lowerOrEmpty(mapType).contains('sub-map');

bool isSubMap(GameDatabase db, String? mapId) {
  if (isBlank(mapId) || mapId == mainMapId || isFutureRegionMapId(mapId)) return false;
  if (isSubMapType(_mapTypeOf(db, mapId!))) return true;
  // Fallback: any map that hosts parented child locations.
  return db.locations.any(
    (location) =>
        location.raw['Map ID'] == mapId &&
        isNotBlank(location.raw['Parent Location ID'] as String?),
  );
}

bool isSubMapGateway(LocationRow location) {
  return lowerOrEmpty(location.raw['Location Type']).contains('sub-map gateway');
}

/// Landing node written on a gateway row, if any.
String? landingLocationIdFor(LocationRow location) {
  final raw = location.raw['Landing Location ID'];
  if (raw is! String) return null;
  final id = raw.trim();
  return id.isEmpty ? null : id;
}

/// World-map Travel to a gateway lands on that gateway's child-map node.
///
/// Standing on a gateway and choosing it again does the same, so Enter still
/// works if someone is already on an inaccessible entrance. Intra-submap
/// travel is left alone.
String resolveSubMapTravelDestination(
  GameDatabase db,
  String selectedLocationId,
  String browseMapId, [
  String? currentLocationId,
]) {
  final dest = db.locations.firstWhereOrNull((row) => row.raw['Location ID'] == selectedLocationId);
  if (dest == null) return selectedLocationId;
  final landing = landingLocationIdFor(dest);
  if (landing == null) return selectedLocationId;
  if (!db.locations.any((row) => row.raw['Location ID'] == landing)) {
    return selectedLocationId;
  }
  final fromMain = browseMapId == mainMapId;
  final standingOnGateway = (currentLocationId ?? selectedLocationId) == selectedLocationId;
  if (!fromMain && !standingOnGateway) return selectedLocationId;
  return landing;
}

/// Where a walk onto [mapId] should start when the player is not on that map.
String? entryLandingLocationIdForMap(GameDatabase db, String mapId) {
  final gatewayId = gatewayLocationIdForSubMap(db, mapId);
  if (gatewayId == null) return null;
  final gateway = db.locations.firstWhereOrNull((row) => row.raw['Location ID'] == gatewayId);
  if (gateway == null) return gatewayId;
  return landingLocationIdFor(gateway) ?? gatewayId;
}

/// Child Map ID for a gateway location, if any.
String? subMapIdForGateway(GameDatabase db, String gatewayLocationId) {
  final child = db.locations.firstWhereOrNull(
    (location) => location.raw['Parent Location ID'] == gatewayLocationId,
  );
  final mapId = child?.raw['Map ID'];
  return mapId is String ? mapId : null;
}

String? gatewayLocationIdForSubMap(GameDatabase db, String mapId) {
  for (final location in db.locations) {
    if (location.raw['Map ID'] != mapId) continue;
    final parentId = location.raw['Parent Location ID'];
    if (parentId is String && parentId.isNotEmpty) return parentId;
  }
  return null;
}

String subMapDisplayName(GameDatabase db, String mapId) {
  final map = db.maps.firstWhereOrNull((row) => row.raw['Map ID'] == mapId);
  final displayName = map?.raw['Display Name'];
  return displayName is String ? displayName : 'Sub-map';
}

/// Drops a trailing "Map" so "Town Map" reads as "Town".
String shortSubMapName(GameDatabase db, String mapId) {
  final name = subMapDisplayName(db, mapId);
  final trimmed = name.replaceAll(RegExp(r'\s+map$', caseSensitive: false), '').trim();
  return trimmed.isEmpty ? name : trimmed;
}

/// Enter-button label for a gateway location.
String? enterSubMapLabel(GameDatabase db, LocationRow gateway) {
  final mapId = subMapIdForGateway(db, jsString(gateway.raw['Location ID']));
  if (mapId == null) return null;
  return 'Enter ${shortSubMapName(db, mapId)}';
}

/// Back-button label for a location that sits on a sub-map.
String? backToSubMapLabel(GameDatabase db, LocationRow location) {
  final rawMapId = location.raw['Map ID'];
  final mapId = rawMapId is String ? rawMapId : mainMapId;
  if (!isSubMap(db, mapId) || isSubMapGateway(location)) return null;
  return 'Back to ${shortSubMapName(db, mapId)}';
}

/// Notes marker: location stays hidden/locked until unlockedLocationIds includes it.
bool locationRequiresUnlock(LocationRow location) {
  return lowerOrEmpty(location.raw['Notes']).contains('requires_unlock');
}

bool isLocationUnlocked(
  List<String> unlockedLocationIds,
  LocationRow location, [
  String? currentLocationId,
]) {
  if (!locationRequiresUnlock(location)) return true;
  final locationId = location.raw['Location ID'];
  if (currentLocationId != null && currentLocationId == locationId) return true;
  return unlockedLocationIds.contains(locationId);
}

List<String> unlockLocation(List<String> unlockedLocationIds, String locationId) {
  if (unlockedLocationIds.contains(locationId)) return unlockedLocationIds;
  return [...unlockedLocationIds, locationId];
}

/// Keep the west / east map constants usable without treating them as submaps.
bool isBrowsableEmptyMap(String mapId) => mapId == westMapId || mapId == eastMapId;
