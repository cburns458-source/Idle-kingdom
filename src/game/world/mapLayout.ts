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
 * Main map is an expanded-in-all-directions canvas generated from the original square art.
 */
export const MAIN_MAP_NODE_LAYOUT: Record<string, NodePosition> = {
  // NW castle with blue roofs
  'LOC-0013': { x: 24, y: 24 },
  // Ancient Forest north of the castle
  'LOC-0018': { x: 22, y: 10 },
  // Temple on the ridge between castle and mountains
  'LOC-0036': { x: 36, y: 20 },
  // Mountain peaks / ridge (nudged right)
  'LOC-0006': { x: 62, y: 16 },
  // Cave mouth in the mountains
  'LOC-0010': { x: 52, y: 36 },
  // Wizard tower with blue magic (NE, lowered)
  'LOC-0007': { x: 78, y: 34 },
  // West kingswoods forest
  'LOC-0008': { x: 14, y: 34 },
  // Central village / town square (gateway into Town Map)
  'LOC-0002': { x: 30, y: 48 },
  // Fortified camp (Goblin Camp)
  'LOC-0003': { x: 72, y: 48 },
  // Meadow
  'LOC-0009': { x: 16, y: 58 },
  // Mine entrance with ore piles
  'LOC-0005': { x: 24, y: 70 },
  // Farm fields / windmill
  'LOC-0001': { x: 76, y: 66 },
  // Harbor / dock at river mouth (raised)
  'LOC-0004': { x: 50, y: 68 },
  // Citadel Hub gateway (between Town and Goblin Camp)
  'LOC-0027': { x: 50, y: 46 },
}

export const CAVE_MAP_NODE_LAYOUT: Record<string, NodePosition> = {
  // Sunlit exit at top
  'LOC-0010': { x: 50, y: 10 },
  // Lantern-lit shop counter (Dwarven Mining Store)
  'LOC-0012': { x: 22, y: 30 },
  // Active mine shaft / ore chambers
  'LOC-0011': { x: 68, y: 58 },
  // Abandoned Mineshaft (bottom-left)
  'LOC-0022': { x: 22, y: 78 },
}

export const CASTLE_MAP_NODE_LAYOUT: Record<string, NodePosition> = {
  // Queen's Quarters (top-left)
  'LOC-0021': { x: 22, y: 14 },
  // Grand blue-roof palace (Main Hall)
  'LOC-0015': { x: 50, y: 18 },
  // Private chamber with bed / shelves (King's Quarters)
  'LOC-0016': { x: 78, y: 24 },
  // Training yard with dummies (Barracks)
  'LOC-0017': { x: 78, y: 70 },
  // Gatehouse / courtyard entrance
  'LOC-0014': { x: 50, y: 78 },
  // Castle gateway marker at the outer gate
  'LOC-0013': { x: 50, y: 90 },
}

export const TOWN_MAP_NODE_LAYOUT: Record<string, NodePosition> = {
  // Town gateway / square (top)
  'LOC-0002': { x: 50, y: 12 },
  // Kitchen
  'LOC-0023': { x: 22, y: 38 },
  // General Store
  'LOC-0024': { x: 78, y: 38 },
  // The Foundry
  'LOC-0025': { x: 30, y: 72 },
  // Rose's Apothecary (unlocks after quest)
  'LOC-0026': { x: 70, y: 72 },
  // Town Bank
  'LOC-0034': { x: 50, y: 55 },
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
