// Phase 0 prototype of the server-authoritative game function.
//
// Bundles `src/game` (via `npm run bundle:game-edge`) and times
// `advanceSession` plus the unattended resolver on copies of saves.
// It never writes `player_saves`. `sync` and `command` are not live.

import { createClient } from 'npm:@supabase/supabase-js@2'

import rawDatabase from '../_shared/game-database.json' with { type: 'json' }
import { runPhase0Prototype } from '../_shared/game_rules.js'

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
        error: 'Phase 0 prototype only. sync and command are not live yet.',
        phase: 0,
      },
      501,
    )
  }
  if (action && action !== 'prototype') {
    return json({ error: 'Unknown action.', phase: 0 }, 400)
  }

  const awayMs = parseAwayMs(payload.awayMs)
  if (awayMs === null) {
    return json({ error: 'awayMs must be a whole number of milliseconds.' }, 400)
  }

  let hostedSave = payload.save
  if (hostedSave === undefined) {
    const admin = connect(supabaseUrl, serviceKey)
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
