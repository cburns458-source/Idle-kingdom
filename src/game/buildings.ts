import type { BuildingDef } from './types'

/**
 * Ordered list of buildings the player can purchase. Later buildings are more
 * expensive but produce far more gold per second.
 */
export const BUILDINGS: BuildingDef[] = [
  {
    id: 'farm',
    name: 'Farm',
    description: 'Hardworking peasants till the fields.',
    icon: '🌾',
    baseCost: 15,
    costGrowth: 1.15,
    production: 0.5,
  },
  {
    id: 'lumber-mill',
    name: 'Lumber Mill',
    description: 'Turns the royal forest into coin.',
    icon: '🪵',
    baseCost: 100,
    costGrowth: 1.15,
    production: 3,
  },
  {
    id: 'mine',
    name: 'Gold Mine',
    description: 'Dwarven miners dig for glittering ore.',
    icon: '⛏️',
    baseCost: 1_100,
    costGrowth: 1.15,
    production: 12,
  },
  {
    id: 'barracks',
    name: 'Barracks',
    description: 'Soldiers collect tribute from the realm.',
    icon: '🛡️',
    baseCost: 12_000,
    costGrowth: 1.15,
    production: 80,
  },
  {
    id: 'castle',
    name: 'Grand Castle',
    description: 'A seat of power that draws wealth from afar.',
    icon: '🏰',
    baseCost: 130_000,
    costGrowth: 1.15,
    production: 500,
  },
]

export const BUILDINGS_BY_ID: Record<string, BuildingDef> = Object.fromEntries(
  BUILDINGS.map((b) => [b.id, b]),
)

/** Gold gained per manual "collect taxes" click. */
export const CLICK_REWARD = 1
