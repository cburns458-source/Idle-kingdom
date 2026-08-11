import type { GameDatabase } from '../data/types'
import { inventoryCount } from '../production/recipes'
import { knowsRecipe } from '../recipes/knowledge'
import type { PlayerSave } from '../save/types'
import type { QuestRow } from './quests'
import type { QuestObjectiveKind, StructuredQuestObjectives } from './types'

function parseIdQtyList(raw: string): Array<{ targetId: string; quantity: number }> {
  const out: Array<{ targetId: string; quantity: number }> = []
  for (const part of raw.split(',')) {
    const m = part.trim().match(/^([A-Z]+-\d+)\s*x\s*(\d+)$/i)
    if (!m) continue
    out.push({ targetId: m[1].toUpperCase(), quantity: Number(m[2]) })
  }
  return out
}

function parseIdList(raw: string): string[] {
  return raw
    .split(',')
    .map((part) => part.trim().toUpperCase())
    .filter((id) => /^[A-Z]+-\d+$/.test(id))
}

export function normalizeObjectiveKind(raw: string | null | undefined): QuestObjectiveKind {
  const value = (raw ?? '').toLowerCase()
  if (value.includes('defeat') || value.includes('kill') || value.includes('combat')) {
    return 'defeat'
  }
  if (value.includes('process') || value.includes('craft') || value.includes('cook')) {
    return 'process'
  }
  if (value.includes('learn') || value.includes('recipe')) return 'learn_recipe'
  if (value.includes('restore') || value.includes('facility')) return 'restore_facility'
  if (value.includes('portal')) return 'construct_portal'
  if (value.includes('travel') || value.includes('mount') || value.includes('route')) {
    return 'unlock_travel'
  }
  if (value.includes('guild')) return 'guild_collab'
  return 'gather_deliver'
}

/**
 * Parse structured objectives from quest fields + Notes.
 * Notes extensions (semicolon-separated):
 *   Deliver: ITEM-x xN, ...
 *   Defeat: ENM-x xN, ...
 *   Process: RCP-x xN, ...
 *   LearnRecipe: RCP-x, ...
 *   GoldCost: N
 *   UnlockLocation: LOC-x
 *   RewardRecipe: RCP-x
 *   RewardProjectNpc: NPC-x
 */
export function parseStructuredObjectives(quest: QuestRow): StructuredQuestObjectives {
  const notes = quest.Notes ?? ''
  const kind = normalizeObjectiveKind(quest['Objective Type'])
  const delivers: StructuredQuestObjectives['delivers'] = []
  const processTargets: StructuredQuestObjectives['processTargets'] = []
  const defeatTargets: StructuredQuestObjectives['defeatTargets'] = []
  let learnRecipeIds: string[] = []
  let restoreFacilityIds: string[] = []
  let constructPortalIds: string[] = []
  let unlockTravelIds: string[] = []
  let goldCost = 0
  const unlockLocationIds: string[] = []
  let rewardRecipeIds: string[] = []
  let rewardProjectNpcIds: string[] = []

  const deliverMatch = notes.match(/Deliver:\s*([^;]+)/i)
  if (deliverMatch) delivers.push(...parseIdQtyList(deliverMatch[1]))

  const defeatMatch = notes.match(/Defeat:\s*([^;]+)/i)
  if (defeatMatch) defeatTargets.push(...parseIdQtyList(defeatMatch[1]))

  const processMatch = notes.match(/Process:\s*([^;]+)/i)
  if (processMatch) processTargets.push(...parseIdQtyList(processMatch[1]))

  const learnMatch = notes.match(/LearnRecipe:\s*([^;]+)/i)
  if (learnMatch) learnRecipeIds = parseIdList(learnMatch[1])

  const restoreMatch = notes.match(/RestoreFacility:\s*([^;]+)/i)
  if (restoreMatch) restoreFacilityIds = parseIdList(restoreMatch[1])

  const portalMatch = notes.match(/ConstructPortal:\s*([^;]+)/i)
  if (portalMatch) constructPortalIds = parseIdList(portalMatch[1])

  const travelMatch = notes.match(/UnlockTravel:\s*([^;]+)/i)
  if (travelMatch) unlockTravelIds = parseIdList(travelMatch[1])

  const goldMatch = notes.match(/GoldCost:\s*(\d+)/i)
  if (goldMatch) goldCost = Number(goldMatch[1])

  const unlockMatch = notes.match(/UnlockLocation(?:s)?:\s*([^;]+)/i)
  if (unlockMatch) unlockLocationIds.push(...parseIdList(unlockMatch[1]))

  const rewardRecipeMatch = notes.match(/RewardRecipe:\s*([^;]+)/i)
  if (rewardRecipeMatch) rewardRecipeIds = parseIdList(rewardRecipeMatch[1])

  const rewardNpcMatch = notes.match(/RewardProjectNpc:\s*([^;]+)/i)
  if (rewardNpcMatch) rewardProjectNpcIds = parseIdList(rewardNpcMatch[1])

  if (delivers.length === 0 && kind === 'gather_deliver') {
    const targetId = quest['Objective Target ID']
    const required = quest['Required Quantity']
    if (targetId && typeof required === 'number' && required > 0) {
      delivers.push({ targetId, quantity: required })
    }
  }

  if (defeatTargets.length === 0 && kind === 'defeat') {
    const targetId = quest['Objective Target ID']
    const required = quest['Required Quantity']
    if (targetId && typeof required === 'number' && required > 0) {
      defeatTargets.push({ targetId, quantity: required })
    }
  }

  if (processTargets.length === 0 && kind === 'process') {
    const targetId = quest['Objective Target ID']
    const required = quest['Required Quantity']
    if (targetId && typeof required === 'number' && required > 0) {
      processTargets.push({ targetId, quantity: required })
    }
  }

  return {
    kind,
    delivers,
    processTargets,
    defeatTargets,
    learnRecipeIds,
    restoreFacilityIds,
    constructPortalIds,
    unlockTravelIds,
    goldCost,
    unlockLocationIds,
    rewardRecipeIds,
    rewardProjectNpcIds,
  }
}

