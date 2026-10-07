// Server-authoritative game function.
//
// Phase 0 `prototype` times ticks on copies. Phase 1 `shadow` advances the
// server's copy beside a client upload and logs diffs. Neither writes
// `player_saves`. `sync` and `command` stay 501 until phase 2.

import { createClient } from 'npm:@supabase/supabase-js@2'

import rawDatabase from '../_shared/game-database.json' with { type: 'json' }
import { runPhase0Prototype, runPhase1Shadow } from '../_shared/game_rules.js'

const SHADOW_MIN_INTERVAL_MS = 90_000

type GameBody = {
  action?: unknown
  awayMs?: unknown
  save?: unknown
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
  if (action === 'sync' || action === 'command') {
    return json(
      {
        error: 'Phase 1 shadow only. sync and command are not live yet.',
        phase: 1,
      },
      501,
    )
  }

  const admin = connect(supabaseUrl, serviceKey)

  if (action === 'shadow') {
    return handleShadow(admin, user.id)
  }

  if (action && action !== 'prototype') {
    return json({ error: 'Unknown action.', phase: 1 }, 400)
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

async function loadHostedSaveCopy(admin: Client, userId: string): Promise<unknown> {
  const { data } = await admin.from('player_saves').select('payload').eq('user_id', userId).maybeSingle()
  return data?.payload ?? undefined
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
