import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { requestBlessing } from '../world/blessing'
import { currentHpAfterMaxChange, withRecalculatedVitals } from './vitals'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('blessing surplus', () => {
  it('keeps the extra HP when max changes', () => {
    expect(currentHpAfterMaxChange(5500, 5000, 4000)).toBe(4500)
    expect(currentHpAfterMaxChange(5250, 5000, 4000)).toBe(4250)
    expect(currentHpAfterMaxChange(4900, 5000, 4000)).toBe(4000)
    expect(currentHpAfterMaxChange(5500, 5000, 6000)).toBe(6500)
  })

  it('blesses to 110% and does not stack another 10%', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0036',
      currentHp: 250,
      maxHp: 5000,
    }
    const first = requestBlessing(launch, { ...save, maxHp: 5000 }, 0)
    expect(first.ok).toBe(true)
    if (!first.ok) return
    expect(first.save.currentHp).toBe(first.save.maxHp + Math.floor(first.save.maxHp * 0.1))

    const again = requestBlessing(launch, first.save, 0)
    expect(again.ok).toBe(true)
    if (!again.ok) return
    expect(again.alreadyFull).toBe(true)
    expect(again.save.currentHp).toBe(first.save.currentHp)
  })

  it('preserves surplus through a max-HP recalculation', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const maxHp = save.maxHp
    const blessed = { ...save, currentHp: maxHp + Math.floor(maxHp * 0.1) }
    const next = withRecalculatedVitals(launch, blessed)
    expect(next.maxHp).toBe(maxHp)
    expect(next.currentHp).toBe(blessed.currentHp)
  })
})
