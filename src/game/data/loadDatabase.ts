import {
  assertGameDatabaseShape,
  buildIndexes,
  countNeedsData,
  filterLaunchContent,
  validateDatabase,
} from './validate'
import type { DatabaseIndexes, GameDatabase, ValidationIssue } from './types'

/** Bump when Launch content rows change so browsers skip stale JSON. */
export const DATABASE_CONTENT_VERSION = '2026-08-11-lucky-necklace-drop-chance'
export const DATABASE_URL = `/data/game-database.json?v=${DATABASE_CONTENT_VERSION}`

export interface LoadedDatabase {
  /** Full source database (never mutated / filtered away). */
  source: GameDatabase
  /** Launch-phase view for runtime content selection. */
  launch: GameDatabase
  sourceIndexes: DatabaseIndexes
  launchIndexes: DatabaseIndexes
  issues: ValidationIssue[]
  needsDataCount: number
}

export async function fetchDatabase(url: string = DATABASE_URL): Promise<unknown> {
  const response = await fetch(url, { cache: 'no-cache' })
  if (!response.ok) {
    throw new Error(`Failed to load database (${response.status}) from ${url}`)
  }
  return response.json()
}

export function prepareDatabase(raw: unknown): LoadedDatabase {
  assertGameDatabaseShape(raw)
  const source = raw
  const issues = validateDatabase(source)
  const errors = issues.filter((issue) => issue.severity === 'error')
  if (errors.length > 0) {
    const summary = errors
      .slice(0, 5)
      .map((issue) => `${issue.table ?? 'root'}: ${issue.message}`)
      .join('; ')
    throw new Error(`Database validation failed (${errors.length} error(s)): ${summary}`)
  }

  const launch = filterLaunchContent(source)
  return {
    source,
    launch,
    sourceIndexes: buildIndexes(source),
    launchIndexes: buildIndexes(launch),
    issues,
    needsDataCount: countNeedsData(source),
  }
}

export async function loadDatabase(url: string = DATABASE_URL): Promise<LoadedDatabase> {
  const raw = await fetchDatabase(url)
  return prepareDatabase(raw)
}
