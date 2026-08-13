import { asAchievementRows } from '../achievements/progress'
import { CRITTER_DEFS, collectionCount } from '../critters/critters'
import type { GameDatabase } from '../data/types'
import { questObjectiveProgress } from '../quests/objectives'
import { asQuestRows, getQuestProgress, questStatusLabel } from '../quests/quests'
import { listRecipeBookEntries } from '../recipes/knowledge'
import type { PlayerSave } from '../save/types'

/** One skill milestone, and whether this save has reached it. */
export interface AchievementLogRow {
  achievementId: string
  name: string
  /** `Unlocked`, or what it takes: `Reach Mining level 50`. */
  note: string
  unlocked: boolean
}

export function achievementLog(db: GameDatabase, save: PlayerSave): AchievementLogRow[] {
  return asAchievementRows(db).map((achievement) => {
    const achievementId = achievement['Achievement ID']
    const unlocked = save.achievements.some(
      (row) => row.achievementId === achievementId && row.unlocked,
    )
    const skillName =
      db.Skills.find((skill) => skill['Skill ID'] === achievement['Target Skill ID'])?.[
        'Display Name'
      ] ?? 'Skill'
    return {
      achievementId,
      name: achievement['Display Name'],
      note: unlocked
        ? 'Unlocked'
        : `Reach ${skillName} level ${achievement['Required Level'] ?? 50}`,
      unlocked,
    }
  })
}

/** One objective of an active quest, with its bar already worked out. */
export interface QuestLogObjective {
  key: string
  /** `Deliver Cabbage: 3/5`. */
  label: string
  /** 0–100, capped, for the bar. */
  percent: number
}

export interface QuestLogRow {
  questId: string
  name: string
  /** `Rose needs herbs. · Rose`, the summary and who gave it. */
  detail: string
  statusLabel: string
  completed: boolean
  /** Empty unless the quest is active and asks for something countable. */
  objectives: QuestLogObjective[]
}

export function questLog(db: GameDatabase, save: PlayerSave): QuestLogRow[] {
  return asQuestRows(db).map((quest) => {
    const questId = quest['Quest ID']
    const status = getQuestProgress(save, questId).status
    const npcName =
      db.NPCs.find((npc) => npc['NPC ID'] === quest['NPC ID'])?.['Display Name'] ?? 'NPC'
    const objectives =
      status === 'active' ? questObjectiveProgress(db, save, quest).progressLines : []

    return {
      questId,
      name: quest['Display Name'],
      detail: `${quest.Summary ?? 'No summary.'} · ${npcName}`,
      statusLabel: questStatusLabel(status),
      completed: status === 'completed',
      objectives: objectives.map((line) => ({
        key: line.key,
        label: `${line.label}: ${Math.min(line.current, line.required)}/${line.required}`,
        percent: Math.min(100, Math.floor((line.current / Math.max(1, line.required)) * 100)),
      })),
    }
  })
}

/** One line of the recipe book, said the way a locked one has to be said. */
export interface RecipeLogRow {
  key: string
  /** The recipe's name, or what little a locked one gives away. */
  title: string
  detail: string
  known: boolean
}

export function recipeLog(db: GameDatabase, save: PlayerSave): RecipeLogRow[] {
  return listRecipeBookEntries(save, db).map((entry) => {
    const kind = entry.kind === 'project' ? 'Project' : 'Recipe'
    if (entry.known) {
      return {
        key: `${entry.kind}-${entry.id}`,
        title: entry.name,
        detail:
          `${kind} · ${entry.skill} ${entry.proficiency} · ` +
          `${entry.station} (${entry.location}) · ${entry.materials} → ${entry.output}`,
        known: true,
      }
    }
    // A mentor-taught recipe is not even named until somebody teaches it.
    return {
      key: `${entry.kind}-${entry.id}`,
      title: entry.hintUnknown ? 'Unknown recipe' : `Locked · ${entry.skill} ${entry.proficiency}`,
      detail: entry.hintUnknown
        ? entry.knowledgeSource
        : `Unlocks at ${entry.skill} level ${entry.proficiency}`,
      known: false,
    }
  })
}

/** One page of the critter collection, blank until one has been caught. */
export interface CritterLogRow {
  critterId: string
  internalKey: string
  /** `Unknown` until the player has met it. */
  name: string
  /** Null while unknown, so nothing is given away. */
  description: string | null
  count: number
  found: boolean
}

export function critterLog(save: PlayerSave): CritterLogRow[] {
  return CRITTER_DEFS.map((critter) => {
    const count = collectionCount(save, critter.id)
    const found = count > 0
    return {
      critterId: critter.id,
      internalKey: critter.internalKey,
      name: found ? critter.displayName : 'Unknown',
      description: found ? critter.description : null,
      count,
      found,
    }
  })
}
