import { useCallback, useEffect, useRef, useState } from 'react'
import {
  buyBuilding as applyBuy,
  click as applyClick,
  createInitialState,
  tick,
} from '../game/engine'
import type { GameState } from '../game/types'

const STORAGE_KEY = 'idle-kingdom-save-v1'
const TICK_MS = 100

function loadState(): GameState {
  if (typeof localStorage === 'undefined') return createInitialState()
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return createInitialState()
    const parsed = JSON.parse(raw) as Partial<GameState>
    const base = createInitialState()
    return {
      ...base,
      ...parsed,
      buildings: { ...base.buildings, ...(parsed.buildings ?? {}) },
    }
  } catch {
    return createInitialState()
  }
}

export interface UseGame {
  state: GameState
  collectTaxes: () => void
  buyBuilding: (buildingId: string) => void
  reset: () => void
}

export function useGame(): UseGame {
  const [state, setState] = useState<GameState>(loadState)
  const stateRef = useRef(state)
  stateRef.current = state

  useEffect(() => {
    const id = window.setInterval(() => {
      setState((prev) => tick(prev, TICK_MS / 1000))
    }, TICK_MS)
    return () => window.clearInterval(id)
  }, [])

  useEffect(() => {
    if (typeof localStorage === 'undefined') return
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state))
  }, [state])

  const collectTaxes = useCallback(() => setState(applyClick), [])
  const buyBuilding = useCallback(
    (buildingId: string) => setState((prev) => applyBuy(prev, buildingId)),
    [],
  )
  const reset = useCallback(() => {
    if (typeof localStorage !== 'undefined') localStorage.removeItem(STORAGE_KEY)
    setState(createInitialState())
  }, [])

  return { state, collectTaxes, buyBuilding, reset }
}
