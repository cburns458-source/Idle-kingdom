import {
  beginCombatSave,
  clearCombatSave,
  enemyForAction,
  isDeathPaused,
} from '../combat/engine'
import { clearProductionSave } from '../production/engine'
import { isStandardProductionActivity, recipesForActivity } from '../production/recipes'
import type { ActionRow, ActivityRow, GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { clearActivePotionEffect, tryConsumePotionForScope } from '../potions/effects'
import { applyRaceSkillXp } from '../races/races'
import { gatheringDurationMs, gatheringXpReward } from './gathering'
import { eligiblePoolEntries, pickWeightedAction, type RandomFn } from './pools'
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
import { bonusSkillXpForAction, bowHuntingCombatXpBonus } from './bonusXp'
import { summarizeXpReward } from './rewardSummary'
import { applyXp } from './xp'

export function getActivity(db: GameDatabase, activityId: string): ActivityRow | undefined {
  return db.Activities.find((row) => row['Activity ID'] === activityId)
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
  const eligible = eligiblePoolEntries(db, activity['Pool ID'])
  const action = pickWeightedAction(eligible, random)
  if (!action) return null

  const startedAt = new Date(nowMs).toISOString()

  if (action.Category === 'Combat') {
    const enemy = enemyForAction(db, action)
    if (!enemy) return null
    const withActivity = {
      ...save,
      currentActivityId: activityId,
      activityStartedAt: save.activityStartedAt ?? startedAt,
    }
    return {
      action,
      state: null,
      save: beginCombatSave(db, withActivity, action, enemy, startedAt),
    }
  }

  const durationMs = gatheringDurationMs(db, save, action)
  let next = clearCombatSave({
    ...save,
    currentActivityId: activityId,
    currentActionId: action['Action ID'],
    actionStartedAt: startedAt,
    actionDurationMs: durationMs,
  })
  const potion = tryConsumePotionForScope(db, next, 'one_action')
  next = potion.save
  return {
    action,
    state: {
      actionId: action['Action ID'],
      startedAtMs: nowMs,
      durationMs,
    },
    save: next,
  }
}

export function completeGatheringAction(
  db: GameDatabase,
  save: PlayerSave,
  action: ActionRow,
  random: RandomFn = Math.random,
): { save: PlayerSave; result: ActionCompletionResult } {
  const rewarded = resolveActionRewards(db, save, action, random)
  const xpAmount = applyRaceSkillXp(
    db,
    save,
    action['Relevant Skill ID'],
    gatheringXpReward(db, save, action),
  )
  let next = clearActivePotionEffect(rewarded.save)
  const xpApplied = applyXp(next, db, action['Relevant Skill ID'], xpAmount)
  next = xpApplied.save
  let leveledUpTo = xpApplied.leveledUpTo

  const bonusXp: { skillId: string; xp: number }[] = []
  const xpRewards: ActionXpRewardSummary[] = []
  const primaryReward = summarizeXpReward(
    db,
    next,
    action['Relevant Skill ID'],
    xpAmount,
    xpApplied.leveledUpTo,
  )
  if (primaryReward) xpRewards.push(primaryReward)

  function applyBonusXp(skillId: string, amount: number) {
    if (amount <= 0) return
    const raced = applyRaceSkillXp(db, save, skillId, amount)
    if (raced <= 0) return
    const applied = applyXp(next, db, skillId, raced)
    next = applied.save
    bonusXp.push({ skillId, xp: raced })
    const reward = summarizeXpReward(db, next, skillId, raced, applied.leveledUpTo)
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

  return {
    save: next,
    result: {
      actionId: action['Action ID'],
      actionName: action['Display Name'],
      skillId: action['Relevant Skill ID'],
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
