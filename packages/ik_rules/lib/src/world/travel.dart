import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/transition.dart';
import '../combat/engine.dart';
import '../js_compat.dart';
import '../quests/progress.dart';
import '../save/generated/save_models.dart';
import 'constants.dart';
import 'map_label.dart';
import 'kingswoods_sling.dart';
import 'submaps.dart';

/// Travel is a menu button: destinations are instant, with no walk or mount delay.
num travelDurationMs(TravelConnectionRow? _) {
  return 0;
}

String getLocationMapId(LocationRow location) {
  final mapId = location.raw['Map ID'];
  return mapId is String ? mapId : mainMapId;
}

/// Map shown when browsing from the player's current location.
String resolveActiveMapId(GameDatabase db, LocationRow location) {
  final mapId = getLocationMapId(location);
  if (isSubMap(db, mapId)) return mapId;
  final childMap = subMapIdForGateway(db, jsString(location.raw['Location ID']));
  if (childMap != null) return childMap;
  return mainMapId;
}

bool _isTwoWay(TravelConnectionRow connection) {
  final direction = connection.raw['Direction'];
  return (direction is String ? direction : 'Two-way').toLowerCase().contains('two');
}

List<TravelConnectionRow> connectionsFrom(GameDatabase db, String fromLocationId) {
  return db.travelConnections.where((connection) {
    if (connection.raw['From Location ID'] == fromLocationId) return true;
    if (_isTwoWay(connection) && connection.raw['To Location ID'] == fromLocationId) return true;
    return false;
  }).toList();
}

TravelConnectionRow? findConnection(GameDatabase db, String fromLocationId, String toLocationId) {
  return db.travelConnections.firstWhereOrNull((connection) {
    if (connection.raw['From Location ID'] == fromLocationId &&
        connection.raw['To Location ID'] == toLocationId) {
      return true;
    }
    if (_isTwoWay(connection) &&
        connection.raw['From Location ID'] == toLocationId &&
        connection.raw['To Location ID'] == fromLocationId) {
      return true;
    }
    return false;
  });
}

/// Destinations selectable on a map.
///
/// The main map lists every location on it. A sub-map lists its own nodes plus
/// the gateway that leads back out, dropping nodes still locked for this save.
List<LocationRow> locationsForMapView(
  GameDatabase db,
  String mapId, [
  List<String> unlockedLocationIds = const <String>[],
  List<String> hiddenLocationIds = const <String>[],
]) {
  if (mapId == mainMapId) {
    return db.locations
        .where(
          (location) =>
              location.raw['Map ID'] == mainMapId && !locationHiddenOnMap(location, mapId),
        )
        .toList();
  }

  if (isBrowsableEmptyMap(mapId)) return <LocationRow>[];

  final gatewayId = gatewayLocationIdForSubMap(db, mapId);
  final gateway = gatewayId == null
      ? null
      : db.locations.firstWhereOrNull((location) => location.raw['Location ID'] == gatewayId);

  final merged = <String, LocationRow>{};
  for (final location in db.locations.where((row) => row.raw['Map ID'] == mapId)) {
    if (!isLocationUnlocked(unlockedLocationIds, location)) continue;
    final id = jsString(location.raw['Location ID']);
    if (hiddenLocationIds.contains(id)) continue;
    if (locationHiddenOnMap(location, mapId)) continue;
    merged[id] = location;
  }
  if (gateway != null && !locationHiddenOnMap(gateway, mapId)) {
    merged[jsString(gateway.raw['Location ID'])] = gateway;
  }
  return merged.values.toList();
}

bool canTravelTo(
  GameDatabase db,
  String fromLocationId,
  String toLocationId,
  String activeMapId, [
  List<String> unlockedLocationIds = const <String>[],
]) {
  if (fromLocationId == toLocationId) return false;
  if (isFutureHorizonLocation(toLocationId)) return false;
  final destination = db.locations.firstWhereOrNull(
    (location) => location.raw['Location ID'] == toLocationId,
  );
  if (destination == null) return false;
  if (!isLocationUnlocked(unlockedLocationIds, destination)) return false;

  if (activeMapId == mainMapId) {
    // World-map travel is allowed from anywhere, including sub-locations,
    // but future horizon gateways are browse-only.
    return destination.raw['Map ID'] == mainMapId && !isFutureHorizonLocation(toLocationId);
  }

  if (findConnection(db, fromLocationId, toLocationId) != null) return true;

  // Nodes shown together on the active sub-map are mutually reachable.
  return locationsForMapView(
    db,
    activeMapId,
    unlockedLocationIds,
  ).any((location) => location.raw['Location ID'] == toLocationId);
}

/// Moves the player to a destination, stopping any running primary activity
/// with refunds. A death pause blocks arrival and leaves the activity alone.
PlayerSave applyTravelArrival(
  GameDatabase db,
  PlayerSave save,
  String destinationLocationId,
  num nowMs,
) {
  if (isDeathPaused(save, nowMs)) return save;
  final stopped = stopPrimaryActivityNow(db, save, nowMs);
  final arrived = stopped.copyWith(currentLocationId: destinationLocationId);
  return maybeGrantKingswoodsSling(
    db,
    applyQuestLocationProgress(db, arrived, destinationLocationId),
  ).save;
}
