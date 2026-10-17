#!/usr/bin/env node
// 100 concurrent damage writes against the TEST project. Gate for SOC-04:
// if this fails, stop and do not build lobbies.
import { createClient } from '@supabase/supabase-js'

const url = process.env.SUPABASE_TEST_URL
const key = process.env.SUPABASE_TEST_SERVICE_ROLE_KEY
if (!url || !key) {
  console.error('Need SUPABASE_TEST_URL and SUPABASE_TEST_SERVICE_ROLE_KEY')
  process.exit(2)
}

const admin = createClient(url, key, { auth: { persistSession: false } })
const users = Array.from({ length: 100 }, (_, i) =>
  `00000000-0000-4000-8000-${String(i + 1).padStart(12, '0')}`,
)

const started = Date.now()
const first = await admin.rpc('mass_join', {
  p_user_id: users[0],
  p_enemy_id: 'ENM-0006',
  p_username: 'Load0',
  p_player_base_hp: 1000,
})
if (first.error) {
  console.error('join failed', first.error)
  process.exit(1)
}
const encounterId = first.data.encounterId
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
  console.error('join errors', joinErrors.length, joinErrors[0].error)
  process.exit(1)
}

const forced = await admin
  .from('mass_encounters')
  .update({ countdown_ends_at: new Date(Date.now() - 1000).toISOString() })
  .eq('id', encounterId)
if (forced.error) {
  console.error('could not expire countdown', forced.error)
  process.exit(1)
}
const { error: lockError, data: locked } = await admin.rpc('mass_lock_if_due', {
  p_encounter_id: encounterId,
  p_solo_hp: 1000,
  p_player_base_hp_scale: null,
})
if (lockError) {
  console.error('lock failed', lockError)
  process.exit(1)
}
if (locked?.status !== 'fighting') {
  console.error('expected fighting after lock', locked)
  process.exit(1)
}

const tickStarted = Date.now()
const ticks = await Promise.all(
  users.map((id, i) =>
    admin.rpc('mass_record_damage', {
      p_user_id: id,
      p_encounter_id: encounterId,
      p_damage: 1,
      p_round_started_at: `round-${i}`,
    }),
  ),
)
const tickMs = Date.now() - tickStarted
const tickErrors = ticks.filter((row) => row.error)
const added = ticks.reduce((sum, row) => sum + Number(row.data?.damageAdded ?? 0), 0)
console.log(
  JSON.stringify(
    {
      ok: tickErrors.length === 0 && added === 100,
      players: 100,
      tickMs,
      totalMs: Date.now() - started,
      tickErrors: tickErrors.length,
      damageAdded: added,
      remainingHp: ticks[0]?.data?.remainingHp ?? null,
    },
    null,
    2,
  ),
)
await admin.from('mass_encounters').delete().eq('id', encounterId)
if (tickErrors.length || added !== 100) process.exit(1)
