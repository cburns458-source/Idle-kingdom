import { REVOCABLE_ACHIEVEMENT_CATEGORY, asAchievementRows } from '../achievements/progress'
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
    if (achievement.Category === REVOCABLE_ACHIEVEMENT_CATEGORY) {
      const held = CRITTER_DEFS.filter((critter) => collectionCount(save, critter.id) > 0).length
      return {
        achievementId,
        name: achievement['Display Name'],
        note: unlocked
          ? 'Unlocked'
          : `Collect one of every critter (${held}/${CRITTER_DEFS.length})`,
        unlocked,
      }
    }
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
      objectives: objectives
        .filter((line) => line.current < line.required)
        .slice(0, 1)
        .map((line) => ({
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

/** How far through one page of the Log a save has got. */
export interface LogSectionCompletion {
  /** `achievements`, `quests`, `recipes`, or `critters`. */
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
  const quests = questLog(db, save)
  const recipes = recipeLog(db, save)
  const critters = critterLog(save)

  const sections = [
    completion(
      'achievements',
      achievements.filter((row) => row.unlocked).length,
      achievements.length,
    ),
    completion('quests', quests.filter((row) => row.completed).length, quests.length),
    completion('recipes', recipes.filter((row) => row.known).length, recipes.length),
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
