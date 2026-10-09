// Server-authoritative game function.
//
// Phase 3: `submit_leaderboard` and `save_pvp_equipment` write ranking rows
// from the hosted save. Phase 2 `sync` / `command` still write `player_saves`.
// Phase 1 `shadow` and phase 0 `prototype` stay available.

import { createClient } from 'npm:@supabase/supabase-js@2'

import rawDatabase from '../_shared/game-database.json' with { type: 'json' }
import {
  applyDevCommand,
  applyGameCommand,
  createTrackedMulberry32,
  overlayPublishedPvpSnapshot,
  parseSave,
  prepareDatabase,
  pvpSnapshotRowForSave,
  rankingBoardRowsFor,
  rankingProfilePatch,
  runPhase0Prototype,
  runPhase1Shadow,
  runPhase2Sync,
} from '../_shared/game_rules.js'

const SHADOW_MIN_INTERVAL_MS = 90_000

type GameBody = {
  action?: unknown
  awayMs?: unknown
  save?: unknown
  command?: unknown
  args?: unknown
  tokens?: unknown
  version?: unknown
  playSessionId?: unknown
}

function connect(url: string, key: string, options?: Parameters<typeof createClient>[2]) {
  return createClient(url, key, options)
}

type Client = ReturnType<typeof connect>

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: cors() })
  }

  const authHeader = req.headers.get('Authorization') ?? ''
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return json({ error: 'Function is missing Supabase secrets.' }, 500)
  }

  const asUser = connect(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  })
  const { data: userData, error: userError } = await asUser.auth.getUser()
  const user = userData.user
  if (userError || !user) {
    return json({ error: 'Sign in required.' }, 401)
  }

  let payload: GameBody
  try {
    payload = (await req.json()) as GameBody
  } catch {
    return json({ error: 'Body must be JSON.' }, 400)
  }

  const action = typeof payload.action === 'string' ? payload.action.trim() : ''
  const admin = connect(supabaseUrl, serviceKey)

  if (action === 'sync' || action === 'command' || action === 'dev_command') {
    const seated = await refuseOtherPlaySession(admin, user.id, payload)
    if (seated) return seated
  }
  if (action === 'sync') {
    return handleSync(admin, user.id, payload)
  }
  if (action === 'command') {
    return handleCommand(admin, user.id, payload)
  }
  if (action === 'dev_status') {
    return handleDevStatus(admin, user.id)
  }
  if (action === 'dev_command') {
    return handleDevCommand(admin, user.id, payload)
  }
  if (action === 'shadow') {
    return handleShadow(admin, user.id)
  }

  if (action && action !== 'prototype') {
    return json({ error: 'Unknown action.', phase: 2 }, 400)
  }

  const awayMs = parseAwayMs(payload.awayMs)
  if (awayMs === null) {
    return json({ error: 'awayMs must be a whole number of milliseconds.' }, 400)
  }

  let hostedSave = payload.save
  if (hostedSave === undefined) {
    hostedSave = await loadHostedSaveCopy(admin, user.id)
  }

  try {
    const started = performance.now()
    const result = runPhase0Prototype(rawDatabase, {
      hostedSave,
      awayMs,
    })
    return json({
      ok: true,
      ...result,
      totalMs: performance.now() - started,
      wroteSave: false,
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Prototype failed.'
    return json({ error: message, phase: 0 }, 400)
  }
})

