import type { PlayerSave, SaveMigration } from './types'
import { SAVE_VERSION } from './types'

/** Ordered migrations from older save versions up to SAVE_VERSION. */
export const SAVE_MIGRATIONS: SaveMigration[] = [
  {
    fromVersion: 1,
    toVersion: 2,
    migrate: (save) => ({
      ...save,
      currentActionId: save.currentActionId ?? null,
      actionStartedAt: save.actionStartedAt ?? null,
      actionDurationMs: save.actionDurationMs ?? null,
      saveVersion: 2,
    }),
  },
  {
    fromVersion: 2,
    toVersion: 3,
    migrate: (save) => ({
      ...save,
      combatEnemyId: save.combatEnemyId ?? null,
      combatEnemyHp: save.combatEnemyHp ?? null,
      combatRoundStartedAt: save.combatRoundStartedAt ?? null,
      deathPauseUntil: save.deathPauseUntil ?? null,
      saveVersion: 3,
    }),
  },
]

export function migrateSave(save: PlayerSave): PlayerSave {
  let current = { ...save }
  if (current.saveVersion > SAVE_VERSION) {
    throw new Error(
      `Save version ${current.saveVersion} is newer than supported version ${SAVE_VERSION}`,
    )
  }

  while (current.saveVersion < SAVE_VERSION) {
    const migration = SAVE_MIGRATIONS.find((entry) => entry.fromVersion === current.saveVersion)
    if (!migration) {
      throw new Error(`No save migration registered from version ${current.saveVersion}`)
    }
    current = migration.migrate(current)
    current.saveVersion = migration.toVersion
  }

  return current
}
