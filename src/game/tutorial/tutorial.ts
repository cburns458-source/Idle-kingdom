/**
 * Mandatory Getting Started tutorial (QST-0006 / QST-02).
 *
 * Unlock flags, gather/cook guarantees, the forced cow fight, Fennel's food
 * top-up, and lock-back migration. Dart port: packages/ik_rules/lib/src/tutorial/tutorial.dart.
 */

import { addItemsToInventory } from '../activity/rewards'
import { isEdibleItem } from '../combat/food'
import type { ActionRow, GameDatabase } from '../data/types'
import { FOOD_SLOT_ID, slotStack } from '../equipment/loadout'
import { inventoryCount } from '../production/recipes'
import { acceptQuest, completeQuest, getQuest, getQuestProgress } from '../quests/quests'
import { applyQuestStepUnlocks, getCurrentStepId, isStepLatched } from '../quests/steps'
import {
  STARTING_BAKED_POTATO_ID,
  STARTING_BAKED_POTATO_QTY,
  type PlayerSave,
} from '../save/types'

export const TUTORIAL_QUEST_ID = 'QST-0006'
export const TUTORIAL_NPC_ID = 'NPC-0014'
export const TUTORIAL_FARM_LOCATION_ID = 'LOC-0001'
export const TUTORIAL_TOWN_GATEWAY_LOCATION_ID = 'LOC-0002'
export const TUTORIAL_TOWN_SQUARE_LOCATION_ID = 'LOC-0054'
export const TUTORIAL_KITCHEN_LOCATION_ID = 'LOC-0023'
export const TUTORIAL_FIELDS_ACTIVITY_ID = 'ACT-0021'
export const TUTORIAL_PASTURE_ACTIVITY_ID = 'ACT-0001'
export const TUTORIAL_COOK_ACTIVITY_ID = 'ACT-0017'
export const TUTORIAL_POTATO_ACTION_ID = 'ACN-0035'
export const TUTORIAL_COW_ACTION_ID = 'ACN-0001'
export const TUTORIAL_POTATO_ITEM_ID = 'ITEM-0025'
export const TUTORIAL_BAKED_POTATO_ITEM_ID = STARTING_BAKED_POTATO_ID
export const TUTORIAL_POTATO_RECIPE_ID = 'RCP-0001'
export const TUTORIAL_COW_ENEMY_ID = 'ENM-0001'
export const TUTORIAL_STARTER_SWORD_ID = 'ITEM-0124'
export const TUTORIAL_STARTER_SHIELD_ID = 'ITEM-0145'
export const TUTORIAL_WEAPON_SLOT_ID = 'SLOT-0001'
export const TUTORIAL_OFFHAND_SLOT_ID = 'SLOT-0002'
export const TUTORIAL_GATHER_GUARANTEE_COUNT = 5
export const TUTORIAL_COOK_GUARANTEE_COUNT = 5
export const TUTORIAL_FOOD_TOP_UP_QTY = STARTING_BAKED_POTATO_QTY

export const TUTORIAL_GATHER_STEP_ID = 'QSTP-0013'
export const TUTORIAL_SHOW_POTATOES_STEP_ID = 'QSTP-0014'
export const TUTORIAL_COOK_STEP_ID = 'QSTP-0015'
export const TUTORIAL_SHOW_COOKED_STEP_ID = 'QSTP-0016'
export const TUTORIAL_COMBAT_STEP_ID = 'QSTP-0022'

export const TUTORIAL_FAREWELL_FLAG = 'tutorial:farewell'
export const TUTORIAL_LOCKBACK_FLAG = 'tutorial:lockback'
export const TUTORIAL_FOOD_GRANT_FLAG = 'tutorial:food_grant'
export const TUTORIAL_LOSS_FLAG = 'tutorial:loss'

const TUTORIAL_STEP_ORDER = [
  TUTORIAL_GATHER_STEP_ID,
  TUTORIAL_SHOW_POTATOES_STEP_ID,
  TUTORIAL_COOK_STEP_ID,
  TUTORIAL_SHOW_COOKED_STEP_ID,
  TUTORIAL_COMBAT_STEP_ID,
] as const

const TUTORIAL_COOK_PATH_LOCATION_IDS = [
  TUTORIAL_FARM_LOCATION_ID,
  TUTORIAL_TOWN_GATEWAY_LOCATION_ID,
  TUTORIAL_TOWN_SQUARE_LOCATION_ID,
  TUTORIAL_KITCHEN_LOCATION_ID,
] as const

