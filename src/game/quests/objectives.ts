import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { inventoryCount } from '../production/recipes'
import type { QuestRow } from './quests'

export interface QuestDeliverItem {
  itemId: string
  quantity: number
}

export interface ParsedQuestObjectives {
  delivers: QuestDeliverItem[]
  goldCost: number
  unlockLocationIds: string[]
}

/**
 * Parse multi-deliver / gold / unlock metadata from quest Notes.
 * Format example:
 *   Deliver: ITEM-0038 x5, ITEM-0031 x5; GoldCost: 1000; UnlockLocation: LOC-0026
 * Falls back to Objective Target ID + Required Quantity for classic single-item quests.
 */
export function parseQuestObjectives(quest: QuestRow): ParsedQuestObjectives {
  const notes = quest.Notes ?? ''
  const delivers: QuestDeliverItem[] = []
  let goldCost = 0
  const unlockLocationIds: string[] = []

  const deliverMatch = notes.match(/Deliver:\s*([^;]+)/i)
  if (deliverMatch) {
    for (const part of deliverMatch[1].split(',')) {
      const m = part.trim().match(/^(ITEM-\d+)\s*x\s*(\d+)$/i)
      if (!m) continue
      delivers.push({ itemId: m[1].toUpperCase(), quantity: Number(m[2]) })
    }
  }

  const goldMatch = notes.match(/GoldCost:\s*(\d+)/i)
  if (goldMatch) goldCost = Number(goldMatch[1])

  const unlockMatch = notes.match(/UnlockLocation(?:s)?:\s*([^;]+)/i)
  if (unlockMatch) {
    for (const part of unlockMatch[1].split(',')) {
      const id = part.trim().toUpperCase()
      if (id.startsWith('LOC-')) unlockLocationIds.push(id)
    }
  }

  if (delivers.length === 0) {
    const targetId = quest['Objective Target ID']
    const required = quest['Required Quantity']
    if (targetId && typeof required === 'number' && required > 0) {
      delivers.push({ itemId: targetId, quantity: required })
    }
  }

  return { delivers, goldCost, unlockLocationIds }
}

export function questObjectiveProgress(
  db: GameDatabase,
  save: PlayerSave,
  quest: QuestRow,
): {
  lines: Array<{ itemId: string; name: string; owned: number; required: number }>
  goldOwned: number
  goldRequired: number
  ready: boolean
} {
  const parsed = parseQuestObjectives(quest)
  const lines = parsed.delivers.map((line) => {
    const name =
      db.Items.find((item) => item['Item ID'] === line.itemId)?.['Display Name'] ?? line.itemId
    return {
      itemId: line.itemId,
      name,
      owned: inventoryCount(save, line.itemId),
      required: line.quantity,
    }
  })
  const itemsReady = lines.every((line) => line.owned >= line.required)
  const goldReady = save.gold >= parsed.goldCost
  return {
    lines,
    goldOwned: save.gold,
    goldRequired: parsed.goldCost,
    ready: itemsReady && goldReady && (lines.length > 0 || parsed.goldCost > 0),
  }
}
