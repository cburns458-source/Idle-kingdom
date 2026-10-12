/**
 * Self-only developer chat commands.
 *
 * Authorization lives in the edge function (developer_accounts). This module
 * only parses arguments and mutates a save copy.
 */

import { raiseSkillToMinimumLevel, getSkillProgress } from '../activity/xp'
import { addItemsToInventory } from '../activity/rewards'
import { spawnCritterAtLocation } from '../critters/critters'
import type { GameDatabase } from '../data/types'
import { assignRace } from '../races/assignRace'
import { resetIntroFlags, resetQuestProgress } from '../quests/quests'
import type { PlayerSave, SkillProgress } from '../save/types'
import { withRecalculatedVitals } from '../equipment/vitals'

export type DevCommandResult = {
  ok: boolean
  reason: string
  save: PlayerSave
  message: string
}

export type DevCommandHelpLine = { name: string; usage: string; summary: string }

export const DEV_COMMAND_HELP: DevCommandHelpLine[] = [
  { name: 'help', usage: '/help', summary: 'List developer commands.' },
  { name: 'give', usage: '/give <item> [qty]', summary: 'Add an item to your bag.' },
  { name: 'setlevel', usage: '/setlevel <skill> <level>', summary: 'Set a skill level.' },
  { name: 'teleport', usage: '/teleport <location>', summary: 'Move to a location instantly.' },
  { name: 'race', usage: '/race <race>', summary: 'Change your race without a kit.' },
  { name: 'critter', usage: '/critter', summary: 'Spawn the habitat critter here.' },
  {
    name: 'resetquests',
    usage: '/resetquests <quest|fennel|wardrobe>… confirm',
    summary: 'Clear quest progress (requires confirm).',
  },
  {
    name: 'resetskills',
    usage: '/resetskills confirm',
    summary: 'Reset every skill to level 1 (requires confirm).',
  },
]

function failed(save: PlayerSave, reason: string): DevCommandResult {
  return { ok: false, reason, save, message: reason }
}

function ok(save: PlayerSave, message: string): DevCommandResult {
  return { ok: true, reason: '', save, message }
}

function normalizeToken(raw: string): string {
  return raw.trim().toLowerCase().replace(/\s+/g, ' ')
}

function resolveItemId(db: GameDatabase, token: string): string | null {
  const trimmed = token.trim()
  if (!trimmed) return null
  if (db.Items.some((row) => row['Item ID'] === trimmed)) return trimmed
  const needle = normalizeToken(trimmed)
  const matches = db.Items.filter((row) => normalizeToken(row['Display Name']) === needle)
  if (matches.length === 1) return matches[0]!['Item ID']
  const keyMatches = db.Items.filter((row) => normalizeToken(row['Internal Key']) === needle)
  if (keyMatches.length === 1) return keyMatches[0]!['Item ID']
  return null
}

function resolveSkillId(db: GameDatabase, token: string): string | null {
  const trimmed = token.trim()
  if (!trimmed) return null
  if (db.Skills.some((row) => row['Skill ID'] === trimmed)) return trimmed
  const needle = normalizeToken(trimmed)
  const matches = db.Skills.filter((row) => normalizeToken(row['Display Name']) === needle)
  if (matches.length === 1) return matches[0]!['Skill ID']
  const keyMatches = db.Skills.filter((row) => normalizeToken(row['Internal Key']) === needle)
  if (keyMatches.length === 1) return keyMatches[0]!['Skill ID']
  return null
}

function resolveLocationId(db: GameDatabase, token: string): string | null {
  const trimmed = token.trim()
  if (!trimmed) return null
  if (db.Locations.some((row) => row['Location ID'] === trimmed)) return trimmed
  const needle = normalizeToken(trimmed)
  const matches = db.Locations.filter((row) => normalizeToken(row['Display Name']) === needle)
  if (matches.length === 1) return matches[0]!['Location ID']
  const keyMatches = db.Locations.filter((row) => normalizeToken(row['Internal Key']) === needle)
  if (keyMatches.length === 1) return keyMatches[0]!['Location ID']
  return null
}

