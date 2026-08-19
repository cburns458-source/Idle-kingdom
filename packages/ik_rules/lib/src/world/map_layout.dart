import 'package:ik_content/ik_content.dart';

import 'constants.dart';

/// Node placement as a percentage of the map image, aligned to landmarks in the
/// generated art. These are presentation coordinates, not balance data.
class NodePosition {
  const NodePosition({required this.x, required this.y});

  final num x;
  final num y;

  Map<String, Object?> toJson() => <String, Object?>{'x': x, 'y': y};
}

/// The overworld is a 9:16 plate; nodes sit on landmarks in the generated art.
const Map<String, NodePosition> mainMapNodeLayout = <String, NodePosition>{
  // NW castle with red roofs
  'LOC-0013': NodePosition(x: 26, y: 33),
  // Ancient Forest north of the castle
  'LOC-0018': NodePosition(x: 22, y: 23),
  // Temple on the ridge between castle and mountains
  'LOC-0036': NodePosition(x: 45, y: 25),
  // Mountain peaks / ridge
  'LOC-0006': NodePosition(x: 68, y: 21),
  // Cave mouth at the foot of the mountains
  'LOC-0010': NodePosition(x: 58, y: 36),
  // Wizard tower with blue roof (NE)
  'LOC-0007': NodePosition(x: 84, y: 28),
  // West kingswoods forest
  'LOC-0008': NodePosition(x: 16, y: 40),
  // Central village / town square (gateway into Town Map)
  'LOC-0002': NodePosition(x: 28, y: 50),
  // Fortified camp (Goblin Camp)
  'LOC-0003': NodePosition(x: 74, y: 45),
  // Meadow
  'LOC-0009': NodePosition(x: 20, y: 57),
  // Mine entrance with ore carts
  'LOC-0005': NodePosition(x: 30, y: 64),
  // Farm fields / windmill
  'LOC-0001': NodePosition(x: 76, y: 65),
  // Harbor / dock at river mouth
  'LOC-0004': NodePosition(x: 54, y: 70),
  // Road to the Citadel — horse and carriage at the river fork
  'LOC-0027': NodePosition(x: 48, y: 42),
};

const Map<String, NodePosition> caveMapNodeLayout = <String, NodePosition>{
  // Sunlit cave mouth looking out to the pines
  'LOC-0010': NodePosition(x: 34, y: 8),
  // Built dwarven shop with gem counter
  'LOC-0012': NodePosition(x: 73, y: 44),
  // Working mine cart and ore
  'LOC-0011': NodePosition(x: 78, y: 78),
  // Abandoned webbed shaft
  'LOC-0022': NodePosition(x: 20, y: 76),
};

const Map<String, NodePosition> castleMapNodeLayout = <String, NodePosition>{
  // Queen's tower with the perched dragon
  'LOC-0021': NodePosition(x: 20, y: 30),
  // Red-roof keep / Main Hall
  'LOC-0015': NodePosition(x: 50, y: 34),
  // King's wing with lion banners and balcony
  'LOC-0016': NodePosition(x: 74, y: 34),
  // Training yard with dummies (Barracks)
  'LOC-0017': NodePosition(x: 76, y: 64),
  // Courtyard fountain
  'LOC-0014': NodePosition(x: 50, y: 55),
  // Castle gateway at the outer gatehouse
  'LOC-0013': NodePosition(x: 50, y: 78),
};

const Map<String, NodePosition> townMapNodeLayout = <String, NodePosition>{
  // Town gateway, offset in the northern cluster
  'LOC-0002': NodePosition(x: 40, y: 21),
  // Kitchen, west street
  'LOC-0023': NodePosition(x: 27, y: 43),
  // General Store, east stall
  'LOC-0024': NodePosition(x: 76, y: 43),
  // The Foundry, lower-left workshops
  'LOC-0025': NodePosition(x: 28, y: 69),
  // Rose's Apothecary, lower-right rose cottage
  'LOC-0026': NodePosition(x: 76, y: 72),
  // Town Bank, columned hall
  'LOC-0034': NodePosition(x: 54, y: 53),
};

const Map<String, NodePosition> citadelMapNodeLayout = <String, NodePosition>{
  // Citadel gateway / exit (north gate, hidden on this submap)
  'LOC-0027': NodePosition(x: 50, y: 18),
  // Plaza hub
  'LOC-0028': NodePosition(x: 50, y: 44),
  // Market District
  'LOC-0029': NodePosition(x: 26, y: 42),
  // Processing District
  'LOC-0030': NodePosition(x: 72, y: 41),
  // Gathering Outskirts
  'LOC-0031': NodePosition(x: 26, y: 72),
  // Combat Training Grounds
  'LOC-0032': NodePosition(x: 70, y: 74),
  // Guild Hall
  'LOC-0033': NodePosition(x: 50, y: 58),
  // Citadel Bank
  'LOC-0035': NodePosition(x: 50, y: 30),
};

const Map<String, Map<String, NodePosition>> _layouts = <String, Map<String, NodePosition>>{
  mainMapId: mainMapNodeLayout,
  caveMapId: caveMapNodeLayout,
  castleMapId: castleMapNodeLayout,
  townMapId: townMapNodeLayout,
  citadelMapId: citadelMapNodeLayout,
};

Map<String, NodePosition> layoutForMap(String mapId) {
  return _layouts[mapId] ?? mainMapNodeLayout;
}

NodePosition positionForLocation(LocationRow location) {
  final mapId = location.raw['Map ID'];
  final layout = layoutForMap(mapId is String ? mapId : mainMapId);
  return layout[location.raw['Location ID']] ?? const NodePosition(x: 50, y: 50);
}
