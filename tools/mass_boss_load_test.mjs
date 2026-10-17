#!/usr/bin/env node
// 100 concurrent damage writes against the TEST project. Gate for SOC-04:
// if this fails, stop and do not build lobbies. Asserts (and exits 1) when
// summed recorded damage is not the expected total, the boss does not settle
// exactly once, or locked_count is not 100.
import { createClient } from '@supabase/supabase-js'

const TEST_HOST = 'xlbwmxxtzrqjujvgqcuf.supabase.co'
const url = process.env.SUPABASE_TEST_URL || process.env.SUPABASE_URL
const key = process.env.SUPABASE_TEST_SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY
if (!url || !key) {
  console.error('Need SUPABASE_TEST_URL and SUPABASE_TEST_SERVICE_ROLE_KEY')
  process.exit(2)
}
if (!url.includes(TEST_HOST)) {
  console.error('Refusing to run against a non-test Supabase project')
  process.exit(2)
}

const PLAYERS = 100
const DAMAGE_EACH = 1
const EXPECTED_CONCURRENT_DAMAGE = PLAYERS * DAMAGE_EACH
const SOLO_HP = 1000

const admin = createClient(url, key, { auth: { persistSession: false } })
const users = Array.from({ length: PLAYERS }, (_, i) =>
  `00000000-0000-4000-8000-${String(i + 1).padStart(12, '0')}`,
)

function fail(reason, extra = {}) {
  const error = new Error(reason)
  error.payload = { ok: false, reason, ...extra }
  throw error
}

function assert(condition, reason, extra = {}) {
  if (!condition) fail(reason, extra)
}

async function damageSum(encounterId) {
  const { data, error } = await admin
    .from('mass_participants')
    .select('damage_dealt')
    .eq('encounter_id', encounterId)
  if (error) fail('could not read damage_dealt', { error })
  return (data ?? []).reduce((sum, row) => sum + Number(row.damage_dealt ?? 0), 0)
}

async function encounterRow(encounterId) {
  const { data, error } = await admin
    .from('mass_encounters')
    .select('status, locked_count, total_hp')
    .eq('id', encounterId)
    .maybeSingle()
  if (error) fail('could not read encounter', { error })
  return data
}

const started = Date.now()
let encounterId = null
let failed = null
try {
  const first = await admin.rpc('mass_join', {
    p_user_id: users[0],
    p_enemy_id: 'ENM-0006',
    p_username: 'Load0',
    p_player_base_hp: 1000,
  })
  if (first.error) fail('join failed', { error: first.error })
  encounterId = first.data.encounterId
  const joins = await Promise.all(
    users.slice(1).map((id, i) =>
      admin.rpc('mass_join', {
        p_user_id: id,
        p_enemy_id: 'ENM-0006',
        p_username: `Load${i + 1}`,
        p_player_base_hp: 1000,
      }),
    ),
  )
  const joinErrors = joins.filter((row) => row.error)
  if (joinErrors.length) {
    fail('join errors', { count: joinErrors.length, error: joinErrors[0].error })
  }

  const forced = await admin
    .from('mass_encounters')
    .update({ countdown_ends_at: new Date(Date.now() - 1000).toISOString() })
    .eq('id', encounterId)
  if (forced.error) fail('could not expire countdown', { error: forced.error })

  const { error: lockError, data: locked } = await admin.rpc('mass_lock_if_due', {
    p_encounter_id: encounterId,
    p_solo_hp: SOLO_HP,
    p_player_base_hp_scale: null,
  })
  if (lockError) fail('lock failed', { error: lockError })
  assert(locked?.status === 'fighting', 'expected fighting after lock', { locked })
  const lockedCount = Number(locked?.lockedCount ?? 0)
  assert(lockedCount === PLAYERS, 'locked_count is not 100', {
    lockedCount,
    locked,
  })

  const tickStarted = Date.now()
  const ticks = await Promise.all(
    users.map((id, i) =>
      admin.rpc('mass_record_damage', {
        p_user_id: id,
        p_encounter_id: encounterId,
        p_damage: DAMAGE_EACH,
        p_round_started_at: `round-${i}`,
      }),
    ),
  )
  const tickMs = Date.now() - tickStarted
  const tickErrors = ticks.filter((row) => row.error)
  const added = ticks.reduce((sum, row) => sum + Number(row.data?.damageAdded ?? 0), 0)
  const recordedSum = await damageSum(encounterId)
  assert(tickErrors.length === 0, 'tick errors', {
    tickErrors: tickErrors.length,
    error: tickErrors[0]?.error,
  })
  assert(added === EXPECTED_CONCURRENT_DAMAGE, 'summed recorded damage does not equal expected total', {
    damageAdded: added,
    expected: EXPECTED_CONCURRENT_DAMAGE,
    recordedSum,
  })
  assert(recordedSum === EXPECTED_CONCURRENT_DAMAGE, 'participant damage_dealt sum does not equal expected total', {
    recordedSum,
    expected: EXPECTED_CONCURRENT_DAMAGE,
    damageAdded: added,
  })

  const remainingAfterWave = Number(ticks[0]?.data?.remainingHp ?? NaN)
  const totalHp = Number(locked?.totalHp ?? NaN)
  if (remainingAfterWave > 0) {
    const kill = await admin.rpc('mass_record_damage', {
      p_user_id: users[0],
      p_encounter_id: encounterId,
      p_damage: remainingAfterWave,
      p_round_started_at: 'kill',
    })
    if (kill.error) fail('kill tick failed', { error: kill.error })
    assert(Number(kill.data?.remainingHp ?? NaN) === 0, 'boss still alive after kill tick', {
      remainingHp: kill.data?.remainingHp,
      damageAdded: kill.data?.damageAdded,
    })
  }

  const settleStarted = Date.now()
  const settles = await Promise.all(
    users.map(() => admin.rpc('mass_settle', { p_encounter_id: encounterId })),
  )
  const settleMs = Date.now() - settleStarted
  const settleErrors = settles.filter((row) => row.error)
  assert(settleErrors.length === 0, 'settle errors', {
    settleErrors: settleErrors.length,
    error: settleErrors[0]?.error,
  })
  const firstSettles = settles.filter((row) => row.data?.alreadySettled === false).length
  const alreadySettled = settles.filter((row) => row.data?.alreadySettled === true).length
  assert(firstSettles === 1, 'boss did not settle exactly once', {
    firstSettles,
    alreadySettled,
    statuses: [...new Set(settles.map((row) => row.data?.status))],
  })
  const row = await encounterRow(encounterId)
  assert(row?.status === 'settled', 'encounter status is not settled', { row })
  assert(Number(row?.locked_count) === PLAYERS, 'locked_count is not 100 after settle', {
    lockedCount: row?.locked_count,
  })

  const report = {
    ok: true,
    players: PLAYERS,
    lockedCount,
    expectedDamage: EXPECTED_CONCURRENT_DAMAGE,
    damageAdded: added,
    recordedSum,
    totalHp,
    remainingAfterWave,
    firstSettles,
    alreadySettled,
    tickMs,
    settleMs,
    totalMs: Date.now() - started,
  }
  console.log(JSON.stringify(report, null, 2))
} catch (error) {
  failed = error
  if (error?.payload) console.error(JSON.stringify(error.payload, null, 2))
  else console.error(error)
} finally {
  if (encounterId) {
    await admin.from('mass_encounters').delete().eq('id', encounterId)
  }
}
if (failed) process.exit(1)
