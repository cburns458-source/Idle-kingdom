import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import {
  beginActivitySave,
  completeGatheringAction,
  generateNextAction,
  validateActivityStart,
} from '../activity/engine'
import { requestActivityStart } from '../activity/transition'
import { activityVisibleForSave } from '../activity/requirements'
import { addItemToInventory } from '../activity/rewards'
import {
  applyCombatDefeat,
  applyCombatVictory,
  applyDeathRecovery,
  enemyForAction,
} from '../combat/engine'
import { isEdibleItem } from '../combat/food'
import { equipItemFromInventory, FOOD_SLOT_ID } from '../equipment/loadout'
import { prepareDatabase } from '../data/loadDatabase'
import { chooseDialogue, dialoguesForNpc, startDialogue } from '../dialogue/engine'
import { npcsAtLocationForSave } from '../npcs/knowledge'
import { completeProductionCraft } from '../production/engine'
import { recipesForActivity } from '../production/recipes'
import { assignRace } from '../races/assignRace'
import { migrateSave } from '../save/migrations'
import { createNewSave, parseSave } from '../save/saveStore'
import { SAVE_VERSION, type PlayerSave } from '../save/types'
import { applyGameCommand } from '../server/authority'
import { resolveUnattendedProgress } from '../unattended/resolve'
import { bazaarTutorialLocked } from '../../../supabase/functions/_shared/bazaar_gate.ts'
import { canTravelTo, applyTravelArrival } from '../world/travel'
import {
  applyTutorialCowKill,
  applyTutorialLockback,
  ensureGettingStartedAccepted,
  tutorialAutoDialogueId,
  isTutorialActivityAllowed,
  isTutorialBazaarAllowed,
  isTutorialGuildHallAllowed,
  isTutorialLocationAllowed,
  isTutorialLocked,
  isTutorialShieldEquipped,
  isTutorialSkillMenuAllowed,
  isTutorialSwordEquipped,
  TUTORIAL_BAKED_POTATO_ITEM_ID,
  TUTORIAL_COMBAT_STEP_ID,
  TUTORIAL_COOK_ACTIVITY_ID,
  TUTORIAL_COOK_STEP_ID,
  TUTORIAL_COW_ACTION_ID,
  TUTORIAL_COW_ENEMY_ID,
  TUTORIAL_FAREWELL_FLAG,
  TUTORIAL_FIELDS_ACTIVITY_ID,
  TUTORIAL_FOOD_GRANT_FLAG,
  TUTORIAL_FOOD_TOP_UP_QTY,
  TUTORIAL_GATHER_STEP_ID,
  TUTORIAL_KITCHEN_LOCATION_ID,
  TUTORIAL_LOCKBACK_FLAG,
  TUTORIAL_LOSS_FLAG,
  TUTORIAL_NPC_ID,
  TUTORIAL_OFFHAND_SLOT_ID,
  TUTORIAL_PASTURE_ACTIVITY_ID,
  TUTORIAL_POTATO_ACTION_ID,
  TUTORIAL_POTATO_ITEM_ID,
  TUTORIAL_POTATO_RECIPE_ID,
  TUTORIAL_QUEST_ID,
  TUTORIAL_SHOW_COOKED_STEP_ID,
  TUTORIAL_SHOW_POTATOES_STEP_ID,
  TUTORIAL_STARTER_DAGGER_ID,
  TUTORIAL_STARTER_SHIELD_ID,
  TUTORIAL_STARTER_SWORD_ID,
  TUTORIAL_WEAPON_SLOT_ID,
  tutorialCombatStepActive,
  tutorialCurrentStepId,
  tutorialForcedAction,
  tutorialGuaranteedCooksUsed,
  tutorialGuaranteedGathersUsed,
  tutorialHudHint,
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

function combatStepSave(raceId = 'RACE-0001'): PlayerSave {
  const assigned = assignRace(db, { ...createNewSave(db, NOW), currentLocationId: FARM }, raceId)
  if (!assigned.ok) throw new Error(assigned.reason)
  let save = withoutFood(assigned.save)
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

function withEquipped(save: PlayerSave, slotId: string, itemId: string): PlayerSave {
  return {
    ...save,
    equipment: {
      ...save.equipment,
      slots: {
        ...save.equipment.slots,
        [slotId]: { itemId, quantity: 1 },
      },
    },
  }
}

function withLatchedSteps(save: PlayerSave, stepIds: string[]): PlayerSave {
  return applyQuestStepUnlocks(db, {
    ...save,
    quests: save.quests.map((quest) =>
      quest.questId === TUTORIAL_QUEST_ID
        ? { ...quest, counters: Object.fromEntries(stepIds.map((stepId) => [`step:${stepId}`, 1])) }
        : quest,
    ),
  })
}

function fightingCow(save: PlayerSave, enemyHp: number, playerHp: number): PlayerSave {
  return {
    ...beginActivitySave(save, TUTORIAL_PASTURE_ACTIVITY_ID, new Date(NOW).toISOString()),
    unattendedProgressAt: new Date(NOW).toISOString(),
    currentActionId: TUTORIAL_COW_ACTION_ID,
    combatEnemyId: TUTORIAL_COW_ENEMY_ID,
    combatEnemyHp: enemyHp,
    currentHp: playerHp,
    combatRoundStartedAt: new Date(NOW).toISOString(),
  }
}

function stackQty(save: PlayerSave, itemId: string): number {
  return save.inventory.reduce((total, stack) => total + (stack.itemId === itemId ? stack.quantity : 0), 0)
}

function reload(save: PlayerSave): PlayerSave {
  return parseSave(JSON.parse(JSON.stringify(save)), NOW)
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

  it('asks goblins to equip the wooden dagger instead of a shield', () => {
    const goblin = withEquipped(combatStepSave('RACE-0005'), TUTORIAL_WEAPON_SLOT_ID, TUTORIAL_STARTER_SWORD_ID)
    expect(tutorialHudHint(db, goblin)?.label).toBe('Equip your dagger')
    const goblinReady = withEquipped(goblin, TUTORIAL_OFFHAND_SLOT_ID, TUTORIAL_STARTER_DAGGER_ID)
    expect(tutorialHudHint(db, goblinReady)?.label).toBe('Fight a cow in the pasture')

    const human = withEquipped(combatStepSave('RACE-0001'), TUTORIAL_WEAPON_SLOT_ID, TUTORIAL_STARTER_SWORD_ID)
    expect(tutorialHudHint(db, human)?.label).toBe('Equip your shield')
    const humanReady = withEquipped(human, TUTORIAL_OFFHAND_SLOT_ID, TUTORIAL_STARTER_SHIELD_ID)
    expect(tutorialHudHint(db, humanReady)?.label).toBe('Fight a cow in the pasture')
  })

  it('first five potato gathers give exactly one potato and no other drop', () => {
    let save = activeTutorial()
    const potato = db.Actions.find((row) => row['Action ID'] === TUTORIAL_POTATO_ACTION_ID)!
    for (let i = 0; i < 5; i += 1) {
      const before = stackQty(save, TUTORIAL_POTATO_ITEM_ID)
      const done = completeGatheringAction(db, save, potato, () => 0.999, NOW)
      save = done.save
      expect(done.result.loot).toHaveLength(1)
      expect(done.result.loot[0]?.itemId).toBe(TUTORIAL_POTATO_ITEM_ID)
      expect(done.result.loot[0]?.quantity).toBe(1)
      expect(stackQty(save, TUTORIAL_POTATO_ITEM_ID)).toBe(before + 1)
    }
    expect(tutorialForcedAction(db, save, TUTORIAL_FIELDS_ACTIVITY_ID)).toBeNull()
    const later = generateNextAction(db, save, TUTORIAL_FIELDS_ACTIVITY_ID, () => 0.999, NOW)
    expect(later?.action['Action ID']).not.toBe(TUTORIAL_POTATO_ACTION_ID)
    expect(tutorialGuaranteedGathersUsed(reload(save))).toBe(5)
  })

  it('sixth potato cook uses normal odds after the guarantee', () => {
    let save: PlayerSave = {
      ...activeTutorial(),
      currentLocationId: TUTORIAL_KITCHEN_LOCATION_ID,
      productionRecipeId: TUTORIAL_POTATO_RECIPE_ID,
      productionQuantityRemaining: 6,
      productionQuantityTotal: 6,
    }
    save = withItem(save, TUTORIAL_POTATO_ITEM_ID, 6)
    save = withLatchedSteps(save, [TUTORIAL_GATHER_STEP_ID, TUTORIAL_SHOW_POTATOES_STEP_ID])
    for (let i = 0; i < 5; i += 1) {
      const craft = completeProductionCraft(db, save, NOW + i, () => 0.999)
      expect(craft?.failed).toBe(false)
      save = craft!.save
    }
    expect(tutorialGuaranteedCooksUsed(save)).toBe(5)
    const sixth = completeProductionCraft(db, save, NOW + 5, () => 0.999)
    if (!sixth) throw new Error('expected a sixth cook result')
    expect(sixth.failed).toBe(true)
    expect(sixth.outputQty).toBe(0)
    expect(tutorialGuaranteedCooksUsed(sixth.save)).toBe(5)
    expect(tutorialGuaranteedCooksUsed(reload(sixth.save))).toBe(5)
  })

  it('first pasture fight stays a Cow after a loss, never a bull', () => {
    const bullActionId = 'ACN-0002'
    const bullEnemyId = 'ENM-0002'
    const lost = applyCombatDefeat(db, combatStepSave(), NOW)
    expect(getQuestProgress(lost, TUTORIAL_QUEST_ID).status).toBe('active')
    expect(getCurrentStepId(db, lost, getQuest(db, TUTORIAL_QUEST_ID)!)).toBe(TUTORIAL_COMBAT_STEP_ID)
    expect(tutorialCombatStepActive(lost)).toBe(true)
    expect(tutorialForcedAction(db, lost, TUTORIAL_PASTURE_ACTIVITY_ID)?.['Action ID']).toBe(
      TUTORIAL_COW_ACTION_ID,
    )
    expect(tutorialForcedAction(db, lost, TUTORIAL_PASTURE_ACTIVITY_ID)?.['Action ID']).not.toBe(
      bullActionId,
    )

    const recovered = applyDeathRecovery(db, lost)
    expect(validateActivityStart(db, recovered, TUTORIAL_PASTURE_ACTIVITY_ID).ok).toBe(true)
    const retry = generateNextAction(db, recovered, TUTORIAL_PASTURE_ACTIVITY_ID, () => 0.999, NOW + 60_000)
    if (!retry) throw new Error('expected a retry cow action')
    expect(retry.action['Action ID']).toBe(TUTORIAL_COW_ACTION_ID)
    expect(enemyForAction(db, retry.action)?.['Enemy ID']).toBe(TUTORIAL_COW_ENEMY_ID)
    expect(retry.action['Action ID']).not.toBe(bullActionId)
    expect(enemyForAction(db, retry.action)?.['Enemy ID']).not.toBe(bullEnemyId)
  })

  it('food top-up is only on the Cow step after a zero-food death', () => {
    const gatheringDeath = applyCombatDefeat(db, withoutFood(activeTutorial()), NOW)
    expect(gatheringDeath.dialogueFlags).not.toContain(TUTORIAL_FOOD_GRANT_FLAG)
    expect(stackQty(gatheringDeath, TUTORIAL_BAKED_POTATO_ITEM_ID)).toBe(0)

    const cooking = withLatchedSteps(withoutFood(activeTutorial()), [
      TUTORIAL_GATHER_STEP_ID,
      TUTORIAL_SHOW_POTATOES_STEP_ID,
    ])
    const cookingDeath = applyCombatDefeat(db, cooking, NOW)
    expect(cookingDeath.dialogueFlags).not.toContain(TUTORIAL_FOOD_GRANT_FLAG)
    expect(stackQty(cookingDeath, TUTORIAL_BAKED_POTATO_ITEM_ID)).toBe(0)

    const empty = applyCombatDefeat(db, combatStepSave(), NOW)
    expect(empty.dialogueFlags).toContain(TUTORIAL_FOOD_GRANT_FLAG)
    expect(stackQty(empty, TUTORIAL_BAKED_POTATO_ITEM_ID)).toBe(TUTORIAL_FOOD_TOP_UP_QTY)

    const finished = applyTutorialCowKill(db, combatStepSave(), TUTORIAL_COW_ENEMY_ID)
    expect(finished.completed).toBe(true)
    const afterWin = applyCombatDefeat(db, withoutFood(finished.save), NOW)
    expect(afterWin.dialogueFlags).not.toContain(TUTORIAL_FOOD_GRANT_FLAG)
    expect(stackQty(afterWin, TUTORIAL_BAKED_POTATO_ITEM_ID)).toBe(0)
  })

  it('reloading or retrying a refused food grant does not grant twice', () => {
    const granted = applyCombatDefeat(db, combatStepSave(), NOW)
    expect(stackQty(granted, TUTORIAL_BAKED_POTATO_ITEM_ID)).toBe(TUTORIAL_FOOD_TOP_UP_QTY)
    const retried = applyCombatDefeat(db, reload(granted), NOW)
    expect(retried.tutorialFoodGrantDeathAt).toBe(granted.tutorialFoodGrantDeathAt)
    expect(stackQty(retried, TUTORIAL_BAKED_POTATO_ITEM_ID)).toBe(TUTORIAL_FOOD_TOP_UP_QTY)

    const snapshot = applyCombatDefeat(db, combatStepSave(), NOW)
    const refusedReplay = applyCombatDefeat(db, snapshot, NOW + 1000)
    expect(stackQty(refusedReplay, TUTORIAL_BAKED_POTATO_ITEM_ID)).toBe(TUTORIAL_FOOD_TOP_UP_QTY)
  })

  it('food top-up during offline catch-up is once per death', () => {
    const dying = fightingCow(combatStepSave(), 100, 1)
    const resolved = resolveUnattendedProgress(db, dying, NOW + 8000, () => 0.99)
    expect(resolved.combatDeaths).toBeGreaterThan(0)
    expect(resolved.save.dialogueFlags).toContain(TUTORIAL_FOOD_GRANT_FLAG)
    expect(stackQty(resolved.save, TUTORIAL_BAKED_POTATO_ITEM_ID)).toBe(TUTORIAL_FOOD_TOP_UP_QTY)
    const again = applyCombatDefeat(db, resolved.save, NOW + 8000)
    expect(stackQty(again, TUTORIAL_BAKED_POTATO_ITEM_ID)).toBe(TUTORIAL_FOOD_TOP_UP_QTY)
  })

  it('server-authoritative catch-up grants food once and a refused retry does not double', () => {
    const dying = fightingCow(combatStepSave(), 100, 1)
    const first = applyGameCommand(rawDatabase, {
      command: 'set_meta',
      args: { hasSeenFennelIntro: true },
      save: dying,
      nowMs: NOW + 8000,
      random: () => 0.99,
    })
    expect(first.ok).toBe(true)
    if (!first.ok) return
    expect(first.save.dialogueFlags).toContain(TUTORIAL_FOOD_GRANT_FLAG)
    expect(stackQty(first.save, TUTORIAL_BAKED_POTATO_ITEM_ID)).toBe(TUTORIAL_FOOD_TOP_UP_QTY)

    const refusedTravel = applyGameCommand(rawDatabase, {
      command: 'travel',
      args: { destinationId: COPPER_MINE, browseMapId: MAIN_MAP },
      save: first.save,
      nowMs: NOW + 9000,
      random: () => 0,
    })
    expect(refusedTravel.ok).toBe(false)
    const retried = applyGameCommand(rawDatabase, {
      command: 'set_meta',
      args: { hasSeenFennelIntro: true },
      save: first.save,
      nowMs: NOW + 9000,
      random: () => 0.99,
    })
    expect(retried.ok).toBe(true)
    if (!retried.ok) return
    expect(stackQty(retried.save, TUTORIAL_BAKED_POTATO_ITEM_ID)).toBe(TUTORIAL_FOOD_TOP_UP_QTY)
  })

  it('one Cow kill through catch-up or reload mid-fight completes once', () => {
    const action = db.Actions.find((row) => row['Action ID'] === TUTORIAL_COW_ACTION_ID)!
    const enemy = db.Enemies.find((row) => row['Enemy ID'] === TUTORIAL_COW_ENEMY_ID)!
    const fighting = fightingCow(combatStepSave(), 1, 1000)
    const victory = applyCombatVictory(db, reload(fighting), action, enemy, () => 0, NOW)
    expect(getQuestProgress(victory.save, TUTORIAL_QUEST_ID).status).toBe('completed')
    expect(victory.save.currentActivityId).toBeNull()
    expect(victory.save.unlockedBookIds).toContain('BOOK-0001')
    expect(isTutorialLocked(victory.save)).toBe(false)

    const away = resolveUnattendedProgress(db, fightingCow(combatStepSave(), 1, 1000), NOW + 8000, () => 0)
    expect(away.combatVictories).toBeGreaterThan(0)
    expect(getQuestProgress(away.save, TUTORIAL_QUEST_ID).status).toBe('completed')
    expect(away.save.currentActivityId).toBeNull()
    expect(away.save.unlockedBookIds.filter((id) => id === 'BOOK-0001')).toHaveLength(1)
    const twice = applyTutorialCowKill(db, away.save, TUTORIAL_COW_ENEMY_ID)
    expect(twice.completed).toBe(false)
    expect(away.save.unlockedBookIds.filter((id) => id === 'BOOK-0001')).toHaveLength(1)
  })

  it('losing to the Cow leaves the step open and retryable', () => {
    const lost = applyCombatDefeat(db, combatStepSave(), NOW)
    expect(getQuestProgress(lost, TUTORIAL_QUEST_ID).status).toBe('active')
    expect(getCurrentStepId(db, lost, getQuest(db, TUTORIAL_QUEST_ID)!)).toBe(TUTORIAL_COMBAT_STEP_ID)
    expect(isTutorialLocked(lost)).toBe(true)
    expect(isTutorialLocationAllowed(lost, COPPER_MINE)).toBe(false)
    const recovered = applyDeathRecovery(db, lost)
    expect(requestActivityStart(db, recovered, TUTORIAL_PASTURE_ACTIVITY_ID, NOW, () => 0.999).ok).toBe(
      true,
    )
    const retry = generateNextAction(db, recovered, TUTORIAL_PASTURE_ACTIVITY_ID, () => 0.999, NOW)
    expect(retry?.action['Action ID']).toBe(TUTORIAL_COW_ACTION_ID)
  })

  it('v66 to v67 keeps partway progress and items, and locks the player back', () => {
    let mid = withItem(activeTutorial(TOWN), TUTORIAL_POTATO_ITEM_ID, 3)
    mid = withLatchedSteps(mid, [TUTORIAL_GATHER_STEP_ID, TUTORIAL_SHOW_POTATOES_STEP_ID])
    mid = {
      ...mid,
      currentLocationId: TUTORIAL_KITCHEN_LOCATION_ID,
      currentActivityId: TUTORIAL_COOK_ACTIVITY_ID,
      gold: 77,
      claimedMerchantTipIds: ['NPC-0008'],
      tutorialGuaranteedGathers: 4,
      tutorialGuaranteedCooks: 2,
    }
    const migrated = migrateSave({ ...mid, saveVersion: 66 }, NOW)
    expect(migrated.saveVersion).toBe(67)
    expect(migrated.dialogueFlags).toContain(TUTORIAL_LOCKBACK_FLAG)
    expect(isStepLatched(migrated, TUTORIAL_QUEST_ID, TUTORIAL_GATHER_STEP_ID)).toBe(true)
    expect(isStepLatched(migrated, TUTORIAL_QUEST_ID, TUTORIAL_SHOW_POTATOES_STEP_ID)).toBe(true)
    expect(getCurrentStepId(db, migrated, getQuest(db, TUTORIAL_QUEST_ID)!)).toBe(TUTORIAL_COOK_STEP_ID)
    expect(stackQty(migrated, TUTORIAL_POTATO_ITEM_ID)).toBe(3)
    expect(migrated.gold).toBe(77)
    expect(migrated.claimedMerchantTipIds).toEqual(['NPC-0008'])
    expect(migrated.currentLocationId).toBe(TUTORIAL_KITCHEN_LOCATION_ID)
  })

  it('v66 to v67 stops idle actions and travel in now-hidden places', () => {
    const hidden = {
      ...activeTutorial(COPPER_MINE),
      currentActivityId: 'ACT-0002',
      unlockedLocationIds: [COPPER_MINE, TOWN],
    }
    const migrated = migrateSave({ ...hidden, saveVersion: 66 }, NOW)
    expect(migrated.currentLocationId).toBe(FARM)
    expect(migrated.currentActivityId).toBeNull()
    expect(canTravelTo(db, FARM, COPPER_MINE, MAIN_MAP, migrated)).toBe(false)
    expect(validateActivityStart(db, migrated, 'ACT-0002').ok).toBe(false)
  })

  it('v66 to v67 lock-back leaves an existing open Bazaar order untouched', () => {
    // bazaar_orders live in the edge table, not on PlayerSave. Lock-back and the
    // v67 migration never receive a row; this keeps a server-side order next to
    // the save and checks both stay intact.
    const openOrder = {
      id: 'ord-tutorial-lockback',
      user_id: 'user-lockback',
      username: 'LockedBack',
      side: 'sell',
      item_id: TUTORIAL_POTATO_ITEM_ID,
      unit_price: 10,
      quantity: 3,
      filled: 0,
      gold_escrow: 0,
      slot: 1,
      status: 'open',
      created_at: '2026-10-01T00:00:00.000Z',
      updated_at: '2026-10-01T00:00:00.000Z',
    }
    const orderSnapshot = structuredClone(openOrder)

    let save = withItem(activeTutorial(TOWN), TUTORIAL_POTATO_ITEM_ID, 4)
    save = {
      ...save,
      currentActivityId: 'ACT-0008',
      gold: 77,
      claimedMerchantTipIds: ['NPC-0008'],
    }
    const goldBefore = save.gold
    const potatoesBefore = stackQty(save, TUTORIAL_POTATO_ITEM_ID)

    const locked = applyTutorialLockback(save)
    expect(locked.gold).toBe(goldBefore)
    expect(stackQty(locked, TUTORIAL_POTATO_ITEM_ID)).toBe(potatoesBefore)
    expect(locked.claimedMerchantTipIds).toEqual(['NPC-0008'])
    expect(bazaarTutorialLocked(locked as unknown as Record<string, unknown>)).toBe(true)
    expect(openOrder).toEqual(orderSnapshot)
    expect(JSON.parse(JSON.stringify(locked))).not.toHaveProperty('bazaarOrders')
    expect(JSON.parse(JSON.stringify(locked))).not.toHaveProperty('bazaar_orders')

    const migrated = migrateSave({ ...save, saveVersion: 66 }, NOW)
    expect(migrated.saveVersion).toBe(67)
    expect(migrated.dialogueFlags).toContain(TUTORIAL_LOCKBACK_FLAG)
    expect(migrated.gold).toBe(goldBefore)
    expect(stackQty(migrated, TUTORIAL_POTATO_ITEM_ID)).toBe(potatoesBefore)
    expect(migrated.claimedMerchantTipIds).toEqual(['NPC-0008'])
    expect(bazaarTutorialLocked(migrated as unknown as Record<string, unknown>)).toBe(true)
    expect(openOrder).toEqual(orderSnapshot)
    expect(JSON.parse(JSON.stringify(migrated))).not.toHaveProperty('bazaarOrders')
    expect(JSON.parse(JSON.stringify(migrated))).not.toHaveProperty('bazaar_orders')
  })

  it('v66 to v67 leaves finished players and bazaar-adjacent state unchanged', () => {
    const finished = {
      ...withItem(activeTutorial(TOWN), TUTORIAL_POTATO_ITEM_ID, 4),
      quests: [{ questId: TUTORIAL_QUEST_ID, status: 'completed' as const, progress: 1 }],
      currentActivityId: 'ACT-0008',
      gold: 120,
      claimedMerchantTipIds: ['NPC-0008'],
    }
    const locked = applyTutorialLockback(finished)
    expect(locked.currentLocationId).toBe(TOWN)
    expect(locked.currentActivityId).toBe('ACT-0008')
    expect(locked.gold).toBe(120)
    expect(locked.claimedMerchantTipIds).toEqual(['NPC-0008'])
    expect(stackQty(locked, TUTORIAL_POTATO_ITEM_ID)).toBe(4)
    expect(locked.dialogueFlags).not.toContain(TUTORIAL_LOCKBACK_FLAG)

    const migrated = migrateSave({ ...finished, saveVersion: 66 }, NOW)
    expect(migrated.saveVersion).toBe(67)
    expect(migrated.currentLocationId).toBe(TOWN)
    expect(migrated.currentActivityId).toBe('ACT-0008')
    expect(migrated.gold).toBe(120)
    expect(migrated.claimedMerchantTipIds).toEqual(['NPC-0008'])
    expect(stackQty(migrated, TUTORIAL_POTATO_ITEM_ID)).toBe(4)
    expect(getQuestProgress(migrated, TUTORIAL_QUEST_ID).status).toBe('completed')
    expect(migrated.dialogueFlags).not.toContain(TUTORIAL_LOCKBACK_FLAG)
  })

  it('new accounts start Getting Started at step 1', () => {
    const save = activeTutorial()
    expect(tutorialCurrentStepId(db, save)).toBe(TUTORIAL_GATHER_STEP_ID)
    expect(getCurrentStepId(db, save, getQuest(db, TUTORIAL_QUEST_ID)!)).toBe(TUTORIAL_GATHER_STEP_ID)
    expect(tutorialGuaranteedGathersUsed(save)).toBe(0)
    expect(tutorialGuaranteedCooksUsed(save)).toBe(0)
    expect(isStepLatched(save, TUTORIAL_QUEST_ID, TUTORIAL_GATHER_STEP_ID)).toBe(false)
  })

  it('unlock flags cannot skip locked places before their step', () => {
    const gather = {
      ...activeTutorial(),
      unlockedLocationIds: [TOWN, COPPER_MINE, TUTORIAL_KITCHEN_LOCATION_ID],
    }
    expect(isTutorialLocationAllowed(gather, TUTORIAL_KITCHEN_LOCATION_ID)).toBe(false)
    expect(isTutorialLocationAllowed(gather, TOWN)).toBe(false)
    expect(isTutorialLocationAllowed(gather, COPPER_MINE)).toBe(false)
    expect(isTutorialActivityAllowed(gather, TUTORIAL_COOK_ACTIVITY_ID)).toBe(false)
    expect(isTutorialActivityAllowed(gather, TUTORIAL_PASTURE_ACTIVITY_ID)).toBe(false)
    expect(canTravelTo(db, FARM, TOWN, MAIN_MAP, gather)).toBe(false)
    expect(canTravelTo(db, FARM, COPPER_MINE, MAIN_MAP, gather)).toBe(false)
    expect(isTutorialBazaarAllowed(gather)).toBe(false)
    expect(isTutorialGuildHallAllowed(gather)).toBe(false)

    const cooking = withLatchedSteps(gather, [TUTORIAL_GATHER_STEP_ID, TUTORIAL_SHOW_POTATOES_STEP_ID])
    expect(isTutorialLocationAllowed(cooking, TUTORIAL_KITCHEN_LOCATION_ID)).toBe(true)
    expect(isTutorialActivityAllowed(cooking, TUTORIAL_COOK_ACTIVITY_ID)).toBe(true)
    expect(isTutorialActivityAllowed(cooking, TUTORIAL_PASTURE_ACTIVITY_ID)).toBe(false)
    expect(canTravelTo(db, FARM, COPPER_MINE, MAIN_MAP, cooking)).toBe(false)

    const combat = withLatchedSteps(gather, [
      TUTORIAL_GATHER_STEP_ID,
      TUTORIAL_SHOW_POTATOES_STEP_ID,
      TUTORIAL_COOK_STEP_ID,
      TUTORIAL_SHOW_COOKED_STEP_ID,
    ])
    expect(isTutorialLocationAllowed(combat, TUTORIAL_KITCHEN_LOCATION_ID)).toBe(false)
    expect(isTutorialActivityAllowed(combat, TUTORIAL_COOK_ACTIVITY_ID)).toBe(false)
    expect(isTutorialActivityAllowed(combat, TUTORIAL_PASTURE_ACTIVITY_ID)).toBe(true)
    expect(canTravelTo(db, FARM, COPPER_MINE, MAIN_MAP, combat)).toBe(false)
    expect(
      validateActivityStart(db, { ...combat, currentLocationId: TUTORIAL_KITCHEN_LOCATION_ID }, TUTORIAL_COOK_ACTIVITY_ID)
        .ok,
    ).toBe(false)
  })

  it('equip step accepts Goblin starting wooden dagger alone', () => {
    let save = combatStepSave('RACE-0005')
    expect(stackQty(save, TUTORIAL_STARTER_DAGGER_ID)).toBe(1)
    expect(stackQty(save, TUTORIAL_STARTER_SHIELD_ID)).toBe(0)
    expect(stackQty(save, TUTORIAL_STARTER_SWORD_ID)).toBe(1)

    const dagger = equipItemFromInventory(db, save, TUTORIAL_STARTER_DAGGER_ID)
    expect(dagger.ok).toBe(true)
    if (!dagger.ok) throw new Error(dagger.reason)
    save = dagger.save
    expect(save.equipment.slots[TUTORIAL_OFFHAND_SLOT_ID]?.itemId).toBe(TUTORIAL_STARTER_DAGGER_ID)
    expect(isTutorialShieldEquipped(save)).toBe(true)
    expect(tutorialHudHint(db, save)?.label).not.toBe('Equip your shield')

    const sword = equipItemFromInventory(db, save, TUTORIAL_STARTER_SWORD_ID)
    expect(sword.ok).toBe(true)
    if (!sword.ok) throw new Error(sword.reason)
    save = sword.save
    expect(isTutorialSwordEquipped(save)).toBe(true)
    expect(save.equipment.slots[TUTORIAL_OFFHAND_SLOT_ID]?.itemId).toBe(TUTORIAL_STARTER_DAGGER_ID)
    expect(stackQty(save, TUTORIAL_STARTER_SHIELD_ID)).toBe(0)
    expect(tutorialHudHint(db, save)?.label).toBe('Fight a cow in the pasture')
    expect(tutorialHudHint(db, save)?.spotlight).toBe('pasture')
  })

  it('equip step still requires sword and shield for other races', () => {
    for (const raceId of ['RACE-0001', 'RACE-0004', 'RACE-0006']) {
      let save = combatStepSave(raceId)
      expect(stackQty(save, TUTORIAL_STARTER_SWORD_ID), raceId).toBe(1)
      expect(stackQty(save, TUTORIAL_STARTER_SHIELD_ID), raceId).toBe(1)
      expect(stackQty(save, TUTORIAL_STARTER_DAGGER_ID), raceId).toBe(0)

      const sword = equipItemFromInventory(db, save, TUTORIAL_STARTER_SWORD_ID)
      expect(sword.ok, raceId).toBe(true)
      if (!sword.ok) throw new Error(`${raceId} ${sword.reason}`)
      save = sword.save
      expect(isTutorialSwordEquipped(save), raceId).toBe(true)
      expect(tutorialHudHint(db, save)?.label, raceId).toBe('Equip your shield')
      expect(tutorialHudHint(db, save)?.spotlight, raceId).not.toBe('pasture')

      const shield = equipItemFromInventory(db, save, TUTORIAL_STARTER_SHIELD_ID)
      expect(shield.ok, raceId).toBe(true)
      if (!shield.ok) throw new Error(`${raceId} ${shield.reason}`)
      save = shield.save
      expect(isTutorialShieldEquipped(save), raceId).toBe(true)
      expect(tutorialHudHint(db, save)?.label, raceId).toBe('Fight a cow in the pasture')
      expect(tutorialHudHint(db, save)?.spotlight, raceId).toBe('pasture')
    }
  })

  it('locked-back non-goblin who owns a wooden dagger still completes equip with sword and shield', () => {
    let save = applyTutorialLockback(withItem(combatStepSave(), TUTORIAL_STARTER_DAGGER_ID, 1))
    expect(save.dialogueFlags).toContain(TUTORIAL_LOCKBACK_FLAG)
    expect(save.raceId).toBe('RACE-0001')
    expect(stackQty(save, TUTORIAL_STARTER_DAGGER_ID)).toBe(1)
    expect(stackQty(save, TUTORIAL_STARTER_SHIELD_ID)).toBe(1)

    const sword = equipItemFromInventory(db, save, TUTORIAL_STARTER_SWORD_ID)
    expect(sword.ok).toBe(true)
    if (!sword.ok) throw new Error(sword.reason)
    save = sword.save
    expect(tutorialHudHint(db, save)?.label).toBe('Equip your shield')

    const shield = equipItemFromInventory(db, save, TUTORIAL_STARTER_SHIELD_ID)
    expect(shield.ok).toBe(true)
    if (!shield.ok) throw new Error(shield.reason)
    save = shield.save
    expect(save.equipment.slots[TUTORIAL_OFFHAND_SLOT_ID]?.itemId).toBe(TUTORIAL_STARTER_SHIELD_ID)
    expect(isTutorialSwordEquipped(save)).toBe(true)
    expect(isTutorialShieldEquipped(save)).toBe(true)
    expect(tutorialHudHint(db, save)?.label).toBe('Fight a cow in the pasture')
  })

  it('Fennel picks the dagger line when ITEM-0125 is in the bag, else sword and shield', () => {
    const sword = "That cow's been trouble all week. Put on your sword and shield before you go near her."
    const dagger = "That cow's been trouble all week. Grab your dagger before you go near her."

    const humanCombat = combatStepSave()
    expect(dialoguesForNpc(db, humanCombat, TUTORIAL_NPC_ID)).toContain('DLG-0016')
    expect(startDialogue(db, humanCombat, 'DLG-0016').view?.nodeId).toBe('DNODE-0027')
    expect(startDialogue(db, humanCombat, 'DLG-0016').view?.line).toBe(sword)
    expect(startDialogue(db, humanCombat, 'DLG-0020').ok).toBe(false)

    const goblinCombat = combatStepSave('RACE-0005')
    expect(stackQty(goblinCombat, TUTORIAL_STARTER_DAGGER_ID)).toBe(1)
    expect(dialoguesForNpc(db, goblinCombat, TUTORIAL_NPC_ID)).toContain('DLG-0020')
    expect(startDialogue(db, goblinCombat, 'DLG-0020').view?.nodeId).toBe('DNODE-0032')
    expect(startDialogue(db, goblinCombat, 'DLG-0020').view?.line).toBe(dagger)
    expect(startDialogue(db, goblinCombat, 'DLG-0016').ok).toBe(false)

    let cooked = withLatchedSteps(activeTutorial(), [
      TUTORIAL_GATHER_STEP_ID,
      TUTORIAL_SHOW_POTATOES_STEP_ID,
      TUTORIAL_COOK_STEP_ID,
    ])
    cooked = withItem(cooked, TUTORIAL_BAKED_POTATO_ITEM_ID, 5)
    const shown = chooseDialogue(db, cooked, 'DLG-0005', 'DNODE-0007', 'DCH-0009')
    expect(shown.ok).toBe(true)
    if (!shown.ok) throw new Error(shown.reason)
    expect(shown.view?.nodeId).toBe('DNODE-0008')
    expect(shown.view?.line).toBe(sword)

    const shownDagger = chooseDialogue(
      db,
      withItem(cooked, TUTORIAL_STARTER_DAGGER_ID, 1),
      'DLG-0005',
      'DNODE-0007',
      'DCH-0041',
    )
    expect(shownDagger.ok).toBe(true)
    if (!shownDagger.ok) throw new Error(shownDagger.reason)
    expect(shownDagger.view?.nodeId).toBe('DNODE-0031')
    expect(shownDagger.view?.line).toBe(dagger)
  })

  it('cow win line DNODE-0026 leads to farewell', () => {
    const killed = applyTutorialCowKill(db, combatStepSave(), TUTORIAL_COW_ENEMY_ID)
    expect(killed.completed).toBe(true)
    expect(killed.save.dialogueFlags).toContain(TUTORIAL_FAREWELL_FLAG)
    expect(tutorialAutoDialogueId(killed.save)).toBe('DLG-0006')

    const opened = startDialogue(db, killed.save, 'DLG-0006')
    expect(opened.ok).toBe(true)
    if (!opened.ok) throw new Error(opened.reason)
    expect(opened.view?.nodeId).toBe('DNODE-0026')
    expect(opened.view?.line).toBe('Well, that settles that.')

    const continued = chooseDialogue(db, opened.save, 'DLG-0006', 'DNODE-0026', 'DCH-0036')
    expect(continued.ok).toBe(true)
    if (!continued.ok) throw new Error(continued.reason)
    expect(continued.view?.nodeId).toBe('DNODE-0009')

    const thanks = chooseDialogue(db, continued.save, 'DLG-0006', 'DNODE-0009', 'DCH-0012')
    expect(thanks.ok).toBe(true)
    if (!thanks.ok) throw new Error(thanks.reason)
    expect(thanks.view?.nodeId).toBe('DNODE-0010')

    const farewell = chooseDialogue(db, thanks.save, 'DLG-0006', 'DNODE-0010', 'DCH-0013')
    expect(farewell.ok).toBe(true)
    if (!farewell.ok) throw new Error(farewell.reason)
    expect(farewell.completed).toBe(true)
    expect(farewell.save.dialogueFlags).not.toContain(TUTORIAL_FAREWELL_FLAG)
    expect(tutorialAutoDialogueId(farewell.save)).toBeNull()
  })

  it('step progress survives reload and a refused travel save', () => {
    const save = combatStepSave()
    const refused = applyTravelArrival(db, save, COPPER_MINE, NOW)
    expect(refused.currentLocationId).toBe(FARM)
    expect(isStepLatched(refused, TUTORIAL_QUEST_ID, TUTORIAL_SHOW_COOKED_STEP_ID)).toBe(true)
    expect(getCurrentStepId(db, refused, getQuest(db, TUTORIAL_QUEST_ID)!)).toBe(TUTORIAL_COMBAT_STEP_ID)
    const reloaded = reload(refused)
    expect(isStepLatched(reloaded, TUTORIAL_QUEST_ID, TUTORIAL_SHOW_COOKED_STEP_ID)).toBe(true)
    expect(getCurrentStepId(db, reloaded, getQuest(db, TUTORIAL_QUEST_ID)!)).toBe(TUTORIAL_COMBAT_STEP_ID)
    expect(tutorialGuaranteedGathersUsed(reloaded)).toBe(tutorialGuaranteedGathersUsed(save))

    const serverRefused = applyGameCommand(rawDatabase, {
      command: 'travel',
      args: { destinationId: COPPER_MINE, browseMapId: MAIN_MAP },
      save,
      nowMs: NOW,
      random: () => 0,
    })
    expect(serverRefused.ok).toBe(false)
    expect(isStepLatched(save, TUTORIAL_QUEST_ID, TUTORIAL_SHOW_COOKED_STEP_ID)).toBe(true)
    expect(getCurrentStepId(db, save, getQuest(db, TUTORIAL_QUEST_ID)!)).toBe(TUTORIAL_COMBAT_STEP_ID)
  })
})
