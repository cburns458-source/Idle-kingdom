import type { ActivityRow, GameDatabase } from '../data/types'
import { GUILD_HALL_LOCATION_ID } from '../world/constants'
import {
  guildHallArcanaUnlocked,
  guildHallCageUnlocked,
  guildHallGardenUnlocked,
} from './hall'

export const GUILD_HALL_COMPANY_XP_PERCENT = 5

export const GUILD_HALL_ESSENCE_ACTIVITY_ID = 'ACT-GH01'
export const GUILD_HALL_CAGE_ACTIVITY_ID = 'ACT-GH02'

const ESSENCE_TEMPLATE_KEY = 'delve_for_essence'
const CAGE_TEMPLATE_KEY = 'train_citadel_grounds'

export const GUILD_HALL_CAGE_NOTE = 'guild_cage; NoLoot'

/** Flat +5% XP when another guild member is anywhere in the hall. */
export function applyGuildHallCompanyXp(xp: number, guildmatesPresent: boolean): number {
  if (!guildmatesPresent || xp <= 0) return xp
  return Math.floor((xp * (100 + GUILD_HALL_COMPANY_XP_PERCENT)) / 100)
}

export function guildHallCompanyActive(
  locationId: string | null | undefined,
  guildmatesInHall: boolean,
): boolean {
  return Boolean(guildmatesInHall) && locationId === GUILD_HALL_LOCATION_ID
}

export function isGuildHallEssenceActivity(activityId: string): boolean {
  return activityId === GUILD_HALL_ESSENCE_ACTIVITY_ID
}

export function isGuildHallCageActivity(activityId: string): boolean {
  return activityId === GUILD_HALL_CAGE_ACTIVITY_ID
}

export function activityIsGuildHallCage(activity: ActivityRow | undefined | null): boolean {
  if (!activity) return false
  if (isGuildHallCageActivity(activity['Activity ID'])) return true
  return /(?:^|;)\s*guild_cage\b/i.test(String(activity.Notes ?? ''))
}

/**
 * Clones Harness essence and the citadel training fight onto the guild hall.
 *
 * Visibility of each clone is gated by hall unlocks at start time, not here.
 */
export function withGuildHallRoomActivities(db: GameDatabase): GameDatabase {
  const essenceTemplate = db.Activities.find((row) => row['Internal Key'] === ESSENCE_TEMPLATE_KEY)
  const cageTemplate = db.Activities.find((row) => row['Internal Key'] === CAGE_TEMPLATE_KEY)
  const extras: ActivityRow[] = []
  const existing = new Set(db.Activities.map((row) => row['Activity ID']))

  if (essenceTemplate && !existing.has(GUILD_HALL_ESSENCE_ACTIVITY_ID)) {
    extras.push({
      ...essenceTemplate,
      'Activity ID': GUILD_HALL_ESSENCE_ACTIVITY_ID,
      'Internal Key': 'guild_hall_harness_essence',
      'Location ID': GUILD_HALL_LOCATION_ID,
      'Contextual Name': 'Harness essence',
      Description: 'The hall Arcana station. Same work as the Wizard\'s Tower.',
    })
  }
  if (cageTemplate && !existing.has(GUILD_HALL_CAGE_ACTIVITY_ID)) {
    extras.push({
      ...cageTemplate,
      'Activity ID': GUILD_HALL_CAGE_ACTIVITY_ID,
      'Internal Key': 'guild_hall_monster_cage',
      'Location ID': GUILD_HALL_LOCATION_ID,
      'Contextual Name': 'Challenge the cage',
      Description: 'A training enemy. XP only — nothing drops.',
      Notes: GUILD_HALL_CAGE_NOTE,
    })
  }
  if (extras.length === 0) return db
  return { ...db, Activities: [...db.Activities, ...extras] }
}

export function guildHallRoomActivityVisible(
  activityId: string,
  completedTiers: string[],
): boolean {
  if (isGuildHallEssenceActivity(activityId)) return guildHallArcanaUnlocked(completedTiers)
  if (isGuildHallCageActivity(activityId)) return guildHallCageUnlocked(completedTiers)
  return true
}

export function guildHallGardenPatchOpen(completedTiers: string[]): boolean {
  return guildHallGardenUnlocked(completedTiers)
}
