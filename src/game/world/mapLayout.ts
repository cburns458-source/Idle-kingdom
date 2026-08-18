import type { LocationRow } from '../data/types'
import {
  CASTLE_MAP_ID,
  CAVE_MAP_ID,
  CITADEL_MAP_ID,
  MAIN_MAP_ID,
  TOWN_MAP_ID,
} from './constants'

export interface NodePosition {
  x: number
  y: number
}

/**
 * UI node placement aligned to landmarks in the generated map art.
 * Coordinates are percent of the map image (not balance data).
 * The overworld, Town, Castle, and Cave are 9:16 portrait plates so they match the phone column.
 */
export const MAIN_MAP_NODE_LAYOUT: Record<string, NodePosition> = {
  // NW castle with red roofs
  'LOC-0013': { x: 26, y: 33 },
  // Ancient Forest north of the castle
  'LOC-0018': { x: 22, y: 23 },
  // Temple on the ridge between castle and mountains
  'LOC-0036': { x: 45, y: 25 },
  // Mountain peaks / ridge
  'LOC-0006': { x: 68, y: 21 },
  // Cave mouth at the foot of the mountains
  'LOC-0010': { x: 58, y: 36 },
  // Wizard tower with blue roof (NE)
  'LOC-0007': { x: 84, y: 28 },
  // West kingswoods forest
  'LOC-0008': { x: 16, y: 40 },
  // Central village / town square (gateway into Town Map)
  'LOC-0002': { x: 28, y: 50 },
  // Fortified camp (Goblin Camp)
  'LOC-0003': { x: 74, y: 45 },
  // Meadow
  'LOC-0009': { x: 20, y: 57 },
  // Mine entrance with ore carts
  'LOC-0005': { x: 30, y: 64 },
  // Farm fields / windmill
  'LOC-0001': { x: 76, y: 65 },
  // Harbor / dock at river mouth
  'LOC-0004': { x: 54, y: 70 },
  // Road to the Citadel — horse and carriage at the river fork
  'LOC-0027': { x: 48, y: 42 },
}

export const CAVE_MAP_NODE_LAYOUT: Record<string, NodePosition> = {
  // Sunlit cave mouth looking out to the pines
  'LOC-0010': { x: 50, y: 8 },
  // Built dwarven shop with gem counter
  'LOC-0012': { x: 18, y: 16 },
  // Working mine cart and ore
  'LOC-0011': { x: 70, y: 40 },
  // Abandoned webbed shaft
  'LOC-0022': { x: 20, y: 72 },
}

export const CASTLE_MAP_NODE_LAYOUT: Record<string, NodePosition> = {
  // Queen's tower with the perched dragon
  'LOC-0021': { x: 20, y: 30 },
  // Red-roof keep / Main Hall
  'LOC-0015': { x: 50, y: 34 },
  // King's wing with lion banners and balcony
  'LOC-0016': { x: 74, y: 34 },
  // Training yard with dummies (Barracks)
  'LOC-0017': { x: 76, y: 64 },
  // Courtyard fountain
  'LOC-0014': { x: 50, y: 55 },
  // Castle gateway at the outer gatehouse
  'LOC-0013': { x: 50, y: 78 },
}

export const TOWN_MAP_NODE_LAYOUT: Record<string, NodePosition> = {
  // Town gateway, offset in the northern cluster
  'LOC-0002': { x: 40, y: 21 },
  // Kitchen, west street
  'LOC-0023': { x: 27, y: 43 },
  // General Store, east stall
  'LOC-0024': { x: 76, y: 43 },
  // The Foundry, lower-left workshops
  'LOC-0025': { x: 28, y: 69 },
  // Rose's Apothecary, lower-right rose cottage
  'LOC-0026': { x: 76, y: 72 },
  // Town Bank, columned hall
  'LOC-0034': { x: 54, y: 53 },
}

export const CITADEL_MAP_NODE_LAYOUT: Record<string, NodePosition> = {
  // Citadel gateway / exit (top)
  'LOC-0027': { x: 50, y: 10 },
  // Plaza hub
  'LOC-0028': { x: 50, y: 40 },
  // Market District
  'LOC-0029': { x: 20, y: 38 },
  // Processing District
  'LOC-0030': { x: 80, y: 38 },
  // Gathering Outskirts
  'LOC-0031': { x: 28, y: 74 },
  // Combat Training Grounds
  'LOC-0032': { x: 72, y: 74 },
  // Guild Hall
  'LOC-0033': { x: 50, y: 58 },
  // Citadel Bank
  'LOC-0035': { x: 50, y: 26 },
}

const LAYOUTS: Record<string, Record<string, NodePosition>> = {
  [MAIN_MAP_ID]: MAIN_MAP_NODE_LAYOUT,
  [CAVE_MAP_ID]: CAVE_MAP_NODE_LAYOUT,
  [CASTLE_MAP_ID]: CASTLE_MAP_NODE_LAYOUT,
  [TOWN_MAP_ID]: TOWN_MAP_NODE_LAYOUT,
  [CITADEL_MAP_ID]: CITADEL_MAP_NODE_LAYOUT,
}

export function layoutForMap(mapId: string): Record<string, NodePosition> {
  return LAYOUTS[mapId] ?? MAIN_MAP_NODE_LAYOUT
}

export function positionForLocation(location: LocationRow): NodePosition {
  const mapId = location['Map ID'] ?? MAIN_MAP_ID
  const layout = layoutForMap(mapId)
  return layout[location['Location ID']] ?? { x: 50, y: 50 }
}
