import { BANK_SLOT_LIMIT, INVENTORY_STACK_MAX } from '../inventory/capacity'
import { stackIsUnbankableGold } from '../inventory/bank'
import type { PlayerSave } from '../save/types'
import { addItemToInventoryExact } from '../activity/rewards'

export const GUILD_BANK_SECTION_MAIN = 'main'
export const GUILD_BANK_SECTION_UP_FOR_GRABS = 'up_for_grabs'

export type GuildBankSection = typeof GUILD_BANK_SECTION_MAIN | typeof GUILD_BANK_SECTION_UP_FOR_GRABS

export type GuildBankItem = {
  id: string
  itemId: string
  quantity: number
  enchantmentId?: string | null
  section: GuildBankSection
}

export type GuildBankState = {
  items: GuildBankItem[]
}

export type GuildBankActionResult =
  | { ok: true; save: PlayerSave; bank: GuildBankState }
  | { ok: false; reason: string }

export const GUILD_BANK_FULL_REFUSAL = `The guild bank is full (${BANK_SLOT_LIMIT} slots).`
export const GUILD_BANK_UNTRADEABLE_REFUSAL = "That stays with you; it can't be traded."
export const GUILD_BANK_GOLD_REFUSAL = 'Gold stays on you.'
export const GUILD_BANK_EMPTY_REFUSAL = 'That stack is not there.'

export function emptyGuildBank(): GuildBankState {
  return { items: [] }
}

export function guildBankSectionItems(
  bank: GuildBankState,
  section: GuildBankSection,
): GuildBankItem[] {
  return bank.items.filter((row) => row.section === section)
}

function sameStack(row: GuildBankItem, itemId: string, enchantmentId: string | null): boolean {
  return row.itemId === itemId && (row.enchantmentId ?? null) === (enchantmentId ?? null)
}

function addToSection(
  items: GuildBankItem[],
  section: GuildBankSection,
  itemId: string,
  quantity: number,
  enchantmentId: string | null,
  nextId: () => string,
): { ok: true; items: GuildBankItem[] } | { ok: false; reason: string } {
  const sectionRows = items.filter((row) => row.section === section)
  const others = items.filter((row) => row.section !== section)
  if (enchantmentId) {
    if (sectionRows.length >= BANK_SLOT_LIMIT) return { ok: false, reason: GUILD_BANK_FULL_REFUSAL }
    return {
      ok: true,
      items: [
        ...others,
        ...sectionRows,
        { id: nextId(), itemId, quantity, enchantmentId, section },
      ],
    }
  }
  const at = sectionRows.findIndex((row) => sameStack(row, itemId, null))
  if (at >= 0) {
    const next = [...sectionRows]
    next[at] = {
      ...next[at],
      quantity: Math.min(INVENTORY_STACK_MAX, next[at].quantity + quantity),
    }
    return { ok: true, items: [...others, ...next] }
  }
  if (sectionRows.length >= BANK_SLOT_LIMIT) return { ok: false, reason: GUILD_BANK_FULL_REFUSAL }
  return {
    ok: true,
    items: [...others, ...sectionRows, { id: nextId(), itemId, quantity, section }],
  }
}

function takeFromSectionItems(
  items: GuildBankItem[],
  section: GuildBankSection,
  itemId: string,
  quantity: number,
  enchantmentId: string | null,
): { ok: true; items: GuildBankItem[]; taken: number } | { ok: false; reason: string } {
  const sectionRows = items.filter((row) => row.section === section)
  const others = items.filter((row) => row.section !== section)
  const at = sectionRows.findIndex((row) => sameStack(row, itemId, enchantmentId))
  if (at < 0) return { ok: false, reason: GUILD_BANK_EMPTY_REFUSAL }
  const stack = sectionRows[at]
  const want = Math.max(0, Math.floor(quantity))
  if (want <= 0) return { ok: false, reason: 'Choose a quantity.' }
  const taken = Math.min(want, Math.floor(stack.quantity))
  const next = [...sectionRows]
  if (taken >= stack.quantity) next.splice(at, 1)
  else next[at] = { ...stack, quantity: stack.quantity - taken }
  return { ok: true, items: [...others, ...next], taken }
}

export function depositToGuildBank(
  bank: GuildBankState,
  save: PlayerSave,
  inventoryIndex: number,
  quantity: number,
  nextId: () => string,
): GuildBankActionResult {
  if (inventoryIndex < 0 || inventoryIndex >= save.inventory.length) {
    return { ok: false, reason: GUILD_BANK_EMPTY_REFUSAL }
  }
  const stack = save.inventory[inventoryIndex]
  if (stackIsUnbankableGold(stack)) return { ok: false, reason: GUILD_BANK_GOLD_REFUSAL }
  const want = Math.max(0, Math.floor(quantity))
  if (want <= 0) return { ok: false, reason: 'Choose a quantity.' }
  const takenQty = Math.min(want, Math.floor(stack.quantity))
  const added = addToSection(
    bank.items,
    GUILD_BANK_SECTION_MAIN,
    stack.itemId,
    takenQty,
    stack.enchantmentId ?? null,
    nextId,
  )
  if (!added.ok) return added
  const nextInventory = [...save.inventory]
  if (takenQty >= stack.quantity) nextInventory.splice(inventoryIndex, 1)
  else nextInventory[inventoryIndex] = { ...stack, quantity: stack.quantity - takenQty }
  return { ok: true, save: { ...save, inventory: nextInventory }, bank: { items: added.items } }
}

function giveToPlayer(
  bank: GuildBankState,
  save: PlayerSave,
  section: GuildBankSection,
  itemId: string,
  quantity: number,
  enchantmentId: string | null,
): GuildBankActionResult {
  const taken = takeFromSectionItems(bank.items, section, itemId, quantity, enchantmentId)
  if (!taken.ok) return taken
  const added = addItemToInventoryExact(save, itemId, taken.taken, enchantmentId, false)
  if (!added.ok) return { ok: false, reason: added.reason }
  return { ok: true, save: added.save, bank: { items: taken.items } }
}

export function withdrawFromGuildBank(
  bank: GuildBankState,
  save: PlayerSave,
  itemId: string,
  quantity: number,
  enchantmentId: string | null = null,
): GuildBankActionResult {
  return giveToPlayer(bank, save, GUILD_BANK_SECTION_MAIN, itemId, quantity, enchantmentId)
}

export function takeGuildBankUpForGrabs(
  bank: GuildBankState,
  save: PlayerSave,
  itemId: string,
  quantity: number,
  enchantmentId: string | null = null,
): GuildBankActionResult {
  return giveToPlayer(bank, save, GUILD_BANK_SECTION_UP_FOR_GRABS, itemId, quantity, enchantmentId)
}

export function moveGuildBankToUpForGrabs(
  bank: GuildBankState,
  save: PlayerSave,
  itemId: string,
  quantity: number,
  enchantmentId: string | null,
  nextId: () => string,
): GuildBankActionResult {
  const taken = takeFromSectionItems(
    bank.items,
    GUILD_BANK_SECTION_MAIN,
    itemId,
    quantity,
    enchantmentId,
  )
  if (!taken.ok) return taken
  const added = addToSection(
    taken.items,
    GUILD_BANK_SECTION_UP_FOR_GRABS,
    itemId,
    taken.taken,
    enchantmentId,
    nextId,
  )
  if (!added.ok) return added
  return { ok: true, save, bank: { items: added.items } }
}
