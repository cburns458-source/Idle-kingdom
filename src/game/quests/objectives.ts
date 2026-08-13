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

function parseTokenList(raw: string): string[] {
  return raw
    .split(',')
    .map((part) => part.trim().toLowerCase())
    .filter((part) => part.length > 0)
}

function noteField(notes: string, pattern: string): string | undefined {
  return notes.match(new RegExp(pattern, 'i'))?.[1]
}

function singleId(raw: string | undefined): string | null {
  if (!raw) return null
  const ids = parseIdList(raw)
  return ids[0] ?? null
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
 *   Talk: NPC-x, ...
 *   Visit: LOC-x, ...
 *   Inspect: bazaar, bounties, processing
 *   GoldCost: N
 *   AcceptGold: N
 *   RewardGold: N
 *   BribeGold: N
 *   BranchSkillXp: N
 *   ChoiceNpc: NPC-x
 *   TurnInNpc: NPC-x
 *   AutoStart: LOC-x
 *   UnlockLocation: LOC-x
 *   RewardRecipe: RCP-x
 *   RewardProjectNpc: NPC-x
 *   RewardCosmetic: COS-x
 */
export function parseStructuredObjectives(quest: QuestRow): StructuredQuestObjectives {
  const notes = quest.Notes ?? ''
  const kind = normalizeObjectiveKind(quest['Objective Type'])
  const delivers: StructuredQuestObjectives['delivers'] = []
  const processTargets: StructuredQuestObjectives['processTargets'] = []
  const defeatTargets: StructuredQuestObjectives['defeatTargets'] = []

  const deliverMatch = noteField(notes, String.raw`Deliver:\s*([^;]+)`)
  if (deliverMatch) delivers.push(...parseIdQtyList(deliverMatch))

  const defeatMatch = noteField(notes, String.raw`Defeat:\s*([^;]+)`)
  if (defeatMatch) defeatTargets.push(...parseIdQtyList(defeatMatch))

  const processMatch = noteField(notes, String.raw`Process:\s*([^;]+)`)
  if (processMatch) processTargets.push(...parseIdQtyList(processMatch))

  const learnMatch = noteField(notes, String.raw`LearnRecipe:\s*([^;]+)`)
  const restoreMatch = noteField(notes, String.raw`RestoreFacility:\s*([^;]+)`)
  const portalMatch = noteField(notes, String.raw`ConstructPortal:\s*([^;]+)`)
  const travelMatch = noteField(notes, String.raw`UnlockTravel:\s*([^;]+)`)
  const talkMatch = noteField(notes, String.raw`Talk:\s*([^;]+)`)
  const visitMatch = noteField(notes, String.raw`Visit:\s*([^;]+)`)
  const inspectMatch = noteField(notes, String.raw`Inspect:\s*([^;]+)`)
  const goldMatch = noteField(notes, String.raw`GoldCost:\s*(\d+)`)
  const acceptGoldMatch = noteField(notes, String.raw`AcceptGold:\s*(\d+)`)
  const rewardGoldMatch = noteField(notes, String.raw`RewardGold:\s*(\d+)`)
  const bribeGoldMatch = noteField(notes, String.raw`BribeGold:\s*(\d+)`)
  const branchXpMatch = noteField(notes, String.raw`BranchSkillXp:\s*(\d+)`)
  const choiceNpcMatch = noteField(notes, String.raw`ChoiceNpc:\s*([^;]+)`)
  const turnInMatch = noteField(notes, String.raw`TurnInNpc:\s*([^;]+)`)
  const autoStartMatch = noteField(notes, String.raw`AutoStart:\s*([^;]+)`)
  const unlockMatch = noteField(notes, String.raw`UnlockLocation(?:s)?:\s*([^;]+)`)
  const rewardRecipeMatch = noteField(notes, String.raw`RewardRecipe:\s*([^;]+)`)
  const rewardNpcMatch = noteField(notes, String.raw`RewardProjectNpc:\s*([^;]+)`)
  const rewardCosmeticMatch = noteField(notes, String.raw`RewardCosmetic:\s*([^;]+)`)

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
    learnRecipeIds: learnMatch ? parseIdList(learnMatch) : [],
    restoreFacilityIds: restoreMatch ? parseIdList(restoreMatch) : [],
    constructPortalIds: portalMatch ? parseIdList(portalMatch) : [],
    unlockTravelIds: travelMatch ? parseIdList(travelMatch) : [],
    talkNpcIds: talkMatch ? parseIdList(talkMatch) : [],
    visitLocationIds: visitMatch ? parseIdList(visitMatch) : [],
    inspectIds: inspectMatch ? parseTokenList(inspectMatch) : [],
    goldCost: goldMatch ? Number(goldMatch) : 0,
    acceptGoldCost: acceptGoldMatch ? Number(acceptGoldMatch) : 0,
    rewardGold: rewardGoldMatch ? Number(rewardGoldMatch) : 0,
    bribeGold: bribeGoldMatch ? Number(bribeGoldMatch) : 0,
    branchSkillXp: branchXpMatch ? Number(branchXpMatch) : 0,
    choiceNpcId: singleId(choiceNpcMatch),
    turnInNpcId: singleId(turnInMatch),
    autoStartLocationId: singleId(autoStartMatch),
    unlockLocationIds: unlockMatch ? parseIdList(unlockMatch) : [],
    rewardRecipeIds: rewardRecipeMatch ? parseIdList(rewardRecipeMatch) : [],
    rewardProjectNpcIds: rewardNpcMatch ? parseIdList(rewardNpcMatch) : [],
    rewardCosmeticIds: rewardCosmeticMatch ? parseIdList(rewardCosmeticMatch) : [],
  }
}

export interface QuestProgressLine {
  key: string
  label: string
  current: number
  required: number
}

function npcDisplayName(db: GameDatabase, npcId: string): string {
  return db.NPCs.find((row) => row['NPC ID'] === npcId)?.['Display Name'] ?? npcId
}

function locationDisplayName(db: GameDatabase, locationId: string): string {
  return (
    db.Locations.find((row) => row['Location ID'] === locationId)?.['Display Name'] ?? locationId
  )
}

function inspectLabel(inspectId: string): string {
  if (inspectId === 'bazaar') return 'Inspect the Grand Bazaar'
  if (inspectId === 'bounties') return 'Inspect the Bounty Board'
  if (inspectId === 'processing') return 'Use a Processing District station'
  return `Inspect ${inspectId}`
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
    ...structured.talkNpcIds.map((npcId) => ({
      key: `talk:${npcId}`,
      label: `Talk to ${npcDisplayName(db, npcId)}`,
      current: Number(counters[`talk:${npcId}`] ?? 0),
      required: 1,
    })),
    ...structured.visitLocationIds.map((locationId) => ({
      key: `visit:${locationId}`,
      label: `Visit ${locationDisplayName(db, locationId)}`,
      current: Number(counters[`visit:${locationId}`] ?? 0),
      required: 1,
    })),
    ...structured.inspectIds.map((inspectId) => ({
      key: `inspect:${inspectId}`,
      label: inspectLabel(inspectId),
      current: Number(counters[`inspect:${inspectId}`] ?? 0),
      required: 1,
    })),
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
