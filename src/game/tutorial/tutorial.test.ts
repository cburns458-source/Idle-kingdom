import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { completeGatheringAction, generateNextAction, validateActivityStart } from '../activity/engine'
import { activityVisibleForSave } from '../activity/requirements'
import { addItemToInventory } from '../activity/rewards'
import { applyCombatDefeat, applyCombatVictory, enemyForAction } from '../combat/engine'
import { isEdibleItem } from '../combat/food'
import { FOOD_SLOT_ID } from '../equipment/loadout'
import { prepareDatabase } from '../data/loadDatabase'
import { npcsAtLocationForSave } from '../npcs/knowledge'
import { completeProductionCraft } from '../production/engine'
import { recipesForActivity } from '../production/recipes'
import { assignRace } from '../races/assignRace'
import { migrateSave } from '../save/migrations'
import { createNewSave, parseSave } from '../save/saveStore'
import { SAVE_VERSION, type PlayerSave } from '../save/types'
import { canTravelTo, applyTravelArrival } from '../world/travel'
import {
  applyTutorialCowKill,
  applyTutorialLockback,
  ensureGettingStartedAccepted,
  isTutorialActivityAllowed,
  isTutorialBazaarAllowed,
  isTutorialLocationAllowed,
  isTutorialLocked,
  isTutorialSkillMenuAllowed,
  TUTORIAL_BAKED_POTATO_ITEM_ID,
  TUTORIAL_COMBAT_STEP_ID,
  TUTORIAL_COOK_ACTIVITY_ID,
  TUTORIAL_COW_ACTION_ID,
  TUTORIAL_COW_ENEMY_ID,
  TUTORIAL_FAREWELL_FLAG,
  TUTORIAL_FIELDS_ACTIVITY_ID,
  TUTORIAL_FOOD_GRANT_FLAG,
  TUTORIAL_KITCHEN_LOCATION_ID,
  TUTORIAL_LOCKBACK_FLAG,
  TUTORIAL_LOSS_FLAG,
  TUTORIAL_PASTURE_ACTIVITY_ID,
  TUTORIAL_POTATO_ITEM_ID,
  TUTORIAL_POTATO_RECIPE_ID,
  TUTORIAL_QUEST_ID,
  tutorialCombatStepActive,
  tutorialForcedAction,
  tutorialGuaranteedCooksUsed,
  tutorialGuaranteedGathersUsed,
} from './tutorial'
import { getQuest, getQuestProgress } from '../quests/quests'
import { applyQuestStepUnlocks, getCurrentStepId, isStepLatched } from '../quests/steps'

