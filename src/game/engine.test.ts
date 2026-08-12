import { describe, expect, it } from 'vitest'
import {
  buildingCost,
  buyBuilding,
  canAfford,
  click,
  createInitialState,
  goldPerSecond,
  tick,
} from './engine'

describe('createInitialState', () => {
  it('starts with no gold and no buildings', () => {
    const state = createInitialState()
    expect(state.gold).toBe(0)
    expect(state.totalEarned).toBe(0)
    expect(state.clicks).toBe(0)
    expect(goldPerSecond(state)).toBe(0)
    expect(Object.values(state.buildings).every((n) => n === 0)).toBe(true)
  })
})

describe('buildingCost', () => {
  it('returns the base cost for the first building', () => {
    expect(buildingCost('farm', 0)).toBe(15)
  })

  it('grows with the number owned', () => {
    expect(buildingCost('farm', 1)).toBe(17) // floor(15 * 1.15)
    expect(buildingCost('farm', 2)).toBe(19) // floor(15 * 1.15^2)
  })

  it('throws for unknown buildings', () => {
    expect(() => buildingCost('dragon', 0)).toThrow()
  })
})

describe('click', () => {
  it('adds one gold and records the click', () => {
    const state = click(createInitialState())
    expect(state.gold).toBe(1)
    expect(state.totalEarned).toBe(1)
    expect(state.clicks).toBe(1)
  })
})

describe('canAfford / buyBuilding', () => {
  it('cannot afford or buy without enough gold', () => {
    const state = createInitialState()
    expect(canAfford(state, 'farm')).toBe(false)
    expect(buyBuilding(state, 'farm')).toBe(state)
  })

  it('buys a building and deducts the cost', () => {
    const rich = { ...createInitialState(), gold: 20 }
    expect(canAfford(rich, 'farm')).toBe(true)
    const next = buyBuilding(rich, 'farm')
    expect(next.buildings.farm).toBe(1)
    expect(next.gold).toBe(5) // 20 - 15
    expect(goldPerSecond(next)).toBe(0.5)
  })

  it('makes the next building more expensive', () => {
    let state = { ...createInitialState(), gold: 100 }
    state = buyBuilding(state, 'farm')
    expect(buildingCost('farm', state.buildings.farm)).toBe(17)
  })
})

describe('tick', () => {
  it('accrues passive gold based on production', () => {
    const withFarm = buyBuilding({ ...createInitialState(), gold: 15 }, 'farm')
    const after = tick(withFarm, 10) // 0.5/s * 10s = 5
    expect(after.gold).toBeCloseTo(5)
    expect(after.totalEarned).toBeCloseTo(5)
  })

  it('does nothing without production or time', () => {
    const state = { ...createInitialState(), gold: 42 }
    expect(tick(state, 5)).toBe(state)
    const withFarm = buyBuilding({ ...createInitialState(), gold: 15 }, 'farm')
    expect(tick(withFarm, 0)).toBe(withFarm)
  })
})
