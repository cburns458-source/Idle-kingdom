import 'dart:ui';

import 'package:ik_rules/ik_rules.dart';

/// District maps that have not been redrawn still ship square.
const double mapArtAspectRatio = 1;

/// Portrait plates match the phone column. Mountains uses the same 9:16
/// location plate as a stand-in map until dedicated highland art exists.
const double mainMapArtAspectRatio = 9 / 16;

/// Cover-fit aspect for [mapId]'s background. Nodes are percentages of that art.
double artAspectRatioForMap(String mapId) {
  return mapId == mainMapId ||
          mapId == townMapId ||
          mapId == castleMapId ||
          mapId == caveMapId ||
          mapId == citadelMapId ||
          mapId == mountainsMapId
      ? mainMapArtAspectRatio
      : mapArtAspectRatio;
}

/// Where the map art actually lands inside [box] once [BoxFit.cover] has had
/// its way with it.
///
/// Node positions are percentages of the art, not of the widget, so they have
/// to be read against this rectangle. Cover scales the art up until it fills
/// the shorter side and lets the longer one hang off both edges, which is why
/// a node placed against the widget drifts off its landmark.
Rect mapArtRect(Size box, {double aspectRatio = mapArtAspectRatio}) {
  if (box.isEmpty || aspectRatio <= 0) return Rect.fromLTWH(0, 0, box.width, box.height);
  final scale = box.width / aspectRatio > box.height ? box.width / aspectRatio : box.height;
  final width = aspectRatio * scale;
  final height = scale;
  return Rect.fromLTWH((box.width - width) / 2, (box.height - height) / 2, width, height);
}

/// Part-way from [from] to [to], for a sprite mid-walk.
NodePosition lerpNodePosition(NodePosition from, NodePosition to, double t) {
  return NodePosition(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t);
}

/// The point on the art a node sits on, in [box] coordinates.
Offset mapArtOffset(NodePosition position, Size box, {double aspectRatio = mapArtAspectRatio}) {
  final rect = mapArtRect(box, aspectRatio: aspectRatio);
  return Offset(
    rect.left + rect.width * (position.x / 100),
    rect.top + rect.height * (position.y / 100),
  );
}

/// How close a map node's dot or label may come to the edge of the map view.
const double mapLabelEdgeMargin = 4;

/// Widest a map node label may be before it wraps, for a map view [boxWidth]
/// wide. Narrow phones get a narrower cap so an edge label has room to move in.
double mapLabelMaxWidth(double boxWidth) {
  final cap = boxWidth * 0.4;
  return cap < 64 ? 64 : (cap > 120 ? 120 : cap);
}

/// Left edge for a box [width] wide that would like to be centred on
/// [anchorX], slid inward just enough to stay [margin] inside [boxWidth].
///
/// A box wider than the room left between the margins is centred in the view.
double clampCentredLeft(
  double anchorX,
  double width,
  double boxWidth, {
  double margin = mapLabelEdgeMargin,
}) {
  final centred = anchorX - width / 2;
  final lo = margin;
  final hi = boxWidth - margin - width;
  if (hi < lo) return (boxWidth - width) / 2;
  if (centred < lo) return lo;
  if (centred > hi) return hi;
  return centred;
}
