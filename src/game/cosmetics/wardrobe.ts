import type { GameDatabase } from '../data/types'
import type { PlayerAppearance, PlayerSave } from '../save/types'
import {
  APPEARANCE_CATEGORIES,
  appearanceCategoryLabel,
  appearanceOptions,
  type AppearanceCategory,
} from './appearance'
import {
  cosmeticById,
  cosmeticSlotById,
  cosmeticSlots,
  cosmeticsForSlot,
  equippedCosmeticId,
  isCosmeticUnlocked,
} from './cosmetics'

function itemName(db: GameDatabase, itemId: string): string | null {
  return db.Items.find((row) => row['Item ID'] === itemId)?.['Display Name'] ?? null
}

/** One tab of the wardrobe, in table order. */
export interface WardrobeSlotTab {
  slotId: string
  label: string
}

export function wardrobeSlotTabs(db: GameDatabase): WardrobeSlotTab[] {
  return cosmeticSlots(db).map((slot) => ({
    slotId: slot['Cosmetic Slot ID'],
    label: slot['Display Name'],
  }))
}

/** One owned cosmetic, as its tile reads. */
export interface WardrobeTile {
  cosmeticId: string
  itemId: string
  name: string
  equipped: boolean
}

/** The wardrobe's lower half for one slot: what is owned and what is worn. */
export interface WardrobeSlotView {
  slotId: string
  label: string
  equippedCosmeticId: string | null
  /** Only what the player owns — a wardrobe is not a catalogue. */
  tiles: WardrobeTile[]
  /** What to say instead of tiles when the slot has nothing in it yet. */
  emptyNote: string
}

/**
 * The wardrobe's view of one slot.
 *
 * Falls back to the first slot when [slotId] names none, so a client can open
 * on a remembered tab without checking whether it still exists.
 */
export function wardrobeSlotView(
  db: GameDatabase,
  save: PlayerSave,
  slotId: string,
): WardrobeSlotView | null {
  const slot = cosmeticSlotById(db, slotId) ?? cosmeticSlots(db)[0]
  if (!slot) return null
  const resolvedId = slot['Cosmetic Slot ID']
  const equipped = equippedCosmeticId(save, resolvedId)

  return {
    slotId: resolvedId,
    label: slot['Display Name'],
    equippedCosmeticId: equipped,
    tiles: cosmeticsForSlot(db, resolvedId)
      .filter((cosmetic) => isCosmeticUnlocked(save, cosmetic['Cosmetic ID']))
      .map((cosmetic) => {
        const cosmeticId = cosmetic['Cosmetic ID']
        const itemId = cosmetic['Item ID']
        return {
          cosmeticId,
          itemId,
          name: itemName(db, itemId) ?? cosmeticId,
          equipped: cosmeticId === equipped,
        }
      }),
    emptyNote: `No ${slot['Display Name']} unlocked yet.`,
  }
}

/** One appearance row: a label and the stops its slider can land on. */
export interface AppearanceSlider {
  category: AppearanceCategory
  label: string
  optionIds: string[]
  /** Index into [optionIds]; 0 when the save holds an option the table dropped. */
  selectedIndex: number
}

/**
 * The appearance rows, in category order, skipping any the content has no
 * options for.
 *
 * Takes the appearance rather than the save because character creation picks a
 * look before there is a save to put it in.
 */
export function appearanceSliders(
  db: GameDatabase,
  appearance: PlayerAppearance,
): AppearanceSlider[] {
  const sliders: AppearanceSlider[] = []
  for (const category of APPEARANCE_CATEGORIES) {
    const optionIds = appearanceOptions(db, category).map((row) => row['Appearance Option ID'])
    if (optionIds.length === 0) continue
    sliders.push({
      category,
      label: appearanceCategoryLabel(category),
      optionIds,
      selectedIndex: Math.max(0, optionIds.indexOf(appearance[category])),
    })
  }
  return sliders
}

/** What the popup says when a cosmetic is unlocked. */
export interface CosmeticUnlockNotice {
  cosmeticId: string
  /** Null when the cosmetic has no item behind it, which only bad data causes. */
  itemId: string | null
  name: string
  /** The one-time "tap your portrait" line, for the player's first cosmetic. */
  hint: string | null
}

const WARDROBE_HINT =
  'Tap your portrait in the top-left corner anytime to open the Wardrobe and equip it.'

export function cosmeticUnlockNotice(
  db: GameDatabase,
  cosmeticId: string,
  isFirstEver: boolean,
): CosmeticUnlockNotice | null {
  const cosmetic = cosmeticById(db, cosmeticId)
  if (!cosmetic) return null
  const itemId = cosmetic['Item ID']
  return {
    cosmeticId,
    itemId: itemId ?? null,
    name: (itemId ? itemName(db, itemId) : null) ?? cosmeticId,
    hint: isFirstEver ? WARDROBE_HINT : null,
  }
}
