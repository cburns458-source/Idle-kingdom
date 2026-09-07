import {
  applyCombatDefeat,
  beginCombatSave,
  clearCombatSave,
  enemyForAction,
  isDeathPaused,
} from '../combat/engine'
import { consumeFoodAfterVictory } from '../combat/food'
import { clearProductionSave } from '../production/engine'
import { isStandardProductionActivity, recipesForActivity } from '../production/recipes'
import type { ActionRow, ActivityRow, GameDatabase } from '../data/types'
import type { EquippedStack, PlayerSave } from '../save/types'
import { clearActivePotionEffect, tryConsumePotionForScope } from '../potions/effects'
import { gatheringDurationMs, gatheringXpReward } from './gathering'
import { heldActionIdFor, withHeldAction, withoutHeldAction } from './heldAction'
import { eligiblePoolEntries, isSelectableAction, pickWeightedAction, type RandomFn } from './pools'
import {
  requirementsForEntity,
  unmetHardRequirements,
} from './requirements'
import { resolveActionRewards } from './rewards'
import type {
  ActionCompletionResult,
  ActionXpRewardSummary,
  ActiveActionState,
  ActivityStartResult,
} from './types'
import { addLifetimeStat, recordGatheredDrops } from '../achievements/progress'
import { applyQuestActionProgress } from '../quests/progress'
import { applyQuestAutoCompleteOnAction } from '../quests/quests'
import { WEAPON_TOOL_SLOT_ID } from '../save/types'
import { slotStack } from '../equipment/loadout'
import { GATHERING_ACTIONS_STAT } from '../log/milestones'
import { bonusSkillXpForAction, bowHuntingCombatXpBonus } from './bonusXp'
import { summarizeXpReward } from './rewardSummary'
import { applyXp } from './xp'
import { bossRespawnUntilMs, isBossEnemy, isBossRespawnReady } from '../combat/boss'

const LOCKPICK_ITEM_ID = 'ITEM-0351'

export const COMING_SOON_REASON = 'Coming soon.'

export function getActivity(db: GameDatabase, activityId: string): ActivityRow | undefined {
  return db.Activities.find((row) => row['Activity ID'] === activityId)
}

export function activityIsComingSoon(activity: ActivityRow | null | undefined): boolean {
  if (!activity) return false
  return String(activity.Notes ?? '')
    .split(';')
    .map((token) => token.trim().toLowerCase())
    .includes('coming_soon')
}

/** Earliest time the next pool action can start, or null when nothing is waiting. */
export function bossRespawnWaitUntilMs(
  db: GameDatabase,
  save: PlayerSave,
  activityId: string,
): number | null {
  const activity = getActivity(db, activityId)
  if (!activity?.['Pool ID']) return null

  const heldId = heldActionIdFor(save, activityId)
  let held = heldId ? db.Actions.find((row) => row['Action ID'] === heldId) : undefined
  if (held && !isSelectableAction(held)) held = undefined
  const candidates: ActionRow[] = held
    ? [held]
    : eligiblePoolEntries(db, activity['Pool ID']).map((entry) => entry.action)
  if (candidates.length === 0) return null

  let wait: number | null = null
  for (const action of candidates) {
    if (action.Category !== 'Combat') return null
    const enemy = enemyForAction(db, action)
    if (!enemy || !isBossEnemy(enemy)) return null
    const until = bossRespawnUntilMs(save, enemy['Enemy ID'])
    if (until == null) return null
    wait = wait == null ? until : Math.min(wait, until)
  }
  return wait
}

export function validateActivityStart(
  db: GameDatabase,
  save: PlayerSave,
  activityId: string,
): ActivityStartResult {
  const activity = getActivity(db, activityId)
  if (!activity) return { ok: false, reason: 'Unknown activity.' }
  if (activity['Location ID'] !== save.currentLocationId) {
    return { ok: false, reason: 'Travel to this location before starting the activity.' }
  }
  if (activityIsComingSoon(activity)) {
    return { ok: false, reason: COMING_SOON_REASON }
  }
  const activityReqFailures = unmetHardRequirements(
    db,
    save,
    requirementsForEntity(db, 'Activity', activityId),
  )
  if (activityReqFailures.length > 0) {
    return { ok: false, reason: activityReqFailures[0]! }
  }

  if (isStandardProductionActivity(db, activity)) {
    if (recipesForActivity(db, save, activityId).length === 0) {
      return { ok: false, reason: 'No known recipes are available at this station yet.' }
    }
    return { ok: true }
  }

  if (!activity['Pool ID']) {
    return { ok: false, reason: 'This activity is not available yet.' }
  }

  const eligible = eligiblePoolEntries(db, activity['Pool ID'])
  if (eligible.length === 0) {
    return {
      ok: false,
      reason: 'No actions are ready for this activity yet.',
    }
  }

  for (const { action } of eligible) {
    const failures = unmetHardRequirements(
      db,
      save,
      requirementsForEntity(db, 'Action', action['Action ID']),
    )
    if (failures.length > 0) {
      return { ok: false, reason: failures[0]! }
    }
  }

  return { ok: true }
}

