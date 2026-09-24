import { addItemToInventoryExact } from '../activity/rewards'
import type { GameDatabase, ItemRow, NpcRow } from '../data/types'
import { projectFacilityIdForLookup } from '../production/recipes'
import type { InventoryStack, PlayerSave } from '../save/types'

export const LEATHER_ITEM_ID = 'ITEM-0045'
export const TANNER_GOLD_PER_LEATHER = 2
export const CRAFTING_WORKSHOP_FACILITY_ID = 'FAC-0003'

/** Leather produced per hide, keyed by Internal Key. */
export const HIDE_LEATHER_YIELDS: Record<string, number> = {
  cow_hide: 3,
  goat_hide: 2,
  elk_hide: 3,
  boar_hide: 2,
  great_stag_hide: 4,
  moonhorn_hide: 4,
}

export interface TannerHideOption {
  itemId: string
  displayName: string
  owned: number
  leatherEach: number
}

export interface TannerOffer {
  prompt: string
  feeEach: number
  leatherItemId: string
  hides: TannerHideOption[]
}

export interface TannerQuote {
  leather: number
  gold: number
  hideCount: number
}

function stackQuantity(stack: InventoryStack): number {
  return Math.max(0, Math.floor(Number(stack.quantity) || 0))
}

function quantityIn(stacks: InventoryStack[] | undefined, itemId: string): number {
  return (stacks ?? []).reduce((sum, stack) => {
    if (stack.itemId !== itemId) return sum
    return sum + stackQuantity(stack)
  }, 0)
}

function ownedQuantity(save: PlayerSave, itemId: string): number {
  return quantityIn(save.inventory, itemId) + quantityIn(save.bank, itemId)
}

function takeFromStacks(
  stacks: InventoryStack[],
  itemId: string,
  need: number,
): { stacks: InventoryStack[]; remaining: number } {
  let remaining = need
  const next: InventoryStack[] = []
  for (const stack of stacks) {
    if (stack.itemId !== itemId || remaining <= 0) {
      next.push({ ...stack })
      continue
    }
    const have = stackQuantity(stack)
    const take = Math.min(have, remaining)
    remaining -= take
    const left = have - take
    if (left > 0) next.push({ ...stack, quantity: left })
  }
  return { stacks: next, remaining }
}

function removeHides(
  save: PlayerSave,
  ingredients: { itemId: string; quantity: number }[],
): PlayerSave | null {
  let inventory = save.inventory.map((stack) => ({ ...stack }))
  let bank = (save.bank ?? []).map((stack) => ({ ...stack }))
  for (const row of ingredients) {
    const fromBag = takeFromStacks(inventory, row.itemId, row.quantity)
    inventory = fromBag.stacks
    if (fromBag.remaining <= 0) continue
    const fromBank = takeFromStacks(bank, row.itemId, fromBag.remaining)
    if (fromBank.remaining > 0) return null
    bank = fromBank.stacks
  }
  return { ...save, inventory, bank }
}

function hideInternalKey(item: ItemRow): string | null {
  const key = item['Internal Key']
  if (typeof key === 'string' && key.endsWith('_hide')) return key
  return null
}

export function isTannerNpc(npc: NpcRow | null | undefined): boolean {
  if (!npc) return false
  return (npc.Role ?? '').toLowerCase() === 'tanner'
}

export function isCraftingWorkshopLocation(db: GameDatabase, locationId: string): boolean {
  return db.Facilities.some((facility) => {
    if (facility['Location ID'] !== locationId) return false
    if (projectFacilityIdForLookup(facility['Facility ID']) === CRAFTING_WORKSHOP_FACILITY_ID) {
      return true
    }
    const key = facility['Internal Key']
    return typeof key === 'string' && key.endsWith('crafting_workshop')
  })
}

export function tannerNpcAtLocation(db: GameDatabase, locationId: string): NpcRow | null {
  if (!isCraftingWorkshopLocation(db, locationId)) return null
  const existing = db.NPCs.find((npc) => npc['Location ID'] === locationId && isTannerNpc(npc))
  if (existing) return existing
  return {
    'NPC ID': `NPC-TANNER-${locationId}`,
    'Internal Key': `tanner_${locationId.toLowerCase()}`,
    'Display Name': 'Tanner',
    'Location ID': locationId,
    Role: 'Tanner',
    Status: 'Planned',
    'Release Phase': 'Launch',
    Description: 'Tans animal hides into leather at the crafting workshop, for a small gold fee.',
    Notes: 'Trades hides for leather. 2 gold per leather produced.',
  }
}