function resolveRaceId(db: GameDatabase, token: string): string | null {
  const trimmed = token.trim()
  if (!trimmed) return null
  if (db.Races.some((row) => row['Race ID'] === trimmed)) return trimmed
  const needle = normalizeToken(trimmed)
  const matches = db.Races.filter((row) => normalizeToken(row['Display Name']) === needle)
  if (matches.length === 1) return matches[0]!['Race ID']
  const keyMatches = db.Races.filter((row) => normalizeToken(row['Internal Key']) === needle)
  if (keyMatches.length === 1) return keyMatches[0]!['Race ID']
  return null
}

function withSkillLevel(
  db: GameDatabase,
  save: PlayerSave,
  skillId: string,
  level: number,
): PlayerSave {
  const target = Math.max(1, Math.floor(level))
  let xp = 0
  for (const row of db.XPCurve) {
    if (row.Level === target) {
      xp = row['Total XP at Level']
      break
    }
  }
  const skills = save.skills.map((row) => ({ ...row }))
  const index = skills.findIndex((row) => row.skillId === skillId)
  const progress: SkillProgress = { skillId, level: target, xp }
  if (index < 0) skills.push(progress)
  else skills[index] = progress
  return { ...save, skills }
}

function clearActivity(save: PlayerSave): PlayerSave {
  return {
    ...save,
    currentActivityId: null,
    activityStartedAt: null,
    currentActionId: null,
    actionStartedAt: null,
    actionDurationMs: null,
    combatEnemyId: null,
    combatEnemyHp: null,
    combatRoundStartedAt: null,
    combatManualEatRoundStartedAt: null,
    combatPlayerSwingApplied: false,
    combatPendingRound: null,
    combatEatUntil: null,
    combatContinueActivityAfterEat: false,
  }
}

/** Parse `/give copper ore 5` into command + raw argument tokens. */
export function parseDevCommandLine(line: string): { command: string; tokens: string[] } | null {
  const trimmed = line.trim()
  if (!trimmed.startsWith('/')) return null
  const body = trimmed.slice(1).trim()
  if (!body) return { command: 'help', tokens: [] }
  const parts = body.split(/\s+/).filter(Boolean)
  const command = (parts[0] ?? 'help').toLowerCase()
  return { command, tokens: parts.slice(1) }
}

