import type { GameDatabase } from '../data/types'
import { totalLevel } from '../skills/totals'
import type { PlayerSave } from '../save/types'

export interface MiniQuestSource {
  'Quest ID': string
  'Display Name': string
  'NPC ID': string
  Summary: string | null
  Notes: string | null
  Repeatable: string | null
}

const DAY_MS = 24 * 60 * 60 * 1000

export function noteFieldValue(notes: string | null | undefined, pattern: string): string | undefined {
  return (notes ?? '').match(new RegExp(pattern, 'i'))?.[1]
}

export function requiredTotalLevelFromNotes(notes: string | null | undefined): number {
  const raw = noteFieldValue(notes, String.raw`RequiresTotalLevel:\s*(\d+)`)
  const level = raw ? Number(raw) : 0
  return Number.isFinite(level) ? level : 0
}

export function isMiniquest(quest: MiniQuestSource): boolean {
  const notes = quest.Notes ?? ''
  return /(?:^|;)\s*Miniquest\b/i.test(notes) || /(?:^|;)\s*HideFromQuestLog\b/i.test(notes)
}

export function hideFromQuestLog(quest: MiniQuestSource): boolean {
  return isMiniquest(quest)
}

export function miniquestRepeatMs(quest: MiniQuestSource): number | null {
  const notes = quest.Notes ?? ''
  const days = noteFieldValue(notes, String.raw`Repeatable:\s*(\d+)\s*d`)
  if (days) {
    const count = Number(days)
    return Number.isFinite(count) && count > 0 ? count * DAY_MS : null
  }
  const weekly = (quest.Repeatable ?? '').toLowerCase()
  if (weekly === 'weekly' || weekly === 'yes') return 7 * DAY_MS
  return null
}

export function meetsTotalLevelRequirement(
  save: PlayerSave,
  notes: string | null | undefined,
): boolean {
  const required = requiredTotalLevelFromNotes(notes)
  return required <= 0 || totalLevel(save) >= required
}

export function miniquestLastCompletedAt(save: PlayerSave, questId: string): number | null {
  const stamp = save.miniquestCompletedAt?.[questId]
  if (!stamp) return null
  const ms = Date.parse(stamp)
  return Number.isFinite(ms) ? ms : null
}

export function recordMiniquestCompletion(
  save: PlayerSave,
  questId: string,
  nowMs: number,
): PlayerSave {
  return {
    ...save,
    miniquestCompletedAt: {
      ...(save.miniquestCompletedAt ?? {}),
      [questId]: new Date(nowMs).toISOString(),
    },
  }
}

export function formatDurationRemaining(ms: number): string {
  const remaining = Math.max(0, Math.floor(ms))
  const days = Math.floor(remaining / DAY_MS)
  const hours = Math.floor((remaining % DAY_MS) / (60 * 60 * 1000))
  const minutes = Math.floor((remaining % (60 * 60 * 1000)) / (60 * 1000))
  if (days >= 1) {
    if (hours > 0) return `${days} day${days === 1 ? '' : 's'} ${hours} hour${hours === 1 ? '' : 's'}`
    return `${days} day${days === 1 ? '' : 's'}`
  }
  if (hours >= 1) return `${hours} hour${hours === 1 ? '' : 's'}`
  const shown = Math.max(1, minutes)
  return `${shown} minute${shown === 1 ? '' : 's'}`
}

export function miniquestRepeatReadyAt(save: PlayerSave, quest: MiniQuestSource): number | null {
  const last = miniquestLastCompletedAt(save, quest['Quest ID'])
  const repeatMs = miniquestRepeatMs(quest)
  if (last == null || repeatMs == null) return null
  return last + repeatMs
}

export function miniquestCanRepeat(save: PlayerSave, quest: MiniQuestSource, nowMs: number): boolean {
  const readyAt = miniquestRepeatReadyAt(save, quest)
  return readyAt == null || nowMs >= readyAt
}

export interface MiniQuestLogRow {
  questId: string
  name: string
  detail: string
  /** Whether this miniquest can be done again on a timer. */
  repeatable: boolean
  /** How often it repeats, when it does. */
  repeatEveryLabel: string | null
  /** `Available now` or `Repeat in 4 days`. */
  repeatLabel: string
  ready: boolean
}

function repeatEveryLabel(quest: MiniQuestSource): string | null {
  const ms = miniquestRepeatMs(quest)
  if (ms == null) return null
  if (ms === 7 * DAY_MS) return 'Every 7 days'
  const days = Math.round(ms / DAY_MS)
  if (days >= 1) return `Every ${days} day${days === 1 ? '' : 's'}`
  return null
}

export function miniQuestLog(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number = Date.now(),
): MiniQuestLogRow[] {
  return (db.Quests as unknown as MiniQuestSource[])
    .filter((quest) => isMiniquest(quest))
    .filter((quest) => meetsTotalLevelRequirement(save, quest.Notes))
    .map((quest) => {
      const questId = quest['Quest ID']
      const npcName =
        db.NPCs.find((npc) => npc['NPC ID'] === quest['NPC ID'])?.['Display Name'] ?? 'NPC'
      const ready = miniquestCanRepeat(save, quest, nowMs)
      const readyAt = miniquestRepeatReadyAt(save, quest)
      const last = miniquestLastCompletedAt(save, questId)
      const repeatable = miniquestRepeatMs(quest) != null
      let repeatLabel = 'Available now'
      if (repeatable && last != null && !ready && readyAt != null) {
        repeatLabel = `Repeat in ${formatDurationRemaining(readyAt - nowMs)}`
      } else if (repeatable && last != null && ready) {
        repeatLabel = 'Can be repeated now'
      }
      return {
        questId,
        name: quest['Display Name'],
        detail: `${quest.Summary ?? 'No summary.'} · ${npcName}`,
        repeatable,
        repeatEveryLabel: repeatEveryLabel(quest),
        repeatLabel,
        ready,
      }
    })
}

export function getMiniquest(db: GameDatabase, questId: string): MiniQuestSource | undefined {
  const quest = (db.Quests as unknown as MiniQuestSource[]).find((row) => row['Quest ID'] === questId)
  return quest && isMiniquest(quest) ? quest : undefined
}