export function leatherPerHide(item: ItemRow): number {
  const key = hideInternalKey(item)
  if (!key) return 0
  const listed = HIDE_LEATHER_YIELDS[key]
  if (typeof listed === 'number' && listed > 0) return listed
  return 1
}

export function tannerHideOptions(db: GameDatabase, save: PlayerSave): TannerHideOption[] {
  const options: TannerHideOption[] = []
  for (const item of db.Items) {
    const leatherEach = leatherPerHide(item)
    if (leatherEach <= 0) continue
    const owned = ownedQuantity(save, item['Item ID'])
    if (owned <= 0) continue
    options.push({
      itemId: item['Item ID'],
      displayName: item['Display Name'],
      owned,
      leatherEach,
    })
  }
  options.sort((a, b) => a.displayName.localeCompare(b.displayName))
  return options
}

export function tannerOffer(db: GameDatabase, save: PlayerSave): TannerOffer {
  const hides = tannerHideOptions(db, save)
  return {
    prompt:
      hides.length === 0
        ? 'Bring me animal hides and a little gold. I will tan them into leather.'
        : 'Which hides should I tan?',
    feeEach: TANNER_GOLD_PER_LEATHER,
    leatherItemId: LEATHER_ITEM_ID,
    hides,
  }
}

export function quoteTannerJob(
  db: GameDatabase,
  save: PlayerSave,
  quantities: Record<string, number>,
): TannerQuote {
  let leather = 0
  let hideCount = 0
  const yields = new Map(db.Items.map((item) => [item['Item ID'], leatherPerHide(item)]))
  for (const [itemId, raw] of Object.entries(quantities)) {
    const want = Math.max(0, Math.floor(Number(raw) || 0))
    if (want <= 0) continue
    const owned = ownedQuantity(save, itemId)
    const take = Math.min(want, owned)
    const each = yields.get(itemId) ?? 0
    if (each <= 0 || take <= 0) continue
    hideCount += take
    leather += take * each
  }
  return { leather, gold: leather * TANNER_GOLD_PER_LEATHER, hideCount }
}

export function confirmTannerJob(
  db: GameDatabase,
  save: PlayerSave,
  npc: NpcRow,
  quantities: Record<string, number>,
): { ok: true; save: PlayerSave; message: string } | { ok: false; reason: string } {
  if (!isTannerNpc(npc)) return { ok: false, reason: 'This person does not tan hides.' }
  if (save.currentLocationId !== npc['Location ID'] || !isCraftingWorkshopLocation(db, npc['Location ID'])) {
    return { ok: false, reason: 'Speak with the tanner at a crafting workshop.' }
  }

  const quote = quoteTannerJob(db, save, quantities)
  if (quote.leather <= 0) return { ok: false, reason: 'Select some hides first.' }
  if (save.gold < quote.gold) {
    return { ok: false, reason: `Need ${quote.gold.toLocaleString()} gold.` }
  }

  const yields = new Map(db.Items.map((item) => [item['Item ID'], leatherPerHide(item)]))
  const ingredients = Object.entries(quantities)
    .map(([itemId, raw]) => ({
      itemId,
      quantity: Math.min(ownedQuantity(save, itemId), Math.max(0, Math.floor(Number(raw) || 0))),
    }))
    .filter((row) => row.quantity > 0 && (yields.get(row.itemId) ?? 0) > 0)

  const spentItems = removeHides(save, ingredients)
  if (!spentItems) return { ok: false, reason: 'You do not have those hides.' }
  const spentGold = { ...spentItems, gold: spentItems.gold - quote.gold }
  const granted = addItemToInventoryExact(spentGold, LEATHER_ITEM_ID, quote.leather, null, false, db)
  if (!granted.ok) return granted

  const hideWord = quote.hideCount === 1 ? 'hide' : 'hides'
  return {
    ok: true,
    save: granted.save,
    message: `Tanned ${quote.hideCount} ${hideWord} into ${quote.leather} leather for ${quote.gold} gold.`,
  }
}
