import { describe, expect, it } from 'vitest'
import {
  MASS_CLAIM_PAYOUT_RPC,
  persistMassClaim,
  type MassClaimRpcAdmin,
} from '../../../supabase/functions/_shared/mass_claim_edge.ts'

const USER_ID = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'
const ENCOUNTER_ID = '11111111-1111-1111-1111-111111111111'
const NOW_MS = Date.parse('2026-10-17T00:00:00.000Z')
const LOOTED = { gold: 75, massEncounterId: null }
const BASE = { gold: 10, massEncounterId: 'pending' }

function memoryClaimAdmin(startVersion = 1, startPayload: unknown = BASE): MassClaimRpcAdmin & {
  claimed: boolean
  version: number
  payload: unknown
  calls: { fn: string; args: Record<string, unknown> }[]
} {
  const state = {
    claimed: false,
    version: startVersion,
    payload: startPayload,
    calls: [] as { fn: string; args: Record<string, unknown> }[],
    async rpc(fn: string, args: Record<string, unknown>) {
      state.calls.push({ fn, args })
      if (fn !== MASS_CLAIM_PAYOUT_RPC) {
        return { data: null, error: { message: `unexpected ${fn}` } }
      }
      if (args.p_expected_version !== state.version) {
        return {
          data: { ok: false, conflict: true, reason: 'Save version conflict. Sync and retry.' },
          error: null,
        }
      }
      if (state.claimed) {
        return {
          data: {
            ok: true,
            alreadyClaimed: true,
            eligible: true,
            version: state.version,
            payload: state.payload,
          },
          error: null,
        }
      }
      state.claimed = true
      state.version += 1
      state.payload = args.p_payload
      return {
        data: {
          ok: true,
          alreadyClaimed: false,
          eligible: true,
          version: state.version,
          payload: state.payload,
        },
        error: null,
      }
    },
  }
  return state
}

describe('mass claim persist', () => {
  it('retries after a failed save write and grants exactly once', async () => {
    const admin = memoryClaimAdmin(3, BASE)
    const args = {
      admin,
      userId: USER_ID,
      encounterId: ENCOUNTER_ID,
      payload: LOOTED,
      rngState: 1,
      nowMs: NOW_MS,
    }

    const failed = await persistMassClaim({ ...args, expectedVersion: 1 })
    expect(failed).toEqual({
      kind: 'failed',
      error: 'Save version conflict. Sync and retry.',
      status: 409,
      conflict: true,
    })
    expect(admin.claimed).toBe(false)
    expect(admin.version).toBe(3)
    expect(admin.payload).toEqual(BASE)

    const retry = await persistMassClaim({ ...args, expectedVersion: 3 })
    expect(retry.kind).toBe('ok')
    if (retry.kind !== 'ok') return
    expect(retry.alreadyClaimed).toBe(false)
    expect(retry.version).toBe(4)
    expect(retry.payload).toEqual(LOOTED)
    expect(admin.claimed).toBe(true)

    const second = await persistMassClaim({ ...args, expectedVersion: 4 })
    expect(second.kind).toBe('ok')
    if (second.kind !== 'ok') return
    expect(second.alreadyClaimed).toBe(true)
    expect(second.payload).toEqual(LOOTED)
    expect(admin.payload).toEqual(LOOTED)
    expect(admin.version).toBe(4)
    expect(admin.calls).toHaveLength(3)
    expect(admin.calls.every((call) => call.fn === MASS_CLAIM_PAYOUT_RPC)).toBe(true)
  })
})
