import type { LocationRow } from '../data/types'
import { CASTLE_MAP_ID, CAVE_MAP_ID, MAIN_MAP_ID } from './constants'

export interface NodePosition {
  x: number
  y: number
}

/**
 * UI-only node placement derived from Game Bible geography.
 * Not balance data; database has no coordinates.
 */
export const MAIN_MAP_NODE_LAYOUT: Record<string, NodePosition> = {
  'LOC-0009': { x: 18, y: 22 }, // Meadow
  'LOC-0001': { x: 34, y: 42 }, // Farm
  'LOC-0002': { x: 48, y: 48 }, // Town
  'LOC-0005': { x: 60, y: 38 }, // Copper Mine
  'LOC-0003': { x: 38, y: 62 }, // Goblin Camp
  'LOC-0004': { x: 22, y: 72 }, // River / Coast / Dock
  'LOC-0008': { x: 66, y: 56 }, // Kingswoods
  'LOC-0013': { x: 82, y: 52 }, // Castle
  'LOC-0006': { x: 70, y: 24 }, // Mountains
  'LOC-0010': { x: 78, y: 30 }, // Cave Entrance
  'LOC-0007': { x: 88, y: 18 }, // Wizard's Tower
}

export const CAVE_MAP_NODE_LAYOUT: Record<string, NodePosition> = {
  'LOC-0010': { x: 50, y: 18 }, // Cave Entrance (exit)
  'LOC-0011': { x: 42, y: 58 }, // Deep Mines
  'LOC-0012': { x: 70, y: 52 }, // Dwarven Mining Store
}

export const CASTLE_MAP_NODE_LAYOUT: Record<string, NodePosition> = {
  'LOC-0014': { x: 50, y: 72 }, // Courtyard and Gate
  'LOC-0015': { x: 50, y: 48 }, // Main Hall
  'LOC-0016': { x: 28, y: 30 }, // King's Quarters
  'LOC-0017': { x: 74, y: 34 }, // Barracks
  'LOC-0013': { x: 50, y: 88 }, // Castle gateway / exit to world
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
