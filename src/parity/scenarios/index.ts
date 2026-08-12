import type { ParityScenario } from '../types'
import { activityScenarios } from './activity'
import { arcanaScenarios } from './arcana'
import { bountyScenarios } from './bounties'
import { combatScenarios } from './combat'
import { combatStatScenarios } from './combatStats'
import { contentScenarios } from './content'
import { coreRuleScenarios } from './coreRules'
import { equipmentScenarios } from './equipment'
import { metaScenarios } from './meta'
import { productionScenarios } from './production'
import { projectScenarios } from './projects'
import { questScenarios } from './quests'
import { raceScenarios } from './races'
import { rngScenarios } from './rng'
import { saveScenarios } from './save'
import { shopScenarios } from './shops'
import { supportScenarios } from './support'
import { unattendedScenarios } from './unattended'
import { worldScenarios } from './world'

/**
 * Every scenario recorded for the Dart port. Each porting phase appends its
 * modules here, and a module counts as ported once its fixtures replay green in
 * the Dart package tests.
 */
export const parityScenarios: ParityScenario[] = [
  ...rngScenarios,
  ...contentScenarios,
  ...coreRuleScenarios,
  ...supportScenarios,
  ...equipmentScenarios,
  ...arcanaScenarios,
  ...raceScenarios,
  ...combatStatScenarios,
  ...productionScenarios,
  ...projectScenarios,
  ...questScenarios,
  ...bountyScenarios,
  ...combatScenarios,
  ...activityScenarios,
  ...shopScenarios,
  ...worldScenarios,
  ...metaScenarios,
  ...saveScenarios,
  ...unattendedScenarios,
]

export function assertUniqueScenarioNames(scenarios: ParityScenario[]): void {
  const seen = new Set<string>()
  for (const entry of scenarios) {
    const key = `${entry.module}/${entry.name}`
    if (seen.has(key)) throw new Error(`Duplicate parity scenario: ${key}`)
    seen.add(key)
  }
}
