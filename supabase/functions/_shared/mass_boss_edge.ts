// Hosted mass-boss commands after applyGameCommand. Damage, lock, and payout
// all go through security-definer RPCs; this file supplies the rules math
// and the hosted save write.

import {
  applyMassVictory,
  beginCombatSave,
  bossProfile,
  clearActivitySave,
  clearCombatSave,
  enemyScaledMaxHp,
  getEnemy,
  isMassBossActivity,
  MASS_BOSS_ACTIVITY_ENEMY,
  parseMassSnapshot,
  playerBaseMaxHp,
  simulateMassFightTick,
  withBossRespawn,
} from './game_rules.js'

export const MASS_COMMANDS = new Set(['mass_join', 'mass_status', 'mass_fight_tick', 'mass_leave'])

export type MassRpcResult = { data: unknown; error: { message: string } | null }

export type MassRpcAdmin = {
  rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<MassRpcResult>
}

export type MassAuthorityResult = { ok: true; save: Record<string, unknown> } | { ok: false; reason: string }

export type MassCommandSettlement =
  | { kind: 'refused'; reason: string }
  | { kind: 'failed'; error: string; status: number }
  | {
      kind: 'ok'
      save: Record<string, unknown>
      dirty: boolean
      snapshot: ReturnType<typeof parseMassSnapshot>
    }

type RulesDb = Parameters<typeof playerBaseMaxHp>[0]
type RulesSave = Parameters<typeof playerBaseMaxHp>[1]
type RulesRandom = Parameters<typeof simulateMassFightTick>[2]['random']

function asString(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null
}

function enemyIdForActivity(activityId: string | null | undefined): string | null {
  if (!activityId) return null
  return MASS_BOSS_ACTIVITY_ENEMY[activityId] ?? null
}

function lockArgs(db: RulesDb, enemyId: string): {
  p_solo_hp: number
  p_player_base_hp_scale: number | null
} {
  const enemy = getEnemy(db, enemyId)
  const profile = enemy ? bossProfile(enemy) : null
  return {
    p_solo_hp: enemy ? enemyScaledMaxHp(enemy) : 1,
    p_player_base_hp_scale: profile?.playerBaseHpScale ?? null,
  }
}

async function rpcJson(
  admin: MassRpcAdmin,
  fn: string,
  args: Record<string, unknown>,
): Promise<{ ok: true; data: unknown } | { ok: false; error: string }> {
  const result = await Promise.resolve(admin.rpc(fn, args))
  if (result.error) return { ok: false, error: result.error.message }
  return { ok: true, data: result.data }
}

function finishMassSave(db: RulesDb, save: RulesSave, enemyId: string, nowMs: number): RulesSave {
  const enemy = getEnemy(db, enemyId)
  let next = clearActivitySave({ ...save, massEncounterId: null }, nowMs)
  if (enemy) next = withBossRespawn(clearCombatSave(next), enemy, nowMs)
  return next
}

async function claimIfSettled(
  db: RulesDb,
  admin: MassRpcAdmin,
  userId: string,
  save: RulesSave,
  snapshot: NonNullable<ReturnType<typeof parseMassSnapshot>>,
  random: RulesRandom,
  nowMs: number,
): Promise<{
  save: RulesSave
  snapshot: NonNullable<ReturnType<typeof parseMassSnapshot>>
  dirty: boolean
}> {
  if (snapshot.status !== 'settled') {
    return { save, snapshot, dirty: false }
  }
  const claimed = await rpcJson(admin, 'mass_claim_payout', {
    p_user_id: userId,
    p_encounter_id: snapshot.encounterId,
  })
  if (!claimed.ok) return { save, snapshot, dirty: false }
  const payload =
    claimed.data && typeof claimed.data === 'object' ? (claimed.data as Record<string, unknown>) : {}
  if (payload.closed === true) {
    return { save: finishMassSave(db, save, snapshot.enemyId, nowMs), snapshot, dirty: true }
  }
  const enemy = getEnemy(db, snapshot.enemyId)
  if (!enemy) {
    return { save: finishMassSave(db, save, snapshot.enemyId, nowMs), snapshot, dirty: true }
  }
  const eligible = payload.eligible === true
  const dropScaleRaw = payload.dropScale ?? snapshot.dropScale
  const dropScale = typeof dropScaleRaw === 'number' ? dropScaleRaw : Number(dropScaleRaw)
  let next = save
  if (eligible && payload.alreadyClaimed !== true) {
    next = applyMassVictory(db, next, enemy, random, nowMs, dropScale).save
  }
  next = finishMassSave(db, next, snapshot.enemyId, nowMs)
  return { save: next, snapshot, dirty: true }
}

