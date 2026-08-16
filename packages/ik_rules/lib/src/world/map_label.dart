import 'package:ik_content/ik_content.dart';

/// Map IDs that must not show this location, from [LocationRow.hiddenOnMapIDs].
List<String> hiddenMapIdsFor(LocationRow location) {
  final raw = location.hiddenOnMapIDs;
  if (raw == null || raw.trim().isEmpty) return const <String>[];
  return raw
      .split(';')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
}

bool locationHiddenOnMap(LocationRow location, String mapId) {
  return hiddenMapIdsFor(location).contains(mapId);
}

/// Gateway nodes use [LocationRow.mapNodeName] on a child sub-map.
String mapNodeLabel(LocationRow location, String browseMapId) {
  final mapId = location.mapId;
  final nodeName = location.mapNodeName;
  if (nodeName != null && nodeName.isNotEmpty && mapId != null && browseMapId != mapId) {
    return nodeName;
  }
  return location.displayName;
}