export type TutorialSpotlightId =
  | 'fennel'
  | 'fields'
  | 'map-town'
  | 'kitchen-cook'
  | 'sword'
  | 'shield'
  | 'pasture'
  | 'food-slot'

export interface TutorialHudHint {
  label: string
  locationId: string
  activityId: string | null
  spotlight: TutorialSpotlightId | null
}

export function tutorialGuaranteedGathersUsed(save: PlayerSave): number {
  return Math.max(0, Math.floor(Number(save.tutorialGuaranteedGathers) || 0))
}

export function tutorialGuaranteedCooksUsed(save: PlayerSave): number {
  return Math.max(0, Math.floor(Number(save.tutorialGuaranteedCooks) || 0))
}

export function hasTutorialFlag(save: PlayerSave, flag: string): boolean {
  return (save.dialogueFlags ?? []).includes(flag)
}

export function withTutorialFlag(save: PlayerSave, flag: string, on: boolean): PlayerSave {
  const current = save.dialogueFlags ?? []
  if (current.includes(flag) === on) return save
  const next = on ? [...current, flag] : current.filter((entry) => entry !== flag)
  return { ...save, dialogueFlags: [...next].sort() }
}

export function isGettingStartedComplete(save: PlayerSave): boolean {
  return getQuestProgress(save, TUTORIAL_QUEST_ID).status === 'completed'
}

export function isGettingStartedActive(save: PlayerSave): boolean {
  return getQuestProgress(save, TUTORIAL_QUEST_ID).status === 'active'
}

/** True while Getting Started is active: the world stays locked to the tutorial. */
export function isTutorialLocked(save: PlayerSave): boolean {
  return isGettingStartedActive(save)
}

export function tutorialCurrentStepId(db: GameDatabase, save: PlayerSave): string | null {
  if (!isGettingStartedActive(save)) return null
  const quest = getQuest(db, TUTORIAL_QUEST_ID)
  if (!quest) return null
  return getCurrentStepId(db, save, quest)
}

/** Step id from latched counters only — safe in save migrations that have no database. */
export function tutorialStepIdFromCounters(save: PlayerSave): string | null {
  if (!isGettingStartedActive(save)) return null
  for (const stepId of TUTORIAL_STEP_ORDER) {
    if (!isStepLatched(save, TUTORIAL_QUEST_ID, stepId)) return stepId
  }
  return TUTORIAL_COMBAT_STEP_ID
}

export function tutorialKitchenPathOpen(save: PlayerSave): boolean {
  if (!isTutorialLocked(save)) return false
  const stepId = tutorialStepIdFromCounters(save)
  return stepId === TUTORIAL_COOK_STEP_ID || stepId === TUTORIAL_SHOW_COOKED_STEP_ID
}

export function tutorialCombatStepActive(save: PlayerSave): boolean {
  return isTutorialLocked(save) && tutorialStepIdFromCounters(save) === TUTORIAL_COMBAT_STEP_ID
}

export function isTutorialLocationAllowed(save: PlayerSave, locationId: string): boolean {
  if (!isTutorialLocked(save)) return true
  if (locationId === TUTORIAL_FARM_LOCATION_ID) return true
  if (!tutorialKitchenPathOpen(save)) return false
  return (TUTORIAL_COOK_PATH_LOCATION_IDS as readonly string[]).includes(locationId)
}

export function isTutorialActivityAllowed(save: PlayerSave, activityId: string): boolean {
  if (!isTutorialLocked(save)) return true
  if (activityId === TUTORIAL_FIELDS_ACTIVITY_ID) return true
  if (activityId === TUTORIAL_COOK_ACTIVITY_ID) return tutorialKitchenPathOpen(save)
  if (activityId === TUTORIAL_PASTURE_ACTIVITY_ID) return tutorialCombatStepActive(save)
  return false
}

export function isTutorialRecipeAllowed(save: PlayerSave, recipeId: string): boolean {
  if (!isTutorialLocked(save)) return true
  return recipeId === TUTORIAL_POTATO_RECIPE_ID && tutorialKitchenPathOpen(save)
}

export function isTutorialNpcAllowed(save: PlayerSave, npcId: string): boolean {
  if (!isTutorialLocked(save)) return true
  return npcId === TUTORIAL_NPC_ID
}

export function isTutorialSkillMenuAllowed(save: PlayerSave): boolean {
  return !isTutorialLocked(save)
}

export function isTutorialBazaarAllowed(save: PlayerSave): boolean {
  return !isTutorialLocked(save)
}

