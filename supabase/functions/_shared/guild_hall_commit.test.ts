import { describe, expect, it } from 'vitest'

import {
  commitGuildHallFromPlayerSaves,
  goldTakenFromPlayerSaves,
} from '../../../src/game/guild/commit.ts'
import { emptyGuildHallState } from '../../../src/game/guild/economy.ts'
import { GUILD_HALL_GOLD_CAP, GUILD_HALL_TIER_BUILD } from '../../../src/game/guild/hall.ts'

/**
 * The game function's hall write. A modified client that stuffed
 * gold_contributed / completed_tiers into the hall payload must not move the
 * hosted hall; only gold and stacks that left the hosted save count.
 */
describe('game function hall commit (forged payload)', () => {
  it('rejects a forged 1M gold_contributed when the save still has its gold', () => {
    expect(goldTakenFromPlayerSaves(80_000, 80_000)).toBe(0)
    const committed = commitGuildHallFromPlayerSaves({
      previousGold: 80_000,
      nextGold: 80_000,
      previousInventory: [],
      nextInventory: [],
      hall: emptyGuildHallState(),
      userId: 'forged-client',
      proposed: {
        goldContributed: GUILD_HALL_GOLD_CAP,
        completedTiers: [GUILD_HALL_TIER_BUILD],
      },
    })
    expect(committed.goldTaken).toBe(0)
    expect(committed.hall.goldContributed).toBe(0)
    expect(committed.hall.completedTiers).toEqual([])
  })

  it('still credits a real chip-in of 250 gold against a payload that claims the cap', () => {
    const committed = commitGuildHallFromPlayerSaves({
      previousGold: 1_000,
      nextGold: 750,
      previousInventory: [],
      nextInventory: [],
      hall: emptyGuildHallState(),
      userId: 'forged-client',
      proposed: { goldContributed: GUILD_HALL_GOLD_CAP },
    })
    expect(committed.goldTaken).toBe(250)
    expect(committed.hall.goldContributed).toBe(250)
  })
})
