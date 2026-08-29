import {
  REVOCABLE_ACHIEVEMENT_CATEGORY,
  asAchievementRows,
  type AchievementRow,
} from '../achievements/progress'
import { CRITTER_DEFS, collectionCount } from '../critters/critters'
import type { GameDatabase } from '../data/types'
import type { QuestRow } from '../quests/quests'
import { questLegacyJournalSteps } from '../quests/objectives'
import { asQuestRows, getQuestProgress, questStatusLabel } from '../quests/quests'
import {
  questCompletedJournal,
  questRequirementJournal,
  questStepJournal,
  questUsesSteps,
} from '../quests/steps'
import { listRecipeBookEntries, type RecipeBookEntry } from '../recipes/knowledge'
import type { PlayerSave } from '../save/types'
import { milestoneLog } from './milestones'

export { milestoneLog } from './milestones'
export type { MilestoneLogRow } from './milestones'

/** One skill milestone, and whether this save has reached it. */
export interface AchievementLogRow {
  achievementId: string
  name: string
  /** What it takes, even after the deed is finished. */
  note: string
  unlocked: boolean
  difficulty: string
}

export function achievementLog(db: GameDatabase, save: PlayerSave): AchievementLogRow[] {
  return asAchievementRows(db).map((achievement) => {
    const achievementId = achievement['Achievement ID']
    const unlocked = save.achievements.some(
      (row) => row.achievementId === achievementId && row.unlocked,
    )
    const difficulty = achievement.Difficulty ?? 'Easy'
    if (achievement.Category === REVOCABLE_ACHIEVEMENT_CATEGORY) {
      const held = CRITTER_DEFS.filter((critter) => collectionCount(save, critter.id) > 0).length
      return {
        achievementId,
        name: achievement['Display Name'],
        note: `Collect one of every critter (${held}/${CRITTER_DEFS.length})`,
        unlocked,
        difficulty,
      }
    }
    return {
      achievementId,
      name: achievement['Display Name'],
      note: achievementNote(achievement),
      unlocked,
      difficulty,
    }
  })
}

function achievementNote(achievement: AchievementRow): string {
  const check = achievement['Check Type'] ?? ''
  const count = achievement['Required Count']
  const level = achievement['Required Level']
  switch (check) {
    case 'skill_all':
      return `Reach level ${level ?? 50} in every skill`
    case 'gold':
      return `Earn ${Number(count ?? 0).toLocaleString('en-US')} gold`
    case 'spell_projects':
      return achievement.Notes ?? `Complete ${count ?? 1} spell project${Number(count ?? 1) === 1 ? '' : 's'}`
    case 'enchant':
      return 'Enchant an item'
    case 'potion':
      return 'Create a potion'
    case 'consume':
      return achievement.Notes ?? 'Eat the required item'
    case 'project':
    case 'output_item':
      return achievement.Notes ?? 'Complete the required work'
    default:
      return achievement.Notes ?? 'Locked'
  }
}

/** One step in an active quest journal. */
export interface QuestLogStep {
  key: string
  label: string
  state: 'done' | 'current'
}

export interface QuestLogRow {
  questId: string
  name: string
  /** Vague report of the situation, plus who gave it. */
  detail: string
  statusLabel: string
  completed: boolean
  /** Revealed steps for active quests; open the row to read them. */
  steps: QuestLogStep[]
}