const rawDatabase = JSON.parse(readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'))
const { launch: db } = prepareDatabase(rawDatabase)
const NOW = Date.parse('2026-10-16T00:00:00.000Z')
const FARM = 'LOC-0001'
const TOWN = 'LOC-0002'
const COPPER_MINE = 'LOC-0003'
const MAIN_MAP = 'MAP-0001'

function activeTutorial(locationId = FARM): PlayerSave {
  const assigned = assignRace(db, { ...createNewSave(db, NOW), currentLocationId: locationId }, 'RACE-0001')
  if (!assigned.ok) throw new Error(assigned.reason)
  return assigned.save
}

function withoutFood(save: PlayerSave): PlayerSave {
  const slots = { ...save.equipment.slots }
  delete slots[FOOD_SLOT_ID]
  return {
    ...save,
    inventory: save.inventory.filter((stack) => !isEdibleItem(db, stack.itemId)),
    bank: (save.bank ?? []).filter((stack) => !isEdibleItem(db, stack.itemId)),
    equipment: { ...save.equipment, slots },
  }
}

function combatStepSave(): PlayerSave {
  let save = withoutFood(activeTutorial())
  save = {
    ...save,
    quests: save.quests.map((quest) =>
      quest.questId === TUTORIAL_QUEST_ID
        ? {
            ...quest,
            counters: {
              'step:QSTP-0013': 1,
              'step:QSTP-0014': 1,
              'step:QSTP-0015': 1,
              'step:QSTP-0016': 1,
            },
          }
        : quest,
    ),
  }
  return applyQuestStepUnlocks(db, save)
}

function withItem(save: PlayerSave, itemId: string, quantity: number): PlayerSave {
  const cleared = { ...save, inventory: save.inventory.filter((stack) => stack.itemId !== itemId) }
  return quantity > 0 ? addItemToInventory(cleared, itemId, quantity) : cleared
}

describe('mandatory Getting Started tutorial', () => {
  it('auto-accepts Getting Started on first race pick and locks the world', () => {
    const save = activeTutorial()
    expect(getQuestProgress(save, TUTORIAL_QUEST_ID).status).toBe('active')
    expect(isTutorialLocked(save)).toBe(true)
    expect(isTutorialLocationAllowed(save, FARM)).toBe(true)
    expect(isTutorialLocationAllowed(save, TOWN)).toBe(false)
    expect(isTutorialLocationAllowed(save, COPPER_MINE)).toBe(false)
    expect(isTutorialActivityAllowed(save, TUTORIAL_FIELDS_ACTIVITY_ID)).toBe(true)
    expect(isTutorialActivityAllowed(save, TUTORIAL_PASTURE_ACTIVITY_ID)).toBe(false)
    expect(isTutorialActivityAllowed(save, TUTORIAL_COOK_ACTIVITY_ID)).toBe(false)
    expect(isTutorialSkillMenuAllowed(save)).toBe(false)
    expect(isTutorialBazaarAllowed(save)).toBe(false)
    expect(npcsAtLocationForSave(db, save, FARM).map((npc) => npc['NPC ID'])).toEqual(['NPC-0014'])
  })

  it('opens the kitchen path only on the cook and show-cooked steps', () => {
    const gathering = activeTutorial()
    expect(isTutorialLocationAllowed(gathering, TUTORIAL_KITCHEN_LOCATION_ID)).toBe(false)
    let cooking = {
      ...gathering,
      quests: gathering.quests.map((quest) =>
        quest.questId === TUTORIAL_QUEST_ID
          ? { ...quest, counters: { 'step:QSTP-0013': 1, 'step:QSTP-0014': 1 } }
          : quest,
      ),
    }
    cooking = applyQuestStepUnlocks(db, cooking)
    expect(isTutorialLocationAllowed(cooking, TUTORIAL_KITCHEN_LOCATION_ID)).toBe(true)
    expect(isTutorialActivityAllowed(cooking, TUTORIAL_COOK_ACTIVITY_ID)).toBe(true)
    expect(canTravelTo(db, FARM, TOWN, MAIN_MAP, cooking)).toBe(true)
    expect(canTravelTo(db, FARM, COPPER_MINE, MAIN_MAP, cooking)).toBe(false)
  })

  it('refuses locked locations and activities on travel, start, and visibility', () => {
    const save = activeTutorial()
    expect(canTravelTo(db, FARM, COPPER_MINE, MAIN_MAP, save)).toBe(false)
    const refused = applyTravelArrival(db, save, COPPER_MINE, NOW)
    expect(refused.currentLocationId).toBe(FARM)
    expect(tutorialGuaranteedGathersUsed(refused)).toBe(tutorialGuaranteedGathersUsed(save))
    expect(validateActivityStart(db, save, TUTORIAL_PASTURE_ACTIVITY_ID).ok).toBe(false)
    expect(activityVisibleForSave(db, save, TUTORIAL_PASTURE_ACTIVITY_ID)).toBe(false)
    expect(validateActivityStart(db, { ...save, currentLocationId: TUTORIAL_KITCHEN_LOCATION_ID }, TUTORIAL_COOK_ACTIVITY_ID).ok).toBe(false)
  })

  it('guarantees the first five potato gathers, persists the count across reload', () => {
    let save = activeTutorial()
    const potato = db.Actions.find((row) => row['Action ID'] === 'ACN-0035')!
    for (let i = 0; i < 5; i += 1) {
      expect(tutorialForcedAction(db, save, TUTORIAL_FIELDS_ACTIVITY_ID)?.['Action ID']).toBe('ACN-0035')
      const done = completeGatheringAction(db, save, potato, () => 0.999, NOW)
      save = done.save
      expect(done.result.loot.map((drop) => drop.itemId)).toEqual([TUTORIAL_POTATO_ITEM_ID])
      expect(tutorialGuaranteedGathersUsed(save)).toBe(i + 1)
    }
    expect(tutorialForcedAction(db, save, TUTORIAL_FIELDS_ACTIVITY_ID)).toBeNull()
    const reloaded = parseSave(JSON.parse(JSON.stringify(save)), NOW)
    expect(tutorialGuaranteedGathersUsed(reloaded)).toBe(5)
    expect(reloaded.saveVersion).toBe(SAVE_VERSION)
  })

  it('guarantees the first five potato cooks then uses normal odds', () => {
    let save: PlayerSave = {
      ...activeTutorial(),
      currentLocationId: TUTORIAL_KITCHEN_LOCATION_ID,
      productionRecipeId: TUTORIAL_POTATO_RECIPE_ID,
      productionQuantityRemaining: 6,
      productionQuantityTotal: 6,
    }
    save = withItem(save, TUTORIAL_POTATO_ITEM_ID, 6)
    save = applyQuestStepUnlocks(db, {
      ...save,
      quests: save.quests.map((quest) =>
        quest.questId === TUTORIAL_QUEST_ID
          ? { ...quest, counters: { 'step:QSTP-0013': 1, 'step:QSTP-0014': 1 } }
          : quest,
      ),
    })
    expect(recipesForActivity(db, save, TUTORIAL_COOK_ACTIVITY_ID).map((row) => row['Recipe ID'])).toEqual([
      TUTORIAL_POTATO_RECIPE_ID,
    ])
    for (let i = 0; i < 5; i += 1) {
      const craft = completeProductionCraft(db, save, NOW + i, () => 0.999)
      expect(craft?.failed).toBe(false)
      expect(craft?.outputQty).toBeGreaterThan(0)
      save = craft!.save
      expect(tutorialGuaranteedCooksUsed(save)).toBe(i + 1)
    }
    expect(tutorialGuaranteedCooksUsed(parseSave(JSON.parse(JSON.stringify(save)), NOW))).toBe(5)
  })

  it('forces the first pasture fight to be a Cow, including retries', () => {
    const save = combatStepSave()
    expect(tutorialCombatStepActive(save)).toBe(true)
    expect(tutorialForcedAction(db, save, TUTORIAL_PASTURE_ACTIVITY_ID)?.['Action ID']).toBe(TUTORIAL_COW_ACTION_ID)
    const rolled = generateNextAction(db, save, TUTORIAL_PASTURE_ACTIVITY_ID, () => 0.999, NOW)
    expect(rolled?.action['Action ID']).toBe(TUTORIAL_COW_ACTION_ID)
    expect(enemyForAction(db, rolled!.action)?.['Enemy ID']).toBe(TUTORIAL_COW_ENEMY_ID)
  })

  it('grants Fennel food once per death only when the bag, bank, and food slot are empty', () => {
    const empty = applyCombatDefeat(db, combatStepSave(), NOW)
    expect(empty.dialogueFlags).toContain(TUTORIAL_LOSS_FLAG)
    expect(empty.dialogueFlags).toContain(TUTORIAL_FOOD_GRANT_FLAG)
    expect(empty.inventory.some((stack) => stack.itemId === TUTORIAL_BAKED_POTATO_ITEM_ID && stack.quantity === 5)).toBe(true)
    const again = applyCombatDefeat(db, empty, NOW)
    expect(again.tutorialFoodGrantDeathAt).toBe(empty.tutorialFoodGrantDeathAt)
    expect(
      again.inventory.find((stack) => stack.itemId === TUTORIAL_BAKED_POTATO_ITEM_ID)?.quantity,
    ).toBe(5)

    const withBagFood = applyCombatDefeat(db, withItem(combatStepSave(), TUTORIAL_BAKED_POTATO_ITEM_ID, 1), NOW)
    expect(withBagFood.dialogueFlags).toContain(TUTORIAL_LOSS_FLAG)
    expect(withBagFood.dialogueFlags).not.toContain(TUTORIAL_FOOD_GRANT_FLAG)

    const banked = applyCombatDefeat(db, {
      ...combatStepSave(),
      bank: [{ itemId: TUTORIAL_BAKED_POTATO_ITEM_ID, quantity: 1 }],
    }, NOW)
    expect(banked.dialogueFlags).not.toContain(TUTORIAL_FOOD_GRANT_FLAG)

    const slotted = applyCombatDefeat(db, {
      ...combatStepSave(),
      equipment: {
        slots: {
          ...combatStepSave().equipment.slots,
          [FOOD_SLOT_ID]: { itemId: TUTORIAL_BAKED_POTATO_ITEM_ID, quantity: 1 },
        },
      },
    }, NOW)
    expect(slotted.dialogueFlags).not.toContain(TUTORIAL_FOOD_GRANT_FLAG)
  })

  it('completes the quest on one cow kill, stops combat, unlocks the world, and grants rewards once', () => {
    const before = combatStepSave()
    const action = db.Actions.find((row) => row['Action ID'] === TUTORIAL_COW_ACTION_ID)!
    const enemy = db.Enemies.find((row) => row['Enemy ID'] === TUTORIAL_COW_ENEMY_ID)!
    const fighting = {
      ...before,
      currentActivityId: TUTORIAL_PASTURE_ACTIVITY_ID,
      combatEnemyId: TUTORIAL_COW_ENEMY_ID,
      combatEnemyHp: 1,
    }
    const victory = applyCombatVictory(db, fighting, action, enemy, () => 0, NOW)
    expect(getQuestProgress(victory.save, TUTORIAL_QUEST_ID).status).toBe('completed')
    expect(victory.save.currentActivityId).toBeNull()
    expect(victory.save.combatEnemyId).toBeNull()
    expect(isTutorialLocked(victory.save)).toBe(false)
    expect(isTutorialLocationAllowed(victory.save, COPPER_MINE)).toBe(true)
    expect(isTutorialSkillMenuAllowed(victory.save)).toBe(true)
    expect(victory.save.dialogueFlags).toContain(TUTORIAL_FAREWELL_FLAG)
    expect(victory.save.unlockedBookIds).toContain('BOOK-0001')

    const twice = applyTutorialCowKill(db, victory.save, TUTORIAL_COW_ENEMY_ID)
    expect(twice.completed).toBe(false)
    expect(getQuestProgress(twice.save, TUTORIAL_QUEST_ID).status).toBe('completed')
  })

  it('locks in-progress players back without dropping items or bazaar state', () => {
    const mid = {
      ...activeTutorial(TOWN),
      currentActivityId: 'ACT-0008',
      unlockedLocationIds: [COPPER_MINE],
      tutorialGuaranteedGathers: 3,
    }
    const locked = applyTutorialLockback(mid)
    expect(locked.dialogueFlags).toContain(TUTORIAL_LOCKBACK_FLAG)
    expect(locked.currentLocationId).toBe(FARM)
    expect(locked.currentActivityId).toBeNull()
    expect(locked.tutorialGuaranteedGathers).toBe(3)
    expect(getQuestProgress(locked, TUTORIAL_QUEST_ID).status).toBe('active')

    const finished = applyTutorialLockback({
      ...mid,
      quests: [{ questId: TUTORIAL_QUEST_ID, status: 'completed', progress: 1 }],
    })
    expect(finished.currentLocationId).toBe(TOWN)
    expect(finished.dialogueFlags).not.toContain(TUTORIAL_LOCKBACK_FLAG)

    const migrated = migrateSave({ ...mid, saveVersion: 66 }, NOW)
    expect(migrated.saveVersion).toBe(67)
    expect(migrated.currentLocationId).toBe(FARM)
    expect(migrated.dialogueFlags).toContain(TUTORIAL_LOCKBACK_FLAG)
  })

  it('keeps step progress across reload while the combat step is open', () => {
    const save = parseSave(JSON.parse(JSON.stringify(combatStepSave())), NOW)
    expect(getCurrentStepId(db, save, getQuest(db, TUTORIAL_QUEST_ID)!)).toBe(
      TUTORIAL_COMBAT_STEP_ID,
    )
    expect(isStepLatched(save, TUTORIAL_QUEST_ID, 'QSTP-0016')).toBe(true)
    expect(ensureGettingStartedAccepted(db, save)).toBe(save)
  })
})