export function beginActivitySave(
  save: PlayerSave,
  activityId: string,
  nowIso: string = new Date().toISOString(),
): PlayerSave {
  if (isDeathPaused(save, Date.parse(nowIso))) return save
  return clearProductionSave(
    clearCombatSave({
      ...save,
      currentActivityId: activityId,
      activityStartedAt: nowIso,
      currentActionId: null,
      actionStartedAt: null,
      actionDurationMs: null,
      deathPauseUntil: null,
      activityTransition: null,
    }),
  )
}

export function clearActivitySave(
  save: PlayerSave,
  nowMs: number = Date.now(),
): PlayerSave {
  if (isDeathPaused(save, nowMs)) return save
  return clearProductionSave(
    clearCombatSave({
      ...save,
      currentActivityId: null,
      activityStartedAt: null,
      currentActionId: null,
      actionStartedAt: null,
      actionDurationMs: null,
      deathPauseUntil: null,
      activityTransition: null,
    }),
  )
}

export function generateNextAction(
  db: GameDatabase,
  save: PlayerSave,
  activityId: string,
  random: RandomFn = Math.random,
  nowMs: number = Date.now(),
): { save: PlayerSave; action: ActionRow; state: ActiveActionState | null } | null {
  const activity = getActivity(db, activityId)
  if (!activity?.['Pool ID']) return null

  const heldId = heldActionIdFor(save, activityId)
  const eligible = eligiblePoolEntries(db, activity['Pool ID'])
  let action = heldId ? db.Actions.find((row) => row['Action ID'] === heldId) : undefined
  if (action && !isSelectableAction(action)) action = undefined
  if (action && !eligible.some((pair) => pair.action['Action ID'] === heldId)) action = undefined
  action ??= pickWeightedAction(eligible, random) ?? undefined
  if (!action) return null
  const actionId = action['Action ID']

  const startedAt = new Date(nowMs).toISOString()

  if (action.Category === 'Combat') {
    const enemy = enemyForAction(db, action)
    if (!enemy) return null
    const withActivity = {
      ...save,
      currentActivityId: activityId,
      activityStartedAt: save.activityStartedAt ?? startedAt,
      currentActionId: null,
      actionStartedAt: null,
      actionDurationMs: null,
    }
    if (isBossEnemy(enemy) && !isBossRespawnReady(save, enemy['Enemy ID'], nowMs)) {
      return {
        action,
        state: null,
        save: clearCombatSave(withActivity),
      }
    }
    return {
      action,
      state: null,
      save: withHeldAction(beginCombatSave(db, withActivity, action, enemy, startedAt), activityId, actionId),
    }
  }

  const durationMs = gatheringDurationMs(db, save, action)
  let next = clearCombatSave({
    ...save,
    currentActivityId: activityId,
    currentActionId: actionId,
    actionStartedAt: startedAt,
    actionDurationMs: durationMs,
  })
  const potion = tryConsumePotionForScope(db, next, 'one_action')
  next = potion.save
  return {
    action,
    state: {
      actionId,
      startedAtMs: nowMs,
      durationMs,
    },
    save: withHeldAction(next, activityId, actionId),
  }
}

function consumeLockpick(save: PlayerSave): PlayerSave {
  const tool = slotStack(save, WEAPON_TOOL_SLOT_ID)
  if (!tool || tool.itemId !== LOCKPICK_ITEM_ID || tool.quantity <= 0) return save
  const nextQty = tool.quantity - 1
  const nextTool: EquippedStack | null =
    nextQty > 0 ? { ...tool, quantity: nextQty } : null
  return {
    ...save,
    equipment: {
      ...save.equipment,
      slots: {
        ...save.equipment.slots,
        [WEAPON_TOOL_SLOT_ID]: nextTool,
      },
    },
  }
}