export function isTutorialGuildHallAllowed(save: PlayerSave): boolean {
  return !isTutorialLocked(save)
}

export function tutorialForcedGatherRemaining(save: PlayerSave): number {
  if (!isTutorialLocked(save)) return 0
  return Math.max(0, TUTORIAL_GATHER_GUARANTEE_COUNT - tutorialGuaranteedGathersUsed(save))
}

export function tutorialForcedCookRemaining(save: PlayerSave): number {
  if (!isTutorialLocked(save)) return 0
  return Math.max(0, TUTORIAL_COOK_GUARANTEE_COUNT - tutorialGuaranteedCooksUsed(save))
}

export function shouldGuaranteeTutorialGather(save: PlayerSave): boolean {
  return tutorialForcedGatherRemaining(save) > 0
}

export function shouldGuaranteeTutorialCook(save: PlayerSave, recipeId: string): boolean {
  return recipeId === TUTORIAL_POTATO_RECIPE_ID && tutorialForcedCookRemaining(save) > 0
}

export function noteTutorialGuaranteedGather(save: PlayerSave): PlayerSave {
  if (!shouldGuaranteeTutorialGather(save)) return save
  return {
    ...save,
    tutorialGuaranteedGathers: tutorialGuaranteedGathersUsed(save) + 1,
  }
}

export function applyTutorialGuaranteedPotatoGather(
  db: GameDatabase,
  save: PlayerSave,
): {
  save: PlayerSave
  loot: { itemId: string; quantity: number; displayName: string }[]
  goldGained: number
  cosmeticsGranted: { cosmeticId: string; isFirstEver: boolean }[]
  booksGranted: { bookId: string; isFirstEver: boolean }[]
  leftBehind: { itemId: string; quantity: number; displayName: string }[]
} {
  const noted = noteTutorialGuaranteedGather(save)
  const granted = addItemsToInventory(noted, TUTORIAL_POTATO_ITEM_ID, 1, null, false, db)
  const displayName =
    db.Items.find((item) => item['Item ID'] === TUTORIAL_POTATO_ITEM_ID)?.['Display Name'] ??
    'Potato'
  const loot =
    granted.added > 0
      ? [{ itemId: TUTORIAL_POTATO_ITEM_ID, quantity: granted.added, displayName }]
      : []
  const leftBehind =
    granted.added < 1
      ? [{ itemId: TUTORIAL_POTATO_ITEM_ID, quantity: 1 - granted.added, displayName }]
      : []
  return {
    save: granted.save,
    loot,
    goldGained: 0,
    cosmeticsGranted: [],
    booksGranted: [],
    leftBehind,
  }
}

export function noteTutorialGuaranteedCook(save: PlayerSave, recipeId: string): PlayerSave {
  if (!shouldGuaranteeTutorialCook(save, recipeId)) return save
  return {
    ...save,
    tutorialGuaranteedCooks: tutorialGuaranteedCooksUsed(save) + 1,
  }
}

export function tutorialForcedAction(
  db: GameDatabase,
  save: PlayerSave,
  activityId: string,
): ActionRow | null {
  if (!isTutorialLocked(save)) return null
  if (activityId === TUTORIAL_FIELDS_ACTIVITY_ID && shouldGuaranteeTutorialGather(save)) {
    return db.Actions.find((row) => row['Action ID'] === TUTORIAL_POTATO_ACTION_ID) ?? null
  }
  if (activityId === TUTORIAL_PASTURE_ACTIVITY_ID && tutorialCombatStepActive(save)) {
    return db.Actions.find((row) => row['Action ID'] === TUTORIAL_COW_ACTION_ID) ?? null
  }
  return null
}

function edibleQuantity(db: GameDatabase, stacks: { itemId: string; quantity: number }[]): number {
  let total = 0
  for (const stack of stacks) {
    if (!isEdibleItem(db, stack.itemId)) continue
    total += Math.max(0, Math.floor(Number(stack.quantity) || 0))
  }
  return total
}

/** Food in the bag, bank, or food slot. Banking/selling to look empty does not work. */
export function tutorialHasAnyFood(db: GameDatabase, save: PlayerSave): boolean {
  const equipped = slotStack(save, FOOD_SLOT_ID)
  const equippedStacks = equipped ? [equipped] : []
  return (
    edibleQuantity(db, save.inventory) +
      edibleQuantity(db, save.bank) +
      edibleQuantity(db, equippedStacks) >
    0
  )
}

