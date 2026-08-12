import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { canonicalJson } from './canonicalJson'
import { assertUniqueScenarioNames, parityScenarios } from './scenarios'
import type { ParityScenario } from './types'

/**
 * Records parity fixtures with `npm run parity:record`, and otherwise asserts
 * the committed fixtures still match what the TypeScript rules produce. Running
 * as part of the normal suite means TS behavior cannot drift away from the Dart
 * port unnoticed.
 */
const RECORDING = process.env.PARITY_RECORD === '1'
const FIXTURE_ROOT = resolve(process.cwd(), 'parity/fixtures')

function fixturePath(entry: ParityScenario): string {
  return resolve(FIXTURE_ROOT, entry.module, `${entry.name}.json`)
}

function fixtureBody(entry: ParityScenario): string {
  const document = {
    module: entry.module,
    case: entry.name,
    input: entry.input,
    output: entry.output(),
  }
  return `${canonicalJson(document)}\n`
}

describe('parity fixtures', () => {
  it('has uniquely named scenarios', () => {
    expect(() => assertUniqueScenarioNames(parityScenarios)).not.toThrow()
    expect(parityScenarios.length).toBeGreaterThan(0)
  })

  for (const entry of parityScenarios) {
    const label = `${entry.module}/${entry.name}`
    it(RECORDING ? `records ${label}` : `matches recorded ${label}`, () => {
      const path = fixturePath(entry)
      const body = fixtureBody(entry)

      if (RECORDING) {
        mkdirSync(dirname(path), { recursive: true })
        writeFileSync(path, body, 'utf8')
        return
      }

      expect(
        existsSync(path),
        `Missing fixture for ${label}. Run: npm run parity:record`,
      ).toBe(true)
      expect(
        readFileSync(path, 'utf8'),
        `Fixture drift for ${label}. If the TypeScript change is intended, re-record with npm run parity:record and re-run the Dart parity suite.`,
      ).toBe(body)
    })
  }
})
