import type { LocationRow } from '../data/types'
import { CASTLE_MAP_ID, CAVE_MAP_ID, MAIN_MAP_ID } from './constants'

export interface NodePosition {
  x: number
  y: number
}

/**
 * UI node placement aligned to landmarks in the generated map art.
 * Coordinates are percent of the square map image (not balance data).
 */
export const MAIN_MAP_NODE_LAYOUT: Record<string, NodePosition> = {
  // NW castle with blue roofs
  'LOC-0013': { x: 22, y: 16 },
  // Mountain peaks / range
  'LOC-0006': { x: 50, y: 9 },
  // Cave mouth in the mountains
  'LOC-0010': { x: 47, y: 21 },
  // Wizard tower with blue magic (NE)
  'LOC-0007': { x: 80, y: 17 },
  // Forest between castle and river (Kingswoods)
  'LOC-0008': { x: 30, y: 28 },
  // Central village / town square
  'LOC-0002': { x: 33, y: 44 },
  // Fortified orange-tent camp (Goblin Camp)
  'LOC-0003': { x: 64, y: 41 },
  // Open grassy plain (Meadow)
  'LOC-0009': { x: 14, y: 50 },
  // Mine entrance with ore piles (SW)
  'LOC-0005': { x: 24, y: 64 },
  // Windmill farmland (SE)
  'LOC-0001': { x: 74, y: 70 },
  // Harbor / dock at river mouth
  'LOC-0004': { x: 50, y: 82 },
}

export const CAVE_MAP_NODE_LAYOUT: Record<string, NodePosition> = {
  // Sunlit exit at top
  'LOC-0010': { x: 50, y: 10 },
  // Lantern-lit shop counter (Dwarven Mining Store)
  'LOC-0012': { x: 22, y: 30 },
  // Active mine shaft / ore chambers
  'LOC-0011': { x: 68, y: 58 },
}

export const CASTLE_MAP_NODE_LAYOUT: Record<string, NodePosition> = {
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

export function layoutForMap(mapId: string): Record<string, NodePosition> {
  switch (mapId) {
    case CAVE_MAP_ID:
      return CAVE_MAP_NODE_LAYOUT
    case CASTLE_MAP_ID:
      return CASTLE_MAP_NODE_LAYOUT
    case MAIN_MAP_ID:
    default:
      return MAIN_MAP_NODE_LAYOUT
  }
}

export function positionForLocation(location: LocationRow): NodePosition {
  const mapId = location['Map ID'] ?? MAIN_MAP_ID
  const layout = layoutForMap(mapId)
  return layout[location['Location ID']] ?? { x: 50, y: 50 }
}