export function shouldGrantTutorialDeathFood(db: GameDatabase, save: PlayerSave): boolean {
  if (!tutorialCombatStepActive(save)) return false
  if (!save.deathPauseUntil) return false
  if (save.tutorialFoodGrantDeathAt === save.deathPauseUntil) return false
  return !tutorialHasAnyFood(db, save)
}

export function applyTutorialDeathFoodGrant(db: GameDatabase, save: PlayerSave): PlayerSave {
  if (!shouldGrantTutorialDeathFood(db, save)) return save
  const granted = addItemsToInventory(save, TUTORIAL_BAKED_POTATO_ITEM_ID, TUTORIAL_FOOD_TOP_UP_QTY)
  return withTutorialFlag(
    {
      ...granted.save,
      tutorialFoodGrantDeathAt: save.deathPauseUntil,
    },
    TUTORIAL_FOOD_GRANT_FLAG,
    true,
  )
}

/** Loss line always; food top-up only when the bag, bank, and food slot are empty. */
export function applyTutorialCombatDefeat(db: GameDatabase, save: PlayerSave): PlayerSave {
  if (!tutorialCombatStepActive(save)) return save
  return applyTutorialDeathFoodGrant(db, withTutorialFlag(save, TUTORIAL_LOSS_FLAG, true))
}

function stopRunningAction(save: PlayerSave): PlayerSave {
  return {
    ...save,
    currentActivityId: null,
    activityStartedAt: null,
    currentActionId: null,
    actionStartedAt: null,
    actionDurationMs: null,
    activityTransition: null,
    combatEnemyId: null,
    combatEnemyHp: null,
    combatRoundStartedAt: null,
    combatManualEatRoundStartedAt: null,
    combatPlayerSwingApplied: false,
    combatPendingRound: null,
    combatEatUntil: null,
    combatContinueActivityAfterEat: false,
    combatSkipEnemyAttack: false,
    combatBossSleepRoundsRemaining: null,
    combatBossPendingId: null,
    combatBossPendingHp: null,
    combatBossAddsRemaining: null,
    combatBossAddsTriggered: false,
    combatBossInkActive: false,
    productionRecipeId: null,
    productionQuantityTotal: null,
    productionQuantityRemaining: null,
    heldActionByActivityId: {},
  }
}

/**
 * Existing players still on Getting Started are locked back in: illegal
 * activities stop, travel out of a now-hidden place returns them to the farm,
 * and Fennel has a one-time lock-back line. Bazaar orders are not touched.
 */
export function applyTutorialLockback(save: PlayerSave): PlayerSave {
  if (!isGettingStartedActive(save)) {
    return {
      ...save,
      tutorialGuaranteedGathers: tutorialGuaranteedGathersUsed(save),
      tutorialGuaranteedCooks: tutorialGuaranteedCooksUsed(save),
      tutorialFoodGrantDeathAt: save.tutorialFoodGrantDeathAt ?? null,
    }
  }

  let next: PlayerSave = {
    ...save,
    tutorialGuaranteedGathers: tutorialGuaranteedGathersUsed(save),
    tutorialGuaranteedCooks: tutorialGuaranteedCooksUsed(save),
    tutorialFoodGrantDeathAt: save.tutorialFoodGrantDeathAt ?? null,
  }
  next = withTutorialFlag(next, TUTORIAL_LOCKBACK_FLAG, true)

  const locationAllowed = isTutorialLocationAllowed(next, next.currentLocationId)
  const activityId = next.currentActivityId
  const activityAllowed = !activityId || isTutorialActivityAllowed(next, activityId)
  if (!locationAllowed || !activityAllowed) {
    next = stopRunningAction(next)
  }
  if (!locationAllowed) {
    next = { ...next, currentLocationId: TUTORIAL_FARM_LOCATION_ID }
  }
  return next
}

export function ensureGettingStartedAccepted(db: GameDatabase, save: PlayerSave): PlayerSave {
  const progress = getQuestProgress(save, TUTORIAL_QUEST_ID)
  if (progress.status === 'active' || progress.status === 'completed') return save
  const accepted = acceptQuest(db, save, TUTORIAL_QUEST_ID, { ignoreLocation: true })
  return accepted.ok ? accepted.save : save
}

export function shouldStopTutorialCombatAfterKill(
  save: PlayerSave,
  enemyId: string,
): boolean {
  return tutorialCombatStepActive(save) && enemyId === TUTORIAL_COW_ENEMY_ID
}

