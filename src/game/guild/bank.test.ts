import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import {
  depositToGuildBank,
  emptyGuildBank,
  GUILD_BANK_SECTION_MAIN,
  GUILD_BANK_SECTION_UP_FOR_GRABS,
  moveGuildBankToUpForGrabs,
  takeGuildBankUpForGrabs,
  withdrawFromGuildBank,
  type GuildBankState,
} from './bank'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('guild bank', () => {
  const { launch } = prepareDatabase(rawDatabase)

  it('stacks a deposit in main and lets one taker empty Up for grabs', () => {
    const save = {
      ...createNewSave(launch, 1),
      inventory: [{ itemId: 'ITEM-0015', quantity: 5 }],
    }
    const deposited = depositToGuildBank(emptyGuildBank(), save, 0, 5, () => 'gb-1')
    expect(deposited.ok).toBe(true)
    if (!deposited.ok) return
    expect(deposited.bank.items).toEqual([
      { id: 'gb-1', itemId: 'ITEM-0015', quantity: 5, section: GUILD_BANK_SECTION_MAIN },
    ])
    expect(deposited.save.inventory).toEqual([])

    const moved = moveGuildBankToUpForGrabs(
      deposited.bank,
      deposited.save,
      'ITEM-0015',
      5,
      null,
      () => 'gb-2',
    )
    expect(moved.ok).toBe(true)
    if (!moved.ok) return
    expect(moved.bank.items[0].section).toBe(GUILD_BANK_SECTION_UP_FOR_GRABS)

    const taken = takeGuildBankUpForGrabs(moved.bank, moved.save, 'ITEM-0015', 5)
    expect(taken.ok).toBe(true)
    if (!taken.ok) return
    expect(taken.bank.items).toEqual([])
    expect(taken.save.inventory).toEqual([{ itemId: 'ITEM-0015', quantity: 5 }])

    const missed = takeGuildBankUpForGrabs(taken.bank, taken.save, 'ITEM-0015', 5)
    expect(missed.ok).toBe(false)
  })

  it('withdraws from main without touching Up for grabs', () => {
    const save = createNewSave(launch, 1)
    const bank: GuildBankState = {
      items: [
        { id: 'a', itemId: 'ITEM-0015', quantity: 2, section: GUILD_BANK_SECTION_MAIN },
        {
          id: 'b',
          itemId: 'ITEM-0015',
          quantity: 9,
          section: GUILD_BANK_SECTION_UP_FOR_GRABS,
        },
      ],
    }
    const taken = withdrawFromGuildBank(bank, save, 'ITEM-0015', 2)
    expect(taken.ok).toBe(true)
    if (!taken.ok) return
    expect(taken.bank.items).toEqual([
      { id: 'b', itemId: 'ITEM-0015', quantity: 9, section: GUILD_BANK_SECTION_UP_FOR_GRABS },
    ])
  })
})
