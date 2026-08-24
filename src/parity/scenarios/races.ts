import { assignRace } from '../../game/races/assignRace'
import {
  applyRaceGoldGain,
  dwarvenMiningStoreRequiredLevel,
  grantRaceStartingItems,
  raceBonusSummaryLines,
  raceBonusesFor,
  raceById,
  raceBypassesForcedHostilityAt,
  raceDisplayName,
  raceGoldGainMultiplier,
  raceMaxHpMultiplier,
  raceSkillDropChanceBonusPercent,
  raceStartingItems,
  races,
} from '../../game/races/races'
import type { PlayerSave } from '../../game/save/types'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'
import { asJson, baseSave, richSave } from './saveFixtures'

const RACE_IDS = ['RACE-0001', 'RACE-0002', 'RACE-0003', 'RACE-0004', 'RACE-0005', 'RACE-0006', 'RACE-0007']
const SKILL_IDS = ['SKL-0001', 'SKL-0002', 'SKL-0003', 'SKL-0004', 'SKL-0005', 'SKL-0006', 'SKL-0007', 'SKL-9999']
const GOLD_AMOUNTS = [0, 1, 7, 100, 12.5, -20]
const HOSTILITY_LOCATIONS = ['LOC-0002', 'LOC-0003', 'LOC-9999']

/** The base save with a race forced on, bypassing the kit grant. */
function saveWithRace(raceId: string | null): PlayerSave {
  return { ...baseSave(contentDatabase()), raceId }
}

function withSave(save: PlayerSave, extra: Record<string, JsonValue> = {}): JsonValue {
  return { source: 'content', save: asJson(save), ...extra }
}

export const raceScenarios: ParityScenario[] = [
  scenario('races/catalog', 'sorted', { source: 'content' }, () => {
    const db = contentDatabase()
    return {
      order: races(db).map((row) => row['Race ID']),
      names: races(db).map((row) => raceDisplayName(db, row['Race ID'])),
      missing: raceDisplayName(db, 'RACE-9999'),
      nullId: raceDisplayName(db, null),
      foundById: RACE_IDS.map((raceId) => raceById(db, raceId)?.['Race ID'] ?? null),
    }
  }),

  ...RACE_IDS.map((raceId) =>
    scenario('races/bonuses', raceId.toLowerCase(), withSave(saveWithRace(raceId), { raceId }), () => {
      const db = contentDatabase()
      const save = saveWithRace(raceId)
      return {
        bonusIds: raceBonusesFor(db, raceId).map((row) => row['Race Bonus ID']),
        summary: raceBonusSummaryLines(db, raceId),
        startingItemIds: raceStartingItems(db, raceId).map((row) => row['Race Starting Item ID']),
        miningStoreLevel: dwarvenMiningStoreRequiredLevel(save),
        maxHp: raceMaxHpMultiplier(db, save),
        goldGain: raceGoldGainMultiplier(db, save),
        skillDropChance: SKILL_IDS.map((skillId) =>
          raceSkillDropChanceBonusPercent(db, save, skillId),
        ),
        appliedGold: GOLD_AMOUNTS.map((amount) => applyRaceGoldGain(db, save, amount)),
        hostility: HOSTILITY_LOCATIONS.map((locationId) =>
          raceBypassesForcedHostilityAt(db, save, locationId),
        ),
      } as unknown as JsonValue
    }),
  ),

  scenario('races/no-race', 'unset', withSave(saveWithRace(null)), () => {
    const db = contentDatabase()
    const save = saveWithRace(null)
    return {
      bonusIds: raceBonusesFor(db, null).map((row) => row['Race Bonus ID']),
      miningStoreLevel: dwarvenMiningStoreRequiredLevel(save),
      maxHp: raceMaxHpMultiplier(db, save),
      goldGain: raceGoldGainMultiplier(db, save),
      hostility: HOSTILITY_LOCATIONS.map((locationId) =>
        raceBypassesForcedHostilityAt(db, save, locationId),
      ),
    } as unknown as JsonValue
  }),

  ...RACE_IDS.map((raceId) =>
    scenario(
      'races/starting-kit',
      raceId.toLowerCase(),
      withSave(baseSave(contentDatabase()), { raceId }),
      () => ({
        save: asJson(grantRaceStartingItems(contentDatabase(), baseSave(contentDatabase()), raceId)),
      }),
    ),
  ),

  ...RACE_IDS.map((raceId) =>
    scenario(
      'races/assign',
      `first-pick-${raceId}`.toLowerCase(),
      withSave(baseSave(contentDatabase()), { raceId }),
      () => {
        const result = assignRace(contentDatabase(), baseSave(contentDatabase()), raceId)
        return (
          result.ok
            ? { ok: true, grantedStarterKit: result.grantedStarterKit, save: asJson(result.save) }
            : { ok: false, reason: result.reason }
        ) as JsonValue
      },
    ),
  ),

  scenario(
    'races/assign',
    'switching-skips-kit',
    withSave(richSave(contentDatabase()), { raceId: 'RACE-0004' }),
    () => {
      const result = assignRace(contentDatabase(), richSave(contentDatabase()), 'RACE-0004')
      return (
        result.ok
          ? { ok: true, grantedStarterKit: result.grantedStarterKit, save: asJson(result.save) }
          : { ok: false, reason: result.reason }
      ) as JsonValue
    },
  ),

  scenario(
    'races/assign',
    'unknown-race',
    withSave(baseSave(contentDatabase()), { raceId: 'RACE-9999' }),
    () => {
      const result = assignRace(contentDatabase(), baseSave(contentDatabase()), 'RACE-9999')
      return (
        result.ok
          ? { ok: true, grantedStarterKit: result.grantedStarterKit, save: asJson(result.save) }
          : { ok: false, reason: result.reason }
      ) as JsonValue
    },
  ),
]
