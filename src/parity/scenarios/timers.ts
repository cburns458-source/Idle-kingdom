import type { LocationTimer, PlayerSave } from '../../game/save/types'
import {
  discoverUnlockedFarmSpot,
  pruneLockedTimerSpots,
} from '../../game/timers/locationTimers'
import { scenario, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'
import { asJson, baseSave } from './saveFixtures'

const GROWING_FARM: LocationTimer = {
  locationId: 'LOC-0001',
  kind: 'botany',
  inputItemId: 'ITEM-0324',
  outputItemId: 'ITEM-0025',
  outputQuantity: 1,
  skillId: 'SKL-0014',
  xpReward: 10,
  startedAt: '2026-01-01T00:00:00.000Z',
  durationMs: 60_000,
}

function makePruneCases(): {
  lockedFarm: PlayerSave
  lockedGrowing: PlayerSave
  unlockedFarm: PlayerSave
} {
  const base = baseSave(contentDatabase())
  const lockedFarm: PlayerSave = {
    ...base,
    discoveredTimerSpotIds: ['botany:LOC-0001', 'botany:LOC-0009', 'fishing_pot:LOC-0003'],
  }
  return {
    lockedFarm,
    lockedGrowing: { ...lockedFarm, locationTimers: [GROWING_FARM] },
    unlockedFarm: {
      ...lockedFarm,
      quests: [{ questId: 'QST-0011', status: 'completed', progress: 1, counters: {} }],
    },
  }
}

const pruneCases = makePruneCases()

export const timerScenarios: ParityScenario[] = [
  scenario(
    'timers/prune-locked-spots',
    'cases',
    {
      source: 'content',
      save: asJson(pruneCases.lockedFarm),
      lockedFarm: asJson(pruneCases.lockedFarm),
      lockedGrowing: asJson(pruneCases.lockedGrowing),
      unlockedFarm: asJson(pruneCases.unlockedFarm),
    },
    () => {
      const db = contentDatabase()
      return {
        dropsLockedFarm: asJson(pruneLockedTimerSpots(db, pruneCases.lockedFarm)),
        keepsGrowing: asJson(pruneLockedTimerSpots(db, pruneCases.lockedGrowing)),
        keepsUnlocked: asJson(pruneLockedTimerSpots(db, pruneCases.unlockedFarm)),
        farmDiscoverLocked: asJson(discoverUnlockedFarmSpot(db, pruneCases.lockedFarm)),
        farmDiscoverUnlocked: asJson(discoverUnlockedFarmSpot(db, pruneCases.unlockedFarm)),
      }
    },
  ),
]
