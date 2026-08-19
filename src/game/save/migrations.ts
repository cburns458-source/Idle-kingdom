import { ensureStartingHuntingTool } from './startingGear'
import type { ActivePotionEffect, EquippedStack, PlayerSave, SaveMigration } from './types'
import {
  DEFAULT_BEARD_ID,
  DEFAULT_EXPRESSION_ID,
  DEFAULT_GENDER_PRESENTATION_ID,
  DEFAULT_HAIRSTYLE_ID,
  DEFAULT_HAIR_COLOR_ID,
  DEFAULT_SKIN_TONE_ID,
  OUTFIT_COSMETIC_SLOT_ID,
  PET_COSMETIC_SLOT_ID,
  SAVE_VERSION,
  STARTER_OUTFIT_COSMETIC_ID,
  STARTER_TITLE_COSMETIC_ID,
  TITLE_COSMETIC_SLOT_ID,
} from './types'

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
    migrate: (save, nowMs) => ({
      ...save,
      // Anchor absence catch-up to last save touch so old creates do not grant a free 24h.
      unattendedProgressAt:
        typeof save.unattendedProgressAt === 'string' && save.unattendedProgressAt.length > 0
          ? save.unattendedProgressAt
          : (save.updatedAt ?? new Date(nowMs).toISOString()),
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
        hudShowTotalXp: save.settings?.hudShowTotalXp ?? false,
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
  {
    fromVersion: 14,
    toVersion: 15,
    migrate: (save) => ({
      ...save,
      unlockedLocationIds: Array.isArray(save.unlockedLocationIds)
        ? save.unlockedLocationIds
        : [],
      claimedMerchantTipIds: Array.isArray(save.claimedMerchantTipIds)
        ? save.claimedMerchantTipIds
        : [],
      saveVersion: 15,
    }),
  },
  {
    fromVersion: 15,
    toVersion: 16,
    migrate: (save) => ({
      ...save,
      critterCollections: Array.isArray(save.critterCollections) ? save.critterCollections : [],
      activeCritterSpawns: Array.isArray(save.activeCritterSpawns)
        ? save.activeCritterSpawns
        : [],
      critterProgressMs:
        save.critterProgressMs && typeof save.critterProgressMs === 'object'
          ? save.critterProgressMs
          : {},
      saveVersion: 16,
    }),
  },
  {
    fromVersion: 16,
    toVersion: 17,
    migrate: (save) => {
      const unlocked = Array.isArray(save.cosmetics?.unlocked) ? save.cosmetics.unlocked : []
      // Every character (new or migrated) starts fully dressed with the
      // default starter outfit unless something else is already equipped.
      const alreadyUnlocked = unlocked.includes(STARTER_OUTFIT_COSMETIC_ID)
      return {
        ...save,
        cosmetics: {
          unlocked: alreadyUnlocked ? unlocked : [...unlocked, STARTER_OUTFIT_COSMETIC_ID],
          equipped: {
            ...save.cosmetics?.equipped,
            [OUTFIT_COSMETIC_SLOT_ID]:
              save.cosmetics?.equipped?.[OUTFIT_COSMETIC_SLOT_ID] ?? STARTER_OUTFIT_COSMETIC_ID,
            [PET_COSMETIC_SLOT_ID]: save.cosmetics?.equipped?.[PET_COSMETIC_SLOT_ID] ?? null,
          },
        },
        appearance: {
          skinTone: save.appearance?.skinTone ?? DEFAULT_SKIN_TONE_ID,
          hairstyle: save.appearance?.hairstyle ?? DEFAULT_HAIRSTYLE_ID,
          hairColor: save.appearance?.hairColor ?? DEFAULT_HAIR_COLOR_ID,
          expression: save.appearance?.expression ?? DEFAULT_EXPRESSION_ID,
          beard: save.appearance?.beard ?? DEFAULT_BEARD_ID,
          genderPresentation:
            save.appearance?.genderPresentation ?? DEFAULT_GENDER_PRESENTATION_ID,
        },
        hasSeenWardrobeIntro: save.hasSeenWardrobeIntro ?? false,
        saveVersion: 17,
      }
    },
  },
  {
    fromVersion: 17,
    toVersion: 18,
    migrate: (save) => ({
      ...save,
      locationSearchClaims:
        save.locationSearchClaims && typeof save.locationSearchClaims === 'object'
          ? save.locationSearchClaims
          : {},
      saveVersion: 18,
    }),
  },
  {
    fromVersion: 18,
    toVersion: 19,
    migrate: (save) => ({
      ...save,
      // Existing named characters are forced through a one-time race picker.
      raceId: typeof save.raceId === 'string' && save.raceId.length > 0 ? save.raceId : null,
      saveVersion: 19,
    }),
  },
  {
    fromVersion: 19,
    toVersion: 20,
    migrate: (save) => ({
      ...save,
      // Normalize favorite flags; omit false so older stack shapes stay unchanged.
      inventory: (save.inventory ?? []).map((stack) => {
        if (stack.favorite === true) return { ...stack, favorite: true }
        const { favorite: _drop, ...rest } = stack
        return rest
      }),
      equipment: {
        ...save.equipment,
        slots: Object.fromEntries(
          Object.entries(save.equipment?.slots ?? {}).map(([slotId, stack]) => {
            if (!stack) return [slotId, null]
            if (stack.favorite === true) return [slotId, { ...stack, favorite: true }]
            const { favorite: _drop, ...rest } = stack
            return [slotId, rest]
          }),
        ),
      },
      saveVersion: 20,
    }),
  },
  {
    fromVersion: 20,
    toVersion: 21,
    migrate: (save) => ({
      ...save,
      unlockedRecipeIds: Array.isArray(save.unlockedRecipeIds) ? save.unlockedRecipeIds : [],
      quests: (save.quests ?? []).map((quest) => ({
        ...quest,
        counters:
          quest.counters && typeof quest.counters === 'object' ? quest.counters : undefined,
      })),
      saveVersion: 21,
    }),
  },
  {
    fromVersion: 21,
    toVersion: 22,
    migrate: (save) => ({
      ...save,
      bountyHourKey: typeof save.bountyHourKey === 'string' ? save.bountyHourKey : null,
      bountyProgress:
        save.bountyProgress && typeof save.bountyProgress === 'object'
          ? save.bountyProgress
          : {},
      bountyClaimedIds: Array.isArray(save.bountyClaimedIds) ? save.bountyClaimedIds : [],
      saveVersion: 22,
    }),
  },
  {
    fromVersion: 22,
    toVersion: 23,
    migrate: (save) => ({
      ...save,
      bank: Array.isArray(save.bank) ? save.bank : [],
      saveVersion: 23,
    }),
  },
  {
    fromVersion: 23,
    toVersion: 24,
    migrate: (save) => ({
      ...save,
      rankedPvpDayKey: typeof save.rankedPvpDayKey === 'string' ? save.rankedPvpDayKey : null,
      rankedPvpFightsToday: Number(save.rankedPvpFightsToday) || 0,
      rankedPvpWins: Number(save.rankedPvpWins) || 0,
      rankedPvpLosses: Number(save.rankedPvpLosses) || 0,
      saveVersion: 24,
    }),
  },
  {
    fromVersion: 24,
    toVersion: 25,
    migrate: (save) => ({
      ...save,
      favoriteActivityByLocationId:
        save.favoriteActivityByLocationId && typeof save.favoriteActivityByLocationId === 'object'
          ? save.favoriteActivityByLocationId
          : {},
      saveVersion: 25,
    }),
  },
  {
    fromVersion: 25,
    toVersion: 26,
    migrate: (save) => ({
      ...save,
      heldActionByActivityId:
        save.heldActionByActivityId && typeof save.heldActionByActivityId === 'object'
          ? save.heldActionByActivityId
          : {},
      saveVersion: 26,
    }),
  },
  {
    fromVersion: 26,
    toVersion: 27,
    // Characters that already exist keep the title: nothing recorded their
    // deaths before now, so the kindest reading is that they have not died.
    migrate: (save) => ({
      ...save,
      hasEverDied: save.hasEverDied === true,
      saveVersion: 27,
    }),
  },
  {
    fromVersion: 27,
    toVersion: 28,
    migrate: (save) => {
      const unlocked = Array.isArray(save.cosmetics?.unlocked) ? save.cosmetics.unlocked : []
      const equipped = { ...save.cosmetics?.equipped }
      if (save.hasEverDied === true) {
        return {
          ...save,
          cosmetics: {
            unlocked: unlocked.filter((id) => id !== STARTER_TITLE_COSMETIC_ID),
            equipped: { ...equipped, [TITLE_COSMETIC_SLOT_ID]: null },
          },
          saveVersion: 28,
        }
      }
      return {
        ...save,
        cosmetics: {
          unlocked: unlocked.includes(STARTER_TITLE_COSMETIC_ID)
            ? unlocked
            : [...unlocked, STARTER_TITLE_COSMETIC_ID],
          equipped: {
            ...equipped,
            [TITLE_COSMETIC_SLOT_ID]:
              equipped[TITLE_COSMETIC_SLOT_ID] ?? STARTER_TITLE_COSMETIC_ID,
          },
        },
        saveVersion: 28,
      }
    },
  },
]

export function migrateSave(save: PlayerSave, nowMs: number = Date.now()): PlayerSave {
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
    current = migration.migrate(current, nowMs)
    current.saveVersion = migration.toVersion
  }

  return current
}