export function applyDevCommand(
  db: GameDatabase,
  save: PlayerSave,
  command: string,
  tokens: string[],
  nowMs: number,
): DevCommandResult {
  switch (command.toLowerCase()) {
    case 'help': {
      const lines = DEV_COMMAND_HELP.map((row) => `${row.usage} — ${row.summary}`)
      return ok(save, lines.join('\n'))
    }
    case 'give': {
      if (tokens.length < 1) return failed(save, 'Usage: /give <item> [qty]')
      let qty = 1
      let nameTokens = tokens
      const last = tokens[tokens.length - 1]!
      if (tokens.length >= 2 && /^\d+$/.test(last)) {
        qty = Math.max(1, Math.floor(Number(last)))
        nameTokens = tokens.slice(0, -1)
      }
      const itemId = resolveItemId(db, nameTokens.join(' '))
      if (!itemId) return failed(save, 'Unknown item.')
      const before = inventoryQty(save, itemId)
      const added = addItemsToInventory(save, itemId, qty, null, false, db)
      const gained = inventoryQty(added.save, itemId) - before + (isGold(db, itemId) ? added.added : 0)
      if (added.added <= 0) return failed(save, 'Could not add that item.')
      const name = db.Items.find((row) => row['Item ID'] === itemId)?.['Display Name'] ?? itemId
      return ok(added.save, `Added ${gained || added.added} ${name}.`)
    }
    case 'setlevel': {
      if (tokens.length < 2) return failed(save, 'Usage: /setlevel <skill> <level>')
      const levelToken = tokens[tokens.length - 1]!
      const level = Number(levelToken)
      if (!Number.isFinite(level)) return failed(save, 'Usage: /setlevel <skill> <level>')
      const skillId = resolveSkillId(db, tokens.slice(0, -1).join(' '))
      if (!skillId) return failed(save, 'Unknown skill.')
      const maxLevel = db.XPCurve.length ? db.XPCurve[db.XPCurve.length - 1]!.Level : 1
      const target = Math.min(maxLevel, Math.max(1, Math.floor(level)))
      const current = getSkillProgress(save, skillId).level
      let next = save
      if (target >= current) {
        const raised = raiseSkillToMinimumLevel(save, db, skillId, target)
        next = raised.save
      } else {
        next = withSkillLevel(db, save, skillId, target)
      }
      const name = db.Skills.find((row) => row['Skill ID'] === skillId)?.['Display Name'] ?? skillId
      return ok(next, `${name} is now level ${getSkillProgress(next, skillId).level}.`)
    }
    case 'teleport': {
      if (tokens.length < 1) return failed(save, 'Usage: /teleport <location>')
      const locationId = resolveLocationId(db, tokens.join(' '))
      if (!locationId) return failed(save, 'Unknown location.')
      const name =
        db.Locations.find((row) => row['Location ID'] === locationId)?.['Display Name'] ?? locationId
      const next = withRecalculatedVitals(db, {
        ...clearActivity(save),
        currentLocationId: locationId,
      })
      return ok(next, `Teleported to ${name}.`)
    }
    case 'race': {
      if (tokens.length < 1) return failed(save, 'Usage: /race <race>')
      const raceId = resolveRaceId(db, tokens.join(' '))
      if (!raceId) return failed(save, 'Unknown race.')
      const assigned = assignRace(db, save, raceId)
      if (!assigned.ok) return failed(save, assigned.reason)
      const name = db.Races.find((row) => row['Race ID'] === raceId)?.['Display Name'] ?? raceId
      return ok(assigned.save, `Race is now ${name}.`)
    }
    case 'critter': {
      const result = spawnCritterAtLocation(save, save.currentLocationId, nowMs)
      if (!result.ok) return failed(save, result.reason)
      return ok(result.save, `${result.critter.displayName} appeared.`)
    }
    case 'resetquests': {
      if (!tokens.map((part) => part.toLowerCase()).includes('confirm')) {
        return failed(save, 'Add confirm to reset quests.')
      }
      const parts = tokens.filter((part) => part.toLowerCase() !== 'confirm')
      if (parts.length === 0) return failed(save, 'Pick a quest id, fennel, or wardrobe.')
      const questIds: string[] = []
      let fennel = false
      let wardrobe = false
      for (const part of parts) {
        const lower = part.toLowerCase()
        if (lower === 'fennel') fennel = true
        else if (lower === 'wardrobe') wardrobe = true
        else questIds.push(part)
      }
      let next = resetQuestProgress(save, questIds)
      next = resetIntroFlags(next, { fennel, wardrobe })
      return ok(next, 'Quest progress reset.')
    }
    case 'resetskills': {
      if (!tokens.map((part) => part.toLowerCase()).includes('confirm')) {
        return failed(save, 'Add confirm to reset every skill.')
      }
      let next = save
      for (const skill of save.skills) {
        next = withSkillLevel(db, next, skill.skillId, 1)
      }
      return ok(next, 'Every skill is back at level 1.')
    }
    default:
      return failed(save, `Unknown command. Try /help.`)
  }
}

function inventoryQty(save: PlayerSave, itemId: string): number {
  return save.inventory
    .filter((stack) => stack.itemId === itemId)
    .reduce((sum, stack) => sum + stack.quantity, 0)
}

function isGold(db: GameDatabase, itemId: string): boolean {
  return db.Items.some(
    (row) => row['Item ID'] === itemId && String(row['Functional / Source Tags'] ?? '').includes('currency'),
  )
}