async function refreshEncounter(
  db: RulesDb,
  admin: MassRpcAdmin,
  userId: string,
  encounterId: string,
  enemyId: string,
): Promise<{ snapshot: ReturnType<typeof parseMassSnapshot>; error?: string }> {
  const args = lockArgs(db, enemyId)
  const result = await rpcJson(admin, 'mass_status', {
    p_user_id: userId,
    p_encounter_id: encounterId,
    p_solo_hp: args.p_solo_hp,
    p_player_base_hp_scale: args.p_player_base_hp_scale,
  })
  if (!result.ok) return { snapshot: null, error: result.error }
  return { snapshot: parseMassSnapshot(result.data) }
}

export async function leaveMassEncounter(
  admin: MassRpcAdmin,
  userId: string,
  encounterId: string | null | undefined,
): Promise<void> {
  if (!encounterId) return
  await rpcJson(admin, 'mass_leave', {
    p_user_id: userId,
    p_encounter_id: encounterId,
  })
}

export async function settleMassCommand(options: {
  command: string
  commandResult: MassAuthorityResult
  admin: MassRpcAdmin
  db: RulesDb
  userId: string
  args: Record<string, unknown>
  previousEncounterId: string | null
  nowMs: number
  random: RulesRandom
}): Promise<MassCommandSettlement> {
  if (!options.commandResult.ok) {
    return { kind: 'refused', reason: options.commandResult.reason }
  }
  let save = options.commandResult.save as RulesSave
  const { admin, db, userId, nowMs, random } = options

  if (options.command === 'mass_leave') {
    await leaveMassEncounter(admin, userId, options.previousEncounterId ?? save.massEncounterId)
    save = { ...save, massEncounterId: null }
    return { kind: 'ok', save, dirty: true, snapshot: null }
  }

  if (options.command === 'mass_join') {
    if (options.previousEncounterId) {
      await leaveMassEncounter(admin, userId, options.previousEncounterId)
    }
    const activityId = asString(options.args.activityId) ?? save.currentActivityId
    if (!activityId || !isMassBossActivity(activityId)) {
      return { kind: 'refused', reason: 'That is not a mass boss.' }
    }
    const enemyId = enemyIdForActivity(activityId)
    if (!enemyId) return { kind: 'refused', reason: 'That is not a mass boss.' }
    const joined = await rpcJson(admin, 'mass_join', {
      p_user_id: userId,
      p_enemy_id: enemyId,
      p_username: save.characterName ?? 'Adventurer',
      p_player_base_hp: playerBaseMaxHp(db, save),
    })
    if (!joined.ok) return { kind: 'failed', error: joined.error, status: 500 }
    const row = joined.data && typeof joined.data === 'object' ? (joined.data as Record<string, unknown>) : {}
    if (row.ok === false && typeof row.reason === 'string') {
      return { kind: 'refused', reason: row.reason }
    }
    const snapshot = parseMassSnapshot(joined.data)
    if (!snapshot) return { kind: 'failed', error: 'Could not join that fight.', status: 500 }
    let next: RulesSave = { ...save, massEncounterId: snapshot.encounterId }
    if (snapshot.status === 'fighting') {
      const enemy = getEnemy(db, enemyId)
      const action = db.Actions.find(
        (candidate: { Category?: string; 'Target ID'?: string }) =>
          candidate.Category === 'Combat' && candidate['Target ID'] === enemyId,
      )
      if (enemy && action) {
        next = {
          ...beginCombatSave(db, next, action, enemy, new Date(nowMs).toISOString(), snapshot.remainingHp),
          massEncounterId: snapshot.encounterId,
        }
      }
    }
    return { kind: 'ok', save: next, dirty: true, snapshot }
  }

  const encounterId = asString(options.args.encounterId) ?? save.massEncounterId
  if (!encounterId) {
    return { kind: 'refused', reason: 'You are not in a mass fight.' }
  }
  const enemyId = enemyIdForActivity(save.currentActivityId) ?? asString(options.args.enemyId)
  if (!enemyId) return { kind: 'refused', reason: 'That is not a mass boss.' }

  const refreshed = await refreshEncounter(db, admin, userId, encounterId, enemyId)
  if (refreshed.error) return { kind: 'failed', error: refreshed.error, status: 500 }
  let snapshot = refreshed.snapshot
  if (!snapshot) return { kind: 'failed', error: 'Unknown mass encounter.', status: 400 }

  if (snapshot.status === 'closed') {
    return {
      kind: 'ok',
      save: finishMassSave(db, save, snapshot.enemyId, nowMs),
      dirty: true,
      snapshot,
    }
  }

  if (snapshot.status === 'settled') {
    const claimed = await claimIfSettled(db, admin, userId, save, snapshot, random, nowMs)
    return { kind: 'ok', save: claimed.save, dirty: claimed.dirty, snapshot }
  }

  if (snapshot.status !== 'fighting' || options.command === 'mass_status') {
    if (snapshot.status === 'fighting' && !save.combatEnemyId) {
      const enemy = getEnemy(db, snapshot.enemyId)
      const action = db.Actions.find(
        (candidate: { Category?: string; 'Target ID'?: string }) =>
          candidate.Category === 'Combat' && candidate['Target ID'] === snapshot.enemyId,
      )
      if (enemy && action) {
        const next = {
          ...beginCombatSave(
            db,
            { ...save, massEncounterId: snapshot.encounterId },
            action,
            enemy,
            new Date(nowMs).toISOString(),
            snapshot.remainingHp,
          ),
          massEncounterId: snapshot.encounterId,
        }
        return { kind: 'ok', save: next, dirty: true, snapshot }
      }
    }
    const next =
      save.massEncounterId === snapshot.encounterId ? save : { ...save, massEncounterId: snapshot.encounterId }
    return { kind: 'ok', save: next, dirty: next !== save, snapshot }
  }

  const you = snapshot.you
  const tick = simulateMassFightTick(db, { ...save, massEncounterId: snapshot.encounterId }, {
    nowMs,
    random,
    encounterId: snapshot.encounterId,
    enemyId: snapshot.enemyId,
    sharedRemainingHp: snapshot.remainingHp,
    healthMultiplier: snapshot.healthMultiplier || 1,
    lockedIn: you?.lockedIn === true,
    late: you?.late === true,
    lastRoundStartedAt: you?.lastRoundStartedAt ?? null,
  })
  let next = tick.save
  let dirty = tick.started || tick.defeated || tick.kill || (!tick.early && !tick.duplicate)

  if (!tick.early && !tick.duplicate && !tick.started) {
    const recorded = await rpcJson(admin, 'mass_record_damage', {
      p_user_id: userId,
      p_encounter_id: snapshot.encounterId,
      p_damage: tick.damageDealt,
      p_round_started_at: tick.roundStartedAt,
    })
    if (recorded.ok) {
      const after = parseMassSnapshot(recorded.data)
      if (after) snapshot = after
      dirty = true
    }
  }

  if (snapshot.status === 'closed') {
    next = finishMassSave(db, next, snapshot.enemyId, nowMs)
    dirty = true
  } else if (tick.kill || snapshot.remainingHp <= 0) {
    const settled = await rpcJson(admin, 'mass_settle', { p_encounter_id: snapshot.encounterId })
    if (settled.ok) {
      const after = parseMassSnapshot(settled.data)
      if (after) snapshot = after
      if (snapshot.status === 'settled') {
        const claimed = await claimIfSettled(db, admin, userId, next, snapshot, random, nowMs)
        next = claimed.save
        snapshot = claimed.snapshot
        dirty = true
      }
    }
  }

  return { kind: 'ok', save: next, dirty, snapshot }
}
