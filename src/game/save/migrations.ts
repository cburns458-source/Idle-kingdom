import { ensureStartingHuntingTool } from './startingGear'
import type { ActivePotionEffect, EquippedStack, PlayerSave, SaveMigration } from './types'
import { SAVE_VERSION } from './types'

const FOOD_SLOT_ID = 'SLOT-0011'

function migrateEquipmentSlotsToStacks(save: PlayerSave): PlayerSave {
  const rawSlots = save.equipment?.slots ?? {}
  const nextSlots: Record<string, EquippedStack | null> = {}
  let inventory = (save.inventory ?? []).map((stack) => ({ ...stack }))

  for (const [slotId, value] of Object.entries(rawSlots)) {
    if (value == null) {
      nextSlots[slotId] = null
      continue
    }
    if (typeof value === 'object' && value !== null && 'itemId' in value) {
      const stack = value as EquippedStack
      nextSlots[slotId] = {
        itemId: stack.itemId,
        quantity: Math.max(1, Number(stack.quantity) || 1),
      }
      continue
    }
    if (typeof value !== 'string') {
      nextSlots[slotId] = null
      continue
    }

    const itemId = value
    if (slotId === FOOD_SLOT_ID) {
      const inv = inventory.find((entry) => entry.itemId === itemId)
      const quantity = inv?.quantity ?? 1
      inventory = inventory.filter((entry) => entry.itemId !== itemId)
      nextSlots[slotId] = { itemId, quantity }
    } else {
      nextSlots[slotId] = { itemId, quantity: 1 }
    }
  }

  return {
    ...save,
    inventory,
    equipment: { slots: nextSlots },
  }
}

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
  {
    fromVersion: 3,
    toVersion: 4,
    migrate: (save) => ({
      ...migrateEquipmentSlotsToStacks(save),
      saveVersion: 4,
    }),
  },
  {
    fromVersion: 4,
    toVersion: 5,
    migrate: (save) => ({
      ...ensureStartingHuntingTool(save),
      saveVersion: 5,
    }),
  },
  {
    fromVersion: 5,
    toVersion: 6,
    migrate: (save) => ({
      ...save,
      characterName: save.characterName ?? null,
      saveVersion: 6,
    }),
  },
  {
    fromVersion: 6,
    toVersion: 7,
    migrate: (save) => ({
      ...save,
      productionRecipeId: save.productionRecipeId ?? null,
      productionQuantityTotal: save.productionQuantityTotal ?? null,
      productionQuantityRemaining: save.productionQuantityRemaining ?? null,
      saveVersion: 7,
    }),
  },
  {
    fromVersion: 7,
    toVersion: 8,
    migrate: (save) => ({
      ...save,
      unlockedNpcIds: Array.isArray(save.unlockedNpcIds) ? save.unlockedNpcIds : [],
      saveVersion: 8,
    }),
  },
  {
    fromVersion: 8,
    toVersion: 9,
    migrate: (save) => ({
      ...save,
      // Anchor absence catch-up to last save touch so old creates do not grant a free 24h.
      unattendedProgressAt:
        typeof save.unattendedProgressAt === 'string' && save.unattendedProgressAt.length > 0
          ? save.unattendedProgressAt
          : (save.updatedAt ?? new Date().toISOString()),
      saveVersion: 9,
    }),
  },
  {
    fromVersion: 9,
    toVersion: 10,
    migrate: (save) => ({
      ...save,
      activityTransition: save.activityTransition ?? null,
      saveVersion: 10,
    }),
  },
  {
    fromVersion: 10,
    toVersion: 11,
    migrate: (save) => ({
      ...save,
      settings: {
        soundEnabled: save.settings?.soundEnabled ?? true,
        showActivityRewards: save.settings?.showActivityRewards ?? true,
      },
      saveVersion: 11,
    }),
  },
  {
    fromVersion: 11,
    toVersion: 12,
    migrate: (save) => ({
      ...save,
      combatPotionDamageBonusPercent:
        (save as PlayerSave & { combatPotionDamageBonusPercent?: number | null })
          .combatPotionDamageBonusPercent ?? null,
      saveVersion: 12,
    }),
  },
  {
    fromVersion: 12,
    toVersion: 13,
    migrate: (save) => {
      const legacy = save as PlayerSave & {
        combatPotionDamageBonusPercent?: number | null
        activePotionEffect?: ActivePotionEffect | null
      }
      const bonus = legacy.combatPotionDamageBonusPercent
      const activePotionEffect =
        legacy.activePotionEffect ??
        (typeof bonus === 'number' && bonus > 0
          ? {
              scope: 'one_combat_encounter' as const,
              itemId: '',
              damageBonusPercent: bonus,
              enemyMaxHpDamagePercent: null,
              relativeDropChanceBonusPercent: null,
              baseDurationReductionPercent: null,
            }
          : null)
      const { combatPotionDamageBonusPercent: _removed, ...rest } = legacy
      return {
        ...rest,
        activePotionEffect,
        saveVersion: 13,
      }
    },
  },
  {
    fromVersion: 13,
    toVersion: 14,
    migrate: (save) => ({
      ...save,
      settings: {
        soundEnabled: save.settings?.soundEnabled ?? true,
        showActivityRewards: save.settings?.showActivityRewards ?? true,
        hudShowTotalXp: save.settings?.hudShowTotalXp ?? false,
      },
      saveVersion: 14,
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
