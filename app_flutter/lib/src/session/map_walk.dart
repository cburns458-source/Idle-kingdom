import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

/// Shortest walk: half a second. Longest walk: a second and a half.
const num mapWalkMinMs = 500;
const num mapWalkMaxMs = 1500;

/// Layout distance treated as a full-length crossing of the map.
const num mapWalkFarDistance = 100;

/// Where the walking sprite starts on [browseMapId].
///
/// Same-map trips start on the node the player is standing on. A trip that
/// leaves a district starts on that map's entrance / gateway, because the
/// current node is not on the map being walked.
String mapWalkStartLocationId(GameDatabase db, String currentLocationId, String browseMapId) {
  LocationRow? current;
  for (final location in db.locations) {
    if (location.locationId == currentLocationId) {
      current = location;
      break;
    }
  }
  if (current == null) return currentLocationId;
  final currentMap = getLocationMapId(current);
  if (currentMap == browseMapId) return currentLocationId;

  if (browseMapId == mainMapId && isSubMap(db, currentMap)) {
    return gatewayLocationIdForSubMap(db, currentMap) ?? currentLocationId;
  }
  if (isSubMap(db, browseMapId)) {
    return entryLandingLocationIdForMap(db, browseMapId) ?? currentLocationId;
  }
  return currentLocationId;
}

/// Node placement on the map the player is looking at, not the node's home map.
NodePosition positionOnBrowseMap(String locationId, String browseMapId, LocationRow? location) {
  final layout = layoutForMap(browseMapId);
  return layout[locationId] ??
      (location == null ? const NodePosition(x: 50, y: 50) : positionForLocation(location));
}

Alignment alignmentOf(NodePosition position) {
  return Alignment(position.x / 50 - 1, position.y / 50 - 1);
}

/// Half a second to a second and a half, from how far apart the two nodes sit.
num mapWalkDurationMs(NodePosition from, NodePosition to) {
  final dx = (to.x - from.x).toDouble();
  final dy = (to.y - from.y).toDouble();
  final distance = math.sqrt(dx * dx + dy * dy);
  final t = (distance / mapWalkFarDistance).clamp(0.0, 1.0);
  return mapWalkMinMs + t * (mapWalkMaxMs - mapWalkMinMs);
}

/// A few wobbles left and right while the sprite walks, in radians.
double mapWalkWobbleRadians(double progress) {
  return math.sin(progress * math.pi * 12) * 0.28;
}
