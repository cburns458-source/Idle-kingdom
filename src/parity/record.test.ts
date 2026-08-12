import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmdirSync,
  rmSync,
  writeFileSync,
} from 'node:fs'
import { dirname, relative, resolve } from 'node:path'
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

/** Every fixture file currently on disk. */
function recordedFixtures(dir = FIXTURE_ROOT): string[] {
  if (!existsSync(dir)) return []
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = resolve(dir, entry.name)
    if (entry.isDirectory()) return recordedFixtures(path)
    return entry.name.endsWith('.json') ? [path] : []
  })
}

/** Removes [dir] and its now-empty parents, stopping at the fixture root. */
function pruneEmptyDirs(dir: string): void {
  let current = dir
  while (current !== FIXTURE_ROOT && readdirSync(current).length === 0) {
    rmdirSync(current)
    current = dirname(current)
  }
}

describe('parity fixtures', () => {
  it('has uniquely named scenarios', () => {
    expect(() => assertUniqueScenarioNames(parityScenarios)).not.toThrow()
    expect(parityScenarios.length).toBeGreaterThan(0)
  })

  // A renamed scenario leaves its old fixture behind, and a Dart test looping
  // over a directory would keep replaying it against rules that no longer
  // produce it. Recording deletes orphans; checking fails on them.
  it(RECORDING ? 'deletes orphaned fixtures' : 'has no orphaned fixtures', () => {
    const expected = new Set(parityScenarios.map(fixturePath))
    const orphans = recordedFixtures().filter((path) => !expected.has(path))
    if (RECORDING) {
      for (const path of orphans) {
        rmSync(path)
        pruneEmptyDirs(dirname(path))
      }
      return
    }
    expect(
      orphans.map((path) => relative(FIXTURE_ROOT, path)),
      'Fixtures with no scenario. Re-record with npm run parity:record.',
    ).toEqual([])
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