export function applyTutorialCowKill(
  db: GameDatabase,
  save: PlayerSave,
  enemyId: string,
): { save: PlayerSave; completed: boolean } {
  if (!shouldStopTutorialCombatAfterKill(save, enemyId)) {
    return { save, completed: false }
  }
  if (isGettingStartedComplete(save)) {
    return { save: stopRunningAction(save), completed: true }
  }

  let next = applyQuestStepUnlocks(db, save)
  const finished = completeQuest(db, next, TUTORIAL_QUEST_ID, { ignoreLocation: true })
  if (!finished.ok) {
    return { save: stopRunningAction(next), completed: false }
  }
  next = stopRunningAction(finished.save)
  next = withTutorialFlag(next, TUTORIAL_FAREWELL_FLAG, true)
  next = withTutorialFlag(next, TUTORIAL_FOOD_GRANT_FLAG, false)
  next = withTutorialFlag(next, TUTORIAL_LOCKBACK_FLAG, false)
  next = withTutorialFlag(next, TUTORIAL_LOSS_FLAG, false)
  return { save: next, completed: true }
}

export function isTutorialSwordEquipped(save: PlayerSave): boolean {
  return slotStack(save, TUTORIAL_WEAPON_SLOT_ID)?.itemId === TUTORIAL_STARTER_SWORD_ID
}

export function isTutorialShieldEquipped(save: PlayerSave): boolean {
  return slotStack(save, TUTORIAL_OFFHAND_SLOT_ID)?.itemId === TUTORIAL_STARTER_SHIELD_ID
}

export function tutorialHudHint(db: GameDatabase, save: PlayerSave): TutorialHudHint | null {
  if (hasTutorialFlag(save, TUTORIAL_FAREWELL_FLAG)) return null
  if (!isTutorialLocked(save)) return null
  const stepId = tutorialCurrentStepId(db, save) ?? tutorialStepIdFromCounters(save)
  if (!stepId) return null

  if (stepId === TUTORIAL_GATHER_STEP_ID) {
    const have = Math.min(5, inventoryCount(save, TUTORIAL_POTATO_ITEM_ID))
    return {
      label: `Gather potatoes ${have}/5`,
      locationId: TUTORIAL_FARM_LOCATION_ID,
      activityId: TUTORIAL_FIELDS_ACTIVITY_ID,
      spotlight: 'fields',
    }
  }
  if (stepId === TUTORIAL_SHOW_POTATOES_STEP_ID) {
    return {
      label: 'Show Fennel the potatoes',
      locationId: TUTORIAL_FARM_LOCATION_ID,
      activityId: null,
      spotlight: 'fennel',
    }
  }
  if (stepId === TUTORIAL_COOK_STEP_ID) {
    const cooked = Math.min(
      5,
      Number(getQuestProgress(save, TUTORIAL_QUEST_ID).counters?.[`process:${TUTORIAL_POTATO_RECIPE_ID}`] ?? 0),
    )
    const atKitchen = save.currentLocationId === TUTORIAL_KITCHEN_LOCATION_ID
    return {
      label: atKitchen ? `Cook potatoes ${cooked}/5` : 'Go to the kitchen in town',
      locationId: atKitchen ? TUTORIAL_KITCHEN_LOCATION_ID : TUTORIAL_TOWN_GATEWAY_LOCATION_ID,
      activityId: atKitchen ? TUTORIAL_COOK_ACTIVITY_ID : null,
      spotlight: atKitchen ? 'kitchen-cook' : 'map-town',
    }
  }
  if (stepId === TUTORIAL_SHOW_COOKED_STEP_ID) {
    return {
      label: 'Show Fennel the cooked potatoes',
      locationId: TUTORIAL_FARM_LOCATION_ID,
      activityId: null,
      spotlight: 'fennel',
    }
  }
  if (stepId === TUTORIAL_COMBAT_STEP_ID) {
    if (!isTutorialSwordEquipped(save)) {
      return {
        label: 'Equip your sword',
        locationId: TUTORIAL_FARM_LOCATION_ID,
        activityId: null,
        spotlight: 'sword',
      }
    }
    if (!isTutorialShieldEquipped(save)) {
      return {
        label: 'Equip your shield',
        locationId: TUTORIAL_FARM_LOCATION_ID,
        activityId: null,
        spotlight: 'shield',
      }
    }
    return {
      label: 'Fight a cow in the pasture',
      locationId: TUTORIAL_FARM_LOCATION_ID,
      activityId: TUTORIAL_PASTURE_ACTIVITY_ID,
      spotlight: 'pasture',
    }
  }
  return null
}
