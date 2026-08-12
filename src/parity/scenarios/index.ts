import type { ParityScenario } from '../types'
import { arcanaScenarios } from './arcana'
import { combatStatScenarios } from './combatStats'
import { contentScenarios } from './content'
import { coreRuleScenarios } from './coreRules'
import { equipmentScenarios } from './equipment'
import { raceScenarios } from './races'
import { rngScenarios } from './rng'
import { supportScenarios } from './support'

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
]

export function assertUniqueScenarioNames(scenarios: ParityScenario[]): void {
  const seen = new Set<string>()
  for (const entry of scenarios) {
    const key = `${entry.module}/${entry.name}`
    if (seen.has(key)) throw new Error(`Duplicate parity scenario: ${key}`)
    seen.add(key)
  }
}