async function handleShadow(admin: Client, userId: string): Promise<Response> {
  const hosted = await loadHostedSaveCopy(admin, userId)
  if (hosted === undefined) {
    return json({ error: 'No cloud save to shadow.', phase: 1 }, 400)
  }

  const { data: shadow, error: shadowReadError } = await admin
    .from('player_save_shadows')
    .select('last_client_payload, own_payload, advanced_to')
    .eq('user_id', userId)
    .maybeSingle()
  if (shadowReadError) {
    return json({ error: shadowReadError.message, phase: 1 }, 500)
  }

  const nowMs = Date.now()
  const advancedTo = new Date(nowMs).toISOString()

  if (!shadow) {
    const { error: writeError } = await admin.from('player_save_shadows').upsert({
      user_id: userId,
      last_client_payload: hosted,
      own_payload: hosted,
      advanced_to: advancedTo,
    })
    if (writeError) return json({ error: writeError.message, phase: 1 }, 500)
    const { error: logError } = await admin.from('player_save_shadow_diffs').insert({
      user_id: userId,
      initialized: true,
      skipped: false,
      matched: true,
      own_matched: true,
      diff_count: 0,
      diffs: { replay: [], own: [] },
    })
    if (logError) return json({ error: logError.message, phase: 1 }, 500)
    return json({
      ok: true,
      phase: 1,
      initialized: true,
      skipped: false,
      matched: true,
      wroteSave: false,
    })
  }

  const { data: lastDiff } = await admin
    .from('player_save_shadow_diffs')
    .select('created_at')
    .eq('user_id', userId)
    .eq('skipped', false)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()
  if (lastDiff?.created_at) {
    const lastMs = Date.parse(String(lastDiff.created_at))
    if (Number.isFinite(lastMs) && nowMs - lastMs < SHADOW_MIN_INTERVAL_MS) {
      return json({
        ok: true,
        phase: 1,
        initialized: false,
        skipped: true,
        wroteSave: false,
      })
    }
  }

  try {
    const started = performance.now()
    const result = runPhase1Shadow(rawDatabase, {
      previousClientSave: shadow.last_client_payload,
      currentClientSave: hosted,
      ownSave: shadow.own_payload,
      nowMs,
    })
    const { error: writeError } = await admin.from('player_save_shadows').upsert({
      user_id: userId,
      last_client_payload: hosted,
      own_payload: result.ownSave,
      advanced_to: advancedTo,
    })
    if (writeError) return json({ error: writeError.message, phase: 1 }, 500)
    const { error: logError } = await admin.from('player_save_shadow_diffs').insert({
      user_id: userId,
      initialized: false,
      skipped: false,
      matched: result.replayMatched,
      own_matched: result.ownMatched,
      diff_count: result.replay.length + result.own.length,
      diffs: { replay: result.replay, own: result.own },
      advance_ms: result.timing.advanceMs,
      unattended_ms: result.timing.unattendedMs,
      effective_elapsed_ms: result.timing.effectiveElapsedMs,
    })
    if (logError) return json({ error: logError.message, phase: 1 }, 500)
    return json({
      ok: true,
      phase: 1,
      initialized: false,
      skipped: false,
      matched: result.replayMatched,
      ownMatched: result.ownMatched,
      diffCount: result.replay.length,
      diffs: result.replay,
      gatheringActions: result.timing.gatheringActions,
      totalMs: performance.now() - started,
      wroteSave: false,
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Shadow failed.'
    return json({ error: message, phase: 1 }, 400)
  }
}

type HostedSaveRow = {
  payload: unknown
  version: number
  advanced_to: string | null
  rng_state: number
  play_session_id: string | null
}

async function loadHostedRow(admin: Client, userId: string): Promise<HostedSaveRow | null> {
  const { data } = await admin
    .from('player_saves')
    .select('payload, version, advanced_to, rng_state, play_session_id')
    .eq('user_id', userId)
    .maybeSingle()
  if (!data) return null
  return {
    payload: data.payload,
    version: typeof data.version === 'number' ? data.version : 1,
    advanced_to: typeof data.advanced_to === 'string' ? data.advanced_to : null,
    rng_state: typeof data.rng_state === 'number' ? data.rng_state >>> 0 : 1,
    play_session_id: typeof data.play_session_id === 'string' ? data.play_session_id : null,
  }
}

async function loadHostedSaveCopy(admin: Client, userId: string): Promise<unknown> {
  const row = await loadHostedRow(admin, userId)
  return row?.payload
}

async function refuseOtherPlaySession(
  admin: Client,
  userId: string,
  payload: GameBody,
): Promise<Response | null> {
  const { data } = await admin
    .from('profiles')
    .select('active_play_session_id')
    .eq('user_id', userId)
    .maybeSingle()
  const active = typeof data?.active_play_session_id === 'string' ? data.active_play_session_id : ''
  if (!active) return null
  const claimed = typeof payload.playSessionId === 'string' ? payload.playSessionId : ''
  if (!claimed || claimed !== active) {
    return json({ error: 'Signed in on another device.', phase: 2 }, 409)
  }
  return null
}

async function handleSync(admin: Client, userId: string, payload: GameBody): Promise<Response> {
  const hosted = await loadHostedRow(admin, userId)
  if (!hosted) return json({ error: 'No cloud save.', phase: 2 }, 400)
  const expected = parseVersion(payload.version, hosted.version)
  if (expected === null) return json({ error: 'version must be a whole number.', phase: 2 }, 400)
  const nowMs = Date.now()
  try {
    const result = runPhase2Sync(rawDatabase, {
      save: hosted.payload,
      nowMs,
      rngState: hosted.rng_state,
    })
    const written = await writeHostedSave(admin, userId, {
      expectedVersion: expected,
      payload: result.save,
      rngState: result.rngState,
      nowMs,
    })
    if (!written.ok) return written.response
    const published = await publishPhase3Rows(admin, rawDatabase, userId, result.save, nowMs)
    if (!published.ok) return published.response
    return json({
      ok: true,
      phase: 2,
      action: 'sync',
      save: result.save,
      version: written.version,
      rngState: result.rngState,
      gatheringActions: result.gatheringActions,
      wroteSave: true,
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Sync failed.'
    return json({ error: message, phase: 2 }, 400)
  }
}

async function handleCommand(admin: Client, userId: string, payload: GameBody): Promise<Response> {
  const command = typeof payload.command === 'string' ? payload.command.trim() : ''
  if (!command) return json({ error: 'Missing command.', phase: 2 }, 400)
  const args = payload.args && typeof payload.args === 'object' ? (payload.args as Record<string, unknown>) : {}
  const nowMs = Date.now()
  const hosted = await loadHostedRow(admin, userId)
  const expected = parseVersion(payload.version, hosted?.version ?? 0)
  if (expected === null) return json({ error: 'version must be a whole number.', phase: 2 }, 400)

  const hallContext = await loadHallContext(admin, userId)
  const rng = createTrackedMulberry32(hosted?.rng_state ?? ((nowMs ^ userId.length) >>> 0))
  try {
    const result = applyGameCommand(rawDatabase, {
      command,
      args,
      save: hosted?.payload,
      nowMs,
      random: rng.random,
      hall: hallContext?.hall,
      userId,
      guildRole: hallContext?.role,
    })
    if (!result.ok) return json({ error: result.reason, phase: 2 }, 400)
    let foundedGuild: Record<string, unknown> | null = null
    if (command === 'guild_create') {
      const founded = await foundGuild(admin, userId, args)
      if (!founded.ok) return founded.response
      foundedGuild = founded.guild
    }
    const written = hosted
      ? await writeHostedSave(admin, userId, {
          expectedVersion: expected,
          payload: result.save,
          rngState: rng.getState(),
          nowMs,
        })
      : await insertHostedSave(admin, userId, {
          payload: result.save,
          rngState: rng.getState(),
          nowMs,
        })
    if (!written.ok) {
      // The gold was not taken, so the guild it paid for goes back.
      if (foundedGuild) await admin.from('guilds').delete().eq('id', foundedGuild.id)
      return written.response
    }
    const published = await publishPhase3Rows(admin, rawDatabase, userId, result.save, nowMs, command)
    if (!published.ok) return published.response
    if (result.hall && hallContext) {
      const { error: hallError } = await admin
        .from('guild_halls')
        .update({
          debt_remaining: result.hall.debtRemaining,
          debt_paid_off: result.hall.debtPaidOff,
          debt_paid_by: result.hall.debtPaidBy,
          storehouse: result.hall.storehouse,
          completed_tiers: result.hall.completedTiers,
          updated_at: new Date(nowMs).toISOString(),
        })
        .eq('guild_id', hallContext.guildId)
      if (hallError) return json({ error: hallError.message, phase: 2 }, 500)
    }
    return json({
      ok: true,
      phase: 2,
      action: 'command',
      command,
      save: result.save,
      version: written.version,
      rngState: rng.getState(),
      wroteSave: true,
      ...(foundedGuild ? { guild: foundedGuild } : {}),
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Command failed.'
    return json({ error: message, phase: 2 }, 400)
  }
}

async function handleDevStatus(admin: Client, userId: string): Promise<Response> {
  const { data, error } = await admin
    .from('developer_accounts')
    .select('user_id')
    .eq('user_id', userId)
    .maybeSingle()
  if (error) return json({ error: error.message, phase: 2 }, 500)
  return json({ ok: true, phase: 2, action: 'dev_status', developer: Boolean(data?.user_id) })
}

async function handleDevCommand(admin: Client, userId: string, payload: GameBody): Promise<Response> {
  const command = typeof payload.command === 'string' ? payload.command.trim().toLowerCase() : ''
  if (!command) return json({ error: 'Missing command.', phase: 2 }, 400)
  const tokens = Array.isArray(payload.tokens)
    ? payload.tokens.filter((part): part is string => typeof part === 'string')
    : []

  const { data: allow, error: allowError } = await admin
    .from('developer_accounts')
    .select('user_id')
    .eq('user_id', userId)
    .maybeSingle()
  if (allowError) return json({ error: allowError.message, phase: 2 }, 500)
  if (!allow?.user_id) {
    await admin.from('developer_audit_log').insert({
      user_id: userId,
      command,
      args: { tokens },
      ok: false,
      reason: 'Not a developer account.',
    })
    return json({ error: 'Not a developer account.', phase: 2, action: 'dev_command' }, 403)
  }

  const nowMs = Date.now()
  const hosted = await loadHostedRow(admin, userId)
  if (!hosted) return json({ error: 'No cloud save.', phase: 2 }, 400)
  const expected = parseVersion(payload.version, hosted.version)
  if (expected === null) return json({ error: 'version must be a whole number.', phase: 2 }, 400)

  const { launch } = prepareDatabase(rawDatabase)
  let result
  try {
    const playerSave = parseSave(hosted.payload, nowMs)
    result = applyDevCommand(launch, playerSave, command, tokens, nowMs)
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Command failed.'
    await admin.from('developer_audit_log').insert({
      user_id: userId,
      command,
      args: { tokens },
      ok: false,
      reason: message,
    })
    return json({ error: message, phase: 2, action: 'dev_command' }, 400)
  }

  await admin.from('developer_audit_log').insert({
    user_id: userId,
    command,
    args: { tokens },
    ok: result.ok,
    reason: result.ok ? result.message : result.reason,
  })

  if (!result.ok) {
    return json({ error: result.reason, phase: 2, action: 'dev_command', message: result.reason }, 400)
  }

  const rng = createTrackedMulberry32(hosted.rng_state ?? ((nowMs ^ userId.length) >>> 0))
  const written = await writeHostedSave(admin, userId, {
    expectedVersion: expected,
    payload: result.save,
    rngState: rng.getState(),
    nowMs,
  })
  if (!written.ok) return written.response
  const published = await publishPhase3Rows(admin, rawDatabase, userId, result.save, nowMs, `dev:${command}`)
  if (!published.ok) return published.response
  return json({
    ok: true,
    phase: 2,
    action: 'dev_command',
    command,
    message: result.message,
    save: result.save,
    version: written.version,
    rngState: rng.getState(),
    wroteSave: true,
  })
}

// Writes the guild, its leader, hall, and starter goals in one transaction.
async function foundGuild(
  admin: Client,
  userId: string,
  args: Record<string, unknown>,
): Promise<{ ok: true; guild: Record<string, unknown> } | { ok: false; response: Response }> {
  const guild = args.guild && typeof args.guild === 'object' ? (args.guild as Record<string, unknown>) : {}
  const { data, error } = await admin.rpc('guild_create_hosted', {
    p_user_id: userId,
    p_guild: { ...guild, name: args.name, tag: args.tag },
  })
  if (error) return { ok: false, response: json({ error: error.message, phase: 2 }, 400) }
  const answer = (data ?? {}) as { ok?: boolean; reason?: string; guild?: Record<string, unknown> }
  if (answer.ok !== true || !answer.guild) {
    return { ok: false, response: json({ error: answer.reason ?? 'The guild was not created.', phase: 2 }, 400) }
  }
  return { ok: true, guild: answer.guild }
}

async function publishPhase3Rows(
  admin: Client,
  rawDatabase: unknown,
  userId: string,
  save: unknown,
  nowMs: number,
  command?: string,
): Promise<{ ok: true } | { ok: false; response: Response }> {
  const nowIso = new Date(nowMs).toISOString()
  const { launch } = prepareDatabase(rawDatabase)
  const hosted = save as Parameters<typeof rankingProfilePatch>[0]
  const overlaid = await refreshPublishedPvp(admin, userId, hosted, nowMs, nowIso)
  if (!overlaid.ok) return overlaid
  if (command === 'submit_leaderboard') {
    const rows = rankingBoardRowsFor(launch, hosted, userId, nowIso)
    const { error: boardError } = await admin.from('leaderboard_snapshots').upsert(rows, {
      onConflict: 'user_id,board_key',
    })
    if (boardError) return { ok: false, response: json({ error: boardError.message, phase: 3 }, 500) }
    const { error: profileError } = await admin
      .from('profiles')
      .update(rankingProfilePatch(hosted))
      .eq('user_id', userId)
    if (profileError) return { ok: false, response: json({ error: profileError.message, phase: 3 }, 500) }
  }
  if (command === 'save_pvp_equipment') {
    const { data: profile } = await admin.from('profiles').select('username').eq('user_id', userId).maybeSingle()
    const username = typeof profile?.username === 'string' ? profile.username : 'Adventurer'
    const row = pvpSnapshotRowForSave({ userId, username, save: hosted, nowIso })
    const { error: pvpError } = await admin.from('pvp_snapshots').upsert(row, { onConflict: 'user_id' })
    if (pvpError) return { ok: false, response: json({ error: pvpError.message, phase: 3 }, 500) }
  }
  return { ok: true }
}

async function refreshPublishedPvp(
  admin: Client,
  userId: string,
  live: Parameters<typeof rankingProfilePatch>[0],
  nowMs: number,
  nowIso: string,
): Promise<{ ok: true } | { ok: false; response: Response }> {
  const { data, error } = await admin.from('pvp_snapshots').select('payload, username').eq('user_id', userId).maybeSingle()
  if (error) return { ok: false, response: json({ error: error.message, phase: 3 }, 500) }
  if (!data) return { ok: true }
  const merged = overlayPublishedPvpSnapshot(data.payload, live, nowMs)
  if (!merged) return { ok: true }
  const username = typeof data.username === 'string' ? data.username : 'Adventurer'
  const row = pvpSnapshotRowForSave({ userId, username, save: merged, nowIso })
  const { error: writeError } = await admin.from('pvp_snapshots').upsert(row, { onConflict: 'user_id' })
  if (writeError) return { ok: false, response: json({ error: writeError.message, phase: 3 }, 500) }
  return { ok: true }
}

async function writeHostedSave(
  admin: Client,
  userId: string,
  options: { expectedVersion: number; payload: unknown; rngState: number; nowMs: number },
): Promise<{ ok: true; version: number } | { ok: false; response: Response }> {
  const advancedTo = new Date(options.nowMs).toISOString()
  const { data, error } = await admin
    .from('player_saves')
    .update({
      payload: options.payload,
      version: options.expectedVersion + 1,
      advanced_to: advancedTo,
      rng_state: options.rngState,
      updated_at: advancedTo,
    })
    .eq('user_id', userId)
    .eq('version', options.expectedVersion)
    .select('version')
    .maybeSingle()
  if (error) return { ok: false, response: json({ error: error.message, phase: 2 }, 500) }
  if (!data) {
    return {
      ok: false,
      response: json({ error: 'Save version conflict. Sync and retry.', phase: 2, conflict: true }, 409),
    }
  }
  return { ok: true, version: data.version as number }
}

async function insertHostedSave(
  admin: Client,
  userId: string,
  options: { payload: unknown; rngState: number; nowMs: number },
): Promise<{ ok: true; version: number } | { ok: false; response: Response }> {
  const advancedTo = new Date(options.nowMs).toISOString()
  const { data, error } = await admin
    .from('player_saves')
    .insert({
      user_id: userId,
      save_version: 60,
      payload: options.payload,
      version: 1,
      advanced_to: advancedTo,
      rng_state: options.rngState,
      updated_at: advancedTo,
    })
    .select('version')
    .maybeSingle()
  if (error) return { ok: false, response: json({ error: error.message, phase: 2 }, 409) }
  return { ok: true, version: (data?.version as number) ?? 1 }
}

type HallContext = {
  guildId: string
  role: string
  hall: {
    debtRemaining: number
    debtPaidOff: boolean
    debtPaidBy: Record<string, number>
    storehouse: unknown[]
    completedTiers: string[]
  }
}

async function loadHallContext(admin: Client, userId: string): Promise<HallContext | null> {
  const { data: member } = await admin
    .from('guild_members')
    .select('guild_id, role')
    .eq('user_id', userId)
    .maybeSingle()
  if (!member?.guild_id) return null
  const { data: hall } = await admin.from('guild_halls').select('*').eq('guild_id', member.guild_id).maybeSingle()
  if (!hall) return null
  return {
    guildId: member.guild_id as string,
    role: String(member.role ?? ''),
    hall: {
      debtRemaining: Number(hall.debt_remaining ?? 0),
      debtPaidOff: Boolean(hall.debt_paid_off),
      debtPaidBy: (hall.debt_paid_by ?? {}) as Record<string, number>,
      storehouse: Array.isArray(hall.storehouse) ? hall.storehouse : [],
      completedTiers: Array.isArray(hall.completed_tiers)
        ? hall.completed_tiers.map((row: unknown) => String(row))
        : [],
    },
  }
}

function parseVersion(value: unknown, fallback: number): number | null {
  if (value === undefined || value === null || value === '') return fallback
  if (typeof value !== 'number' || !Number.isFinite(value) || !Number.isInteger(value) || value < 0) {
    return null
  }
  return value
}

function parseAwayMs(value: unknown): number | undefined | null {
  if (value === undefined || value === null || value === '') return undefined
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || !Number.isInteger(value)) {
    return null
  }
  return value
}

function cors(): HeadersInit {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }
}

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors(), 'Content-Type': 'application/json' },
  })
}