/** @deprecated Prefer parseStructuredObjectives */
export function parseQuestObjectives(quest: QuestRow) {
  const structured = parseStructuredObjectives(quest)
  return {
    delivers: structured.delivers.map((row) => ({
      itemId: row.targetId,
      quantity: row.quantity,
    })),
    goldCost: structured.goldCost,
    unlockLocationIds: structured.unlockLocationIds,
  }
}

export interface QuestProgressLine {
  key: string
  label: string
  current: number
  required: number
}

export function questObjectiveProgress(
  db: GameDatabase,
  save: PlayerSave,
  quest: QuestRow,
): {
  lines: Array<{ itemId: string; name: string; owned: number; required: number }>
  progressLines: QuestProgressLine[]
  goldOwned: number
  goldRequired: number
  ready: boolean
} {
  const structured = parseStructuredObjectives(quest)
  const progress = save.quests.find((row) => row.questId === quest['Quest ID'])
  const counters = progress?.counters ?? {}

  const deliverLines = structured.delivers.map((line) => {
    const name =
      db.Items.find((item) => item['Item ID'] === line.targetId)?.['Display Name'] ??
      line.targetId
    return {
      itemId: line.targetId,
      name,
      owned: inventoryCount(save, line.targetId),
      required: line.quantity,
    }
  })

  const progressLines: QuestProgressLine[] = [
    ...deliverLines.map((line) => ({
      key: `deliver:${line.itemId}`,
      label: `Deliver ${line.name}`,
      current: line.owned,
      required: line.required,
    })),
    ...structured.defeatTargets.map((line) => {
      const name =
        db.Enemies.find((enemy) => enemy['Enemy ID'] === line.targetId)?.['Display Name'] ??
        line.targetId
      return {
        key: `defeat:${line.targetId}`,
        label: `Defeat ${name}`,
        current: Number(counters[`defeat:${line.targetId}`] ?? 0),
        required: line.quantity,
      }
    }),
    ...structured.processTargets.map((line) => {
      const name =
        db.Recipes.find((recipe) => recipe['Recipe ID'] === line.targetId)?.['Display Name'] ??
        db.Projects.find((project) => project['Project ID'] === line.targetId)?.[
          'Display Name'
        ] ??
        line.targetId
      return {
        key: `process:${line.targetId}`,
        label: `Craft ${name}`,
        current: Number(counters[`process:${line.targetId}`] ?? 0),
        required: line.quantity,
      }
    }),
    ...structured.learnRecipeIds.map((recipeId) => {
      const name =
        db.Recipes.find((recipe) => recipe['Recipe ID'] === recipeId)?.['Display Name'] ??
        recipeId
      const known = knowsRecipe(save, db, recipeId) ? 1 : 0
      return {
        key: `learn:${recipeId}`,
        label: `Learn ${name}`,
        current: known,
        required: 1,
      }
    }),
  ]

  if (structured.goldCost > 0) {
    progressLines.push({
      key: 'gold',
      label: 'Gold',
      current: save.gold,
      required: structured.goldCost,
    })
  }

  const counterReady = progressLines.every((line) => line.current >= line.required)
  const hasWork =
    progressLines.length > 0 ||
    structured.goldCost > 0 ||
    structured.restoreFacilityIds.length > 0 ||
    structured.constructPortalIds.length > 0 ||
    structured.unlockTravelIds.length > 0

  // Guild collab / restore / portal stay incomplete until those systems land.
  const deferredIncomplete =
    structured.kind === 'guild_collab' ||
    structured.restoreFacilityIds.length > 0 ||
    structured.constructPortalIds.length > 0

  return {
    lines: deliverLines,
    progressLines,
    goldOwned: save.gold,
    goldRequired: structured.goldCost,
    ready: hasWork && counterReady && !deferredIncomplete,
  }
}
