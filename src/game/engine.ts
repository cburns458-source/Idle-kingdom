import { BUILDINGS, BUILDINGS_BY_ID, CLICK_REWARD } from './buildings'
import type { GameState } from './types'

export function createInitialState(): GameState {
  return {
    gold: 0,
    totalEarned: 0,
    clicks: 0,
    buildings: Object.fromEntries(BUILDINGS.map((b) => [b.id, 0])),
  }
}

/** Cost of the next building of the given type, given how many are owned. */
export function buildingCost(buildingId: string, owned: number): number {
  const def = BUILDINGS_BY_ID[buildingId]
  if (!def) throw new Error(`Unknown building: ${buildingId}`)
  return Math.floor(def.baseCost * Math.pow(def.costGrowth, owned))
}

/** Total gold produced per second across all owned buildings. */
export function goldPerSecond(state: GameState): number {
  return BUILDINGS.reduce((sum, def) => {
    const owned = state.buildings[def.id] ?? 0
    return sum + owned * def.production
  }, 0)
}

export function canAfford(state: GameState, buildingId: string): boolean {
  const owned = state.buildings[buildingId] ?? 0
  return state.gold >= buildingCost(buildingId, owned)
}

/**
 * Attempt to buy one building. Returns a new state with the purchase applied,
 * or the same state (unchanged) when the player cannot afford it.
 */
export function buyBuilding(state: GameState, buildingId: string): GameState {
  if (!canAfford(state, buildingId)) return state
  const owned = state.buildings[buildingId] ?? 0
  const cost = buildingCost(buildingId, owned)
  return {
    ...state,
    gold: state.gold - cost,
    buildings: { ...state.buildings, [buildingId]: owned + 1 },
  }
}

/** Apply a manual "collect taxes" click. */
export function click(state: GameState): GameState {
  return {
    ...state,
    gold: state.gold + CLICK_REWARD,
    totalEarned: state.totalEarned + CLICK_REWARD,
    clicks: state.clicks + 1,
  }
}

/** Advance the simulation by `deltaSeconds`, accruing passive gold. */
export function tick(state: GameState, deltaSeconds: number): GameState {
  if (deltaSeconds <= 0) return state
  const earned = goldPerSecond(state) * deltaSeconds
  if (earned === 0) return state
  return {
    ...state,
    gold: state.gold + earned,
    totalEarned: state.totalEarned + earned,
  }
}
