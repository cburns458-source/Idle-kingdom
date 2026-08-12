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

/// Enter-button label for a gateway location.
String? enterSubMapLabel(GameDatabase db, LocationRow gateway) {
  final mapId = subMapIdForGateway(db, jsString(gateway.raw['Location ID']));
  if (mapId == null) return null;
  final name = subMapDisplayName(db, mapId);
  // Prefer short CTA: "Enter Town Map" → "Enter Town" when name ends with Map.
  final trimmed = name.replaceAll(RegExp(r'\s+map$', caseSensitive: false), '').trim();
  return 'Enter ${trimmed.isEmpty ? name : trimmed}';
}

/// Notes marker: location stays hidden/locked until unlockedLocationIds includes it.
bool locationRequiresUnlock(LocationRow location) {
  return lowerOrEmpty(location.raw['Notes']).contains('requires_unlock');
}

bool isLocationUnlocked(List<String> unlockedLocationIds, LocationRow location) {
  if (!locationRequiresUnlock(location)) return true;
  return unlockedLocationIds.contains(location.raw['Location ID']);
}

List<String> unlockLocation(List<String> unlockedLocationIds, String locationId) {
  if (unlockedLocationIds.contains(locationId)) return unlockedLocationIds;
  return [...unlockedLocationIds, locationId];
}

/// Keep the west / east map constants usable without treating them as submaps.
bool isBrowsableEmptyMap(String mapId) => mapId == westMapId || mapId == eastMapId;
