// The developer_accounts gate the game function puts in front of /abandonquest
// and every other dev_command.

import { describe, expect, it } from 'vitest'

import { gateDevCommand, NOT_A_DEVELOPER, type DevAuditRow, type DevGateDeps } from './dev_gate.ts'

const DEVELOPER = 'user-dev'
const PLAYER = 'user-player'

function fakeDeps(options: { lookupError?: string } = {}): DevGateDeps & { audits: DevAuditRow[]; lookups: string[] } {
  const audits: DevAuditRow[] = []
  const lookups: string[] = []
  return {
    audits,
    lookups,
    lookupDeveloper: async (userId) => {
      lookups.push(userId)
      if (options.lookupError) return { developer: false, error: options.lookupError }
      return { developer: userId === DEVELOPER, error: null }
    },
    audit: async (row) => {
      audits.push(row)
    },
  }
}

describe('dev_command developer gate', () => {
  it('refuses the abandon cheat for a non-developer with 403 and logs the attempt', async () => {
    const deps = fakeDeps()
    const decision = await gateDevCommand(deps, PLAYER, 'abandonquest', ['QST-0001', 'confirm'])
    expect(decision).toEqual({ ok: false, status: 403, error: NOT_A_DEVELOPER })
    expect(deps.lookups).toEqual([PLAYER])
    expect(deps.audits).toEqual([
      {
        user_id: PLAYER,
        command: 'abandonquest',
        args: { tokens: ['QST-0001', 'confirm'] },
        ok: false,
        reason: NOT_A_DEVELOPER,
      },
    ])
  })

  it('lets a developer through without an audit row from the gate', async () => {
    const deps = fakeDeps()
    expect(await gateDevCommand(deps, DEVELOPER, 'abandonquest', ['QST-0001', 'confirm'])).toEqual({ ok: true })
    expect(deps.audits).toEqual([])
  })

  it('fails closed with 500 when the allowlist cannot be read', async () => {
    const deps = fakeDeps({ lookupError: 'connection reset' })
    expect(await gateDevCommand(deps, DEVELOPER, 'abandonquest', ['QST-0001', 'confirm'])).toEqual({
      ok: false,
      status: 500,
      error: 'connection reset',
    })
    expect(deps.audits).toEqual([])
  })
})