export function questLog(db: GameDatabase, save: PlayerSave): QuestLogRow[] {
  return asQuestRows(db).map((quest) => {
    const questId = quest['Quest ID']
    const status = getQuestProgress(save, questId).status
    const npcName =
      db.NPCs.find((npc) => npc['NPC ID'] === quest['NPC ID'])?.['Display Name'] ?? 'NPC'
    const questRow = quest as QuestRow
    const steps =
      status === 'active'
        ? questUsesSteps(db, questId)
          ? questStepJournal(db, save, questRow)
          : questLegacyJournalSteps(db, save, questRow)
        : status === 'inactive'
          ? questRequirementJournal(db, save, questRow)
          : questCompletedJournal(db, questRow)

    return {
      questId,
      name: quest['Display Name'],
      detail: `${quest.Summary ?? 'No summary.'} · ${npcName}`,
      statusLabel: questStatusLabel(status),
      completed: status === 'completed',
      steps,
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

export function sentenceCase(text: string): string {
  const trimmed = text.trim()
  if (!trimmed) return trimmed
  return trimmed.charAt(0).toUpperCase() + trimmed.slice(1).toLowerCase()
}

export function formatRecipeMaterials(materials: string): string {
  return materials
    .split(', ')
    .map((part) => {
      const match = part.match(/^(.*?)\s*×\s*(\d+)\s*$/)
      if (match) return `${sentenceCase(match[1] ?? '')} × ${match[2]}`
      return sentenceCase(part)
    })
    .join(', ')
}

export function recipeLogRowFromEntry(entry: RecipeBookEntry): RecipeLogRow {
  if (entry.known) {
    return {
      key: `${entry.kind}-${entry.id}`,
      title: `${entry.proficiency}. ${sentenceCase(entry.name)}: ${formatRecipeMaterials(entry.materials)}`,
      detail: '',
      known: true,
    }
  }
  // A mentor-taught recipe is not even named until somebody teaches it.
  if (entry.hintUnknown) {
    return {
      key: `${entry.kind}-${entry.id}`,
      title: 'Unknown recipe',
      detail: entry.knowledgeSource,
      known: false,
    }
  }
  return {
    key: `${entry.kind}-${entry.id}`,
    title: `${entry.proficiency}. ${sentenceCase(entry.name)}`,
    detail: `Unlocks at ${entry.skill} level ${entry.proficiency}`,
    known: false,
  }
}

export function recipeLog(db: GameDatabase, save: PlayerSave): RecipeLogRow[] {
  return listRecipeBookEntries(save, db).map(recipeLogRowFromEntry)
}

export function recipeLogForEntries(entries: RecipeBookEntry[]): RecipeLogRow[] {
  return entries.map(recipeLogRowFromEntry)
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

/** How far through one page of the Log a save has got. */
export interface LogSectionCompletion {
  /** `achievements`, `milestones`, `quests`, or `critters`. */
  section: string
  done: number
  total: number
  /** Whole percent, so a page that is nearly done does not read as finished. */
  percent: number
  /** `3/13 · 23%`, the way the Log tabs say it. */
  label: string
}

/** Every page of the Log, plus the whole thing counted together. */
export interface LogCompletion {
  sections: LogSectionCompletion[]
  /**
   * Every entry of every page, so one big page cannot be outvoted by a small
   * one. Its `section` reads `total`.
   */
  overall: LogSectionCompletion
}

function completion(section: string, done: number, total: number): LogSectionCompletion {
  const percent = total <= 0 ? 0 : Math.floor((done * 100) / total)
  return { section, done, total, percent, label: `${done}/${total} · ${percent}%` }
}

export function logCompletion(db: GameDatabase, save: PlayerSave): LogCompletion {
  const achievements = achievementLog(db, save)
  const milestones = milestoneLog(db, save)
  const quests = questLog(db, save)
  const critters = critterLog(save)

  const sections = [
    completion(
      'achievements',
      achievements.filter((row) => row.unlocked).length,
      achievements.length,
    ),
    completion(
      'milestones',
      milestones.filter((row) => row.unlocked).length,
      milestones.length,
    ),
    completion('quests', quests.filter((row) => row.completed).length, quests.length),
    completion('critters', critters.filter((row) => row.found).length, critters.length),
  ]

  return {
    sections,
    overall: completion(
      'total',
      sections.reduce((sum, row) => sum + row.done, 0),
      sections.reduce((sum, row) => sum + row.total, 0),
    ),
  }
}