export function completeGatheringAction(
  db: GameDatabase,
  save: PlayerSave,
  action: ActionRow,
  random: RandomFn = Math.random,
  nowMs: number = Date.now(),
): { save: PlayerSave; result: ActionCompletionResult } {
  const notes = action.Notes ?? ''
  const emptyResult = (): ActionCompletionResult => ({
    actionId: action['Action ID'],
    actionName: action['Display Name'],
    skillId: action['Relevant Skill ID'],
    xpGained: 0,
    bonusXp: [],
    xpRewards: [],
    goldGained: 0,
    loot: [],
    leveledUpTo: null,
  })

  if (/RequiresLockpick/i.test(notes)) {
    const tool = slotStack(save, WEAPON_TOOL_SLOT_ID)
    if (!tool || tool.quantity <= 0 || tool.itemId !== LOCKPICK_ITEM_ID) {
      return {
        save: withoutHeldAction(save, save.currentActivityId),
        result: emptyResult(),
      }
    }
  }

  const failChanceMatch = /FailChance:(\d+)/i.exec(notes)
  if (
    /Thievery/i.test(notes) &&
    failChanceMatch &&
    !/NoConsequences/i.test(notes)
  ) {
    const failChance = Number(failChanceMatch[1])
    if (random() * 100 < failChance) {
      const damagePercent = Number(/FailDamagePercent:(\d+)/i.exec(notes)?.[1] ?? 10)
      const damage = Math.max(1, Math.floor((save.maxHp * damagePercent) / 100))
      const nextHp = save.currentHp - damage
      let next: PlayerSave = { ...save, currentHp: nextHp }
      if (/RequiresLockpick/i.test(notes)) {
        next = consumeLockpick(next)
      }
      if (nextHp <= 0) {
        next = applyCombatDefeat(db, next, nowMs)
      } else {
        next = consumeFoodAfterVictory(db, next).save
      }
      return {
        save: withoutHeldAction(next, save.currentActivityId),
        result: emptyResult(),
      }
    }
  }

  let working = save
  if (/RequiresLockpick/i.test(notes)) {
    working = consumeLockpick(working)
  }

  const skillId = action['Relevant Skill ID']
  const rewarded = resolveActionRewards(db, working, action, random)
  const xpAmount = gatheringXpReward(db, working, action)
  let next = clearActivePotionEffect(rewarded.save)
  const xpApplied = applyXp(next, db, skillId, xpAmount)
  next = xpApplied.save
  let leveledUpTo = xpApplied.leveledUpTo

  const bonusXp: { skillId: string; xp: number }[] = []
  const xpRewards: ActionXpRewardSummary[] = []
  const primaryReward = summarizeXpReward(
    db,
    next,
    skillId,
    xpAmount,
    xpApplied.leveledUpTo,
  )
  if (primaryReward) xpRewards.push(primaryReward)

  function applyBonusXp(bonusSkillId: string, amount: number) {
    if (amount <= 0) return
    const applied = applyXp(next, db, bonusSkillId, amount)
    next = applied.save
    bonusXp.push({ skillId: bonusSkillId, xp: amount })
    const reward = summarizeXpReward(db, next, bonusSkillId, amount, applied.leveledUpTo)
    if (reward) xpRewards.push(reward)
    if (applied.leveledUpTo != null) {
      leveledUpTo = applied.leveledUpTo
    }
  }

  const bonus = bonusSkillXpForAction(action)
  if (bonus && bonus.xp > 0) {
    applyBonusXp(bonus.skillId, gatheringXpReward(db, save, action, bonus.xp))
  }

  // Qualifying bow-based Hunting Actions also grant Combat XP (10% of the
  // Hunting XP just awarded) when a bow is the equipped Weapon/Tool.
  const bowBonus = bowHuntingCombatXpBonus(db, save, action, xpAmount)
  if (bowBonus) {
    applyBonusXp(bowBonus.skillId, bowBonus.xp)
  }

  next = addLifetimeStat(next, GATHERING_ACTIONS_STAT)
  if (rewarded.loot.length > 0) {
    next = recordGatheredDrops(
      next,
      rewarded.loot.map((drop) => drop.itemId),
      save.currentLocationId,
      save.equipment.slots[WEAPON_TOOL_SLOT_ID]?.itemId ?? null,
    )
  }
  next = applyQuestActionProgress(db, next, action['Action ID'])
  next = applyQuestAutoCompleteOnAction(db, next).save
  if (/Thievery/i.test(notes)) {
    next = consumeFoodAfterVictory(db, next).save
  }

  return {
    save: withoutHeldAction(next, save.currentActivityId),
    result: {
      actionId: action['Action ID'],
      actionName: action['Display Name'],
      skillId,
      xpGained: xpAmount,
      bonusXp,
      xpRewards,
      goldGained: rewarded.goldGained,
      loot: rewarded.loot,
      leveledUpTo,
    },
  }
}

export function activityStillValid(
  db: GameDatabase,
  save: PlayerSave,
  activityId: string,
): boolean {
  return validateActivityStart(db, save, activityId).ok
}

export function restoreActiveActionState(save: PlayerSave): ActiveActionState | null {
  if (!save.currentActionId || !save.actionStartedAt || save.actionDurationMs == null) {
    return null
  }
  return {
    actionId: save.currentActionId,
    startedAtMs: Date.parse(save.actionStartedAt),
    durationMs: save.actionDurationMs,
  }
}
