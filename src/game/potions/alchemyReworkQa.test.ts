import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { addItemToInventory, resolveActionRewards } from '../activity/rewards'
import { CodexIndex, includeInCodexCatalog } from '../codex/codex'
import { beginCombatSave, resolveCombatRound } from '../combat/engine'
import { DATABASE_CONTENT_VERSION, prepareDatabase } from '../data/loadDatabase'
import {
  equipItemFromInventory,
  equipStackToSlot,
  POTION_SLOT_ID,
  unequipSlot,
} from '../equipment/loadout'
import { equipmentTooltipStatLines } from '../equipment/tooltips'
import {
  applyRelativeDropChance,
  totalRelativeDropChanceBonusPercent,
} from '../loot/dropChance'
import { cancelProductionActivity, beginProductionQueue } from '../production/engine'
import {
  KITCHEN_SCRAPS_ITEM_ID,
  WATER_ITEM_ID,
  alchemyStationLocationIds,
  getRecipe,
  ingredientOwned,
  isAmbientIngredientAt,
  isAtAlchemyStation,
  maxCraftsFromMaterials,
  recipeIngredients,
} from '../production/recipes'
import { migrateSave } from '../save/migrations'
import { createNewSave } from '../save/saveStore'
import { POTION_ACTION_DURATION, SAVE_VERSION, type PlayerSave } from '../save/types'
import { confirmShopOffer } from '../shops/transactions'
import { getShop, playerSellPrice, shopSellsItem, shopStockEntries } from '../shops/shops'
import {
  applyPotionEnemyRoundDamage,
  applyPotionInstantHeal,
  applyPotionRegenHeal,
  isSpeedPotionItem,
  parsePotionEffect,
  potionFlatDamageBonus,
} from './effects'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const EXPECTED_CONTENT_VERSION = '2026-10-15-potion-doses-6'
const NOW_MS = Date.parse('2026-10-15T00:00:00.000Z')
const APOTHECARY = 'LOC-0026'
const KITCHENS = ['LOC-0023', 'LOC-0015', 'LOC-0030', 'LOC-0053', 'LOC-0049']
const CROSSBREEDING_SEEDS = ['ITEM-0331', 'ITEM-0332', 'ITEM-0335', 'ITEM-0338', 'ITEM-0349']

const SIX_DOSE_POTIONS = [
  { itemId: 'ITEM-0070', key: 'luck_potion', name: 'Luck Potion (6)' },
  { itemId: 'ITEM-0071', key: 'speed_potion', name: 'Speed Potion (6)' },
  { itemId: 'ITEM-0072', key: 'strength_potion', name: 'Strength Potion (6)' },
  { itemId: 'ITEM-0073', key: 'poison_potion', name: 'Poison Potion (6)' },
  { itemId: 'ITEM-0210', key: 'minor_luck_potion', name: 'Minor Luck Potion (6)' },
  { itemId: 'ITEM-0211', key: 'minor_strength_potion', name: 'Minor Strength Potion (6)' },
  { itemId: 'ITEM-0212', key: 'greater_strength_potion', name: 'Greater Strength Potion (6)' },
  { itemId: 'ITEM-0213', key: 'masterwork_draught', name: 'Masterwork Draught (6)' },
  { itemId: 'ITEM-0439', key: 'fernleaf_tonic', name: 'Fernleaf Tonic (6)' },
  { itemId: 'ITEM-0440', key: 'mosstole_brew', name: 'Mosstole Brew (6)' },
  { itemId: 'ITEM-0441', key: 'augur_draught', name: 'Augur Draught (6)' },
  { itemId: 'ITEM-0442', key: 'moonblossom_elixir', name: 'Moonblossom Elixir (6)' },
] as const

const HERB_POTIONS = [
  { itemId: 'ITEM-0439', recipeId: 'RCP-0078', herbId: 'ITEM-0031' },
  { itemId: 'ITEM-0440', recipeId: 'RCP-0079', herbId: 'ITEM-0032' },
  { itemId: 'ITEM-0441', recipeId: 'RCP-0080', herbId: 'ITEM-0033' },
  { itemId: 'ITEM-0442', recipeId: 'RCP-0081', herbId: 'ITEM-0207' },
] as const

function seqRandom(values: number[]): () => number {
  let i = 0
  return () => values[Math.min(i++, values.length - 1)]!
}

function versionFromSource(source: string, pattern: RegExp): string {
  const match = source.match(pattern)
  expect(match?.[1]).toBeTruthy()
  return match![1]!
}

function weightedShare(
  entries: Array<{ Weight: number | null; Status: string | null; 'Reward ID / Value': string | null }>,
  itemId: string,
): number {
  const usable = entries.filter(
    (entry) => entry.Status !== 'Needs Data' && typeof entry.Weight === 'number' && entry.Weight > 0,
  )
  const total = usable.reduce((sum, entry) => sum + Number(entry.Weight), 0)
  const weight = usable
    .filter((entry) => entry['Reward ID / Value'] === itemId)
    .reduce((sum, entry) => sum + Number(entry.Weight), 0)
  expect(total).toBeGreaterThan(0)
  return weight / total
}

function withPotion(save: PlayerSave, itemId: string, quantity = 1): PlayerSave {
  return equipStackToSlot(save, POTION_SLOT_ID, itemId, quantity)
}

describe('alchemy rework QA', () => {
  const { launch, source } = prepareDatabase(rawDatabase)
  const launchCodex = new CodexIndex(launch)
  const sourceCodex = new CodexIndex(source)

  const item = (id: string) => launch.Items.find((row) => row['Item ID'] === id)!
  const sourceItem = (id: string) => source.Items.find((row) => row['Item ID'] === id)!
  const equipment = (itemId: string) => launch.Equipment.find((row) => row['Item ID'] === itemId)

  it('content version is 2026-10-15-potion-doses-6 in both loaders', () => {
    const tsSource = readFileSync(resolve(process.cwd(), 'src/game/data/loadDatabase.ts'), 'utf8')
    const dartSource = readFileSync(
      resolve(process.cwd(), 'packages/ik_content/lib/src/load_database.dart'),
      'utf8',
    )
    const tsVersion = versionFromSource(tsSource, /export const DATABASE_CONTENT_VERSION = '([^']+)'/)
    const dartVersion = versionFromSource(
      dartSource,
      /const String databaseContentVersion = '([^']+)';/,
    )
    expect(DATABASE_CONTENT_VERSION).toBe(EXPECTED_CONTENT_VERSION)
    expect(tsVersion).toBe(EXPECTED_CONTENT_VERSION)
    expect(dartVersion).toBe(EXPECTED_CONTENT_VERSION)
  })

  it('the four new potions parse to their tagged effects and last 6 uses', () => {
    const tonic = parsePotionEffect(equipment('ITEM-0439'), 'ITEM-0439')
    expect(tonic?.instantHealMaxHpPercent).toBe(5)
    expect(tonic?.actionsRemaining).toBe(POTION_ACTION_DURATION)
    expect(tonic?.actionsRemaining).toBe(6)
    expect(tonic?.scope).toBe('one_combat_encounter')

    const brew = parsePotionEffect(equipment('ITEM-0440'), 'ITEM-0440')
    expect(brew?.regenMaxHpPercentPerRound).toBe(3)
    expect(brew?.actionsRemaining).toBe(6)

    const draught = parsePotionEffect(equipment('ITEM-0441'), 'ITEM-0441')
    expect(draught?.damageBonusMin).toBe(10)
    expect(draught?.damageBonusMax).toBe(30)
    expect(draught?.actionsRemaining).toBe(6)

    const elixir = parsePotionEffect(equipment('ITEM-0442'), 'ITEM-0442')
    expect(elixir?.damageBonusMin).toBe(30)
    expect(elixir?.damageBonusMax).toBe(90)
    expect(elixir?.actionsRemaining).toBe(6)
  })

  it('Fernleaf Tonic heals 5% of max HP instantly, capped at max HP', () => {
    const effect = parsePotionEffect(equipment('ITEM-0439'), 'ITEM-0439')
    expect(applyPotionInstantHeal(400, 1000, effect)).toBe(450)
    expect(applyPotionInstantHeal(980, 1000, effect)).toBe(1000)
    expect(applyPotionInstantHeal(1000, 1000, effect)).toBe(1000)

    const hurt = { ...withPotion(createNewSave(launch), 'ITEM-0439'), currentHp: 400 }
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0001')!
    const started = beginCombatSave(launch, hurt, action, enemy)
    expect(started.currentHp).toBe(400 + Math.floor(started.maxHp * 0.05))
    expect(started.currentHp).toBeLessThanOrEqual(started.maxHp)
    expect(started.activePotionEffect?.actionsRemaining).toBe(6)
  })

  it('Mosstole Brew heals 3% of max HP each combat round, capped at max HP', () => {
    const effect = parsePotionEffect(equipment('ITEM-0440'), 'ITEM-0440')
    expect(applyPotionRegenHeal(400, 1000, effect)).toBe(430)
    expect(applyPotionRegenHeal(990, 1000, effect)).toBe(1000)
    expect(applyPotionRegenHeal(1000, 1000, effect)).toBe(1000)

    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0001')!
    const started = beginCombatSave(
      launch,
      { ...withPotion(createNewSave(launch), 'ITEM-0440'), currentHp: 400 },
      action,
      enemy,
    )
    const before = started.currentHp
    const round = resolveCombatRound(launch, started, enemy, started.combatEnemyHp ?? 0, () => 0)
    expect(round.playerHpAfterPlayer).toBe(
      applyPotionRegenHeal(before, started.maxHp, started.activePotionEffect),
    )
    expect(round.playerHpAfterPlayer).toBeLessThanOrEqual(started.maxHp)
    expect(started.activePotionEffect?.actionsRemaining).toBe(6)
  })

  it('Augur Draught adds +10 min / +30 max flat damage', () => {
    const save = withPotion(createNewSave(launch), 'ITEM-0441')
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0001')!
    const started = beginCombatSave(launch, save, action, enemy)
    expect(started.activePotionEffect?.damageBonusMin).toBe(10)
    expect(started.activePotionEffect?.damageBonusMax).toBe(30)
    expect(potionFlatDamageBonus(started.activePotionEffect)).toEqual({ min: 10, max: 30 })
    expect(started.activePotionEffect?.actionsRemaining).toBe(6)
  })

  it('Moonblossom Elixir adds +30 min / +90 max flat damage', () => {
    const save = withPotion(createNewSave(launch), 'ITEM-0442')
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0001')!
    const started = beginCombatSave(launch, save, action, enemy)
    expect(started.activePotionEffect?.damageBonusMin).toBe(30)
    expect(started.activePotionEffect?.damageBonusMax).toBe(90)
    expect(potionFlatDamageBonus(started.activePotionEffect)).toEqual({ min: 30, max: 90 })
    expect(started.activePotionEffect?.actionsRemaining).toBe(6)
  })

  it('every 6-dose potion display name ends in (6) and keeps its id and key', () => {
    for (const potion of SIX_DOSE_POTIONS) {
      const row = item(potion.itemId)
      expect(row['Item ID'], potion.itemId).toBe(potion.itemId)
      expect(row['Internal Key'], potion.itemId).toBe(potion.key)
      expect(row['Display Name'], potion.itemId).toBe(potion.name)
      expect(row['Display Name']?.endsWith('(6)'), potion.itemId).toBe(true)
    }
  })

  it('the four new recipes use exactly 1 herb + Water x1', () => {
    for (const potion of HERB_POTIONS) {
      const ingredients = recipeIngredients(getRecipe(launch, potion.recipeId)!)
      expect(ingredients, potion.recipeId).toHaveLength(2)
      expect(ingredients, potion.recipeId).toContainEqual({ itemId: potion.herbId, quantity: 1 })
      expect(ingredients, potion.recipeId).toContainEqual({ itemId: WATER_ITEM_ID, quantity: 1 })
    }
  })

  it('water is free and unconsumed at every Alchemy station and kitchen', () => {
    const base = createNewSave(launch)
    const stations = [...alchemyStationLocationIds(launch)]
    expect(stations.sort()).toEqual(['LOC-0026', 'LOC-0030'])
    for (const loc of stations) {
      const save = { ...base, currentLocationId: loc }
      expect(isAmbientIngredientAt(launch, save, WATER_ITEM_ID), loc).toBe(true)
      expect(ingredientOwned(launch, save, WATER_ITEM_ID), loc).toBe(Number.POSITIVE_INFINITY)
    }
    for (const loc of KITCHENS) {
      const save = { ...base, currentLocationId: loc }
      expect(ingredientOwned(launch, save, WATER_ITEM_ID), loc).toBe(Number.POSITIVE_INFINITY)
    }
    expect(ingredientOwned(launch, { ...base, currentLocationId: 'LOC-0001' }, WATER_ITEM_ID)).toBe(0)
  })

  it('Kitchen Scraps are free in kitchens, including Manor and Giant Camp, but not at the apothecary', () => {
    const base = createNewSave(launch)
    for (const loc of KITCHENS) {
      const save = { ...base, currentLocationId: loc }
      expect(ingredientOwned(launch, save, KITCHEN_SCRAPS_ITEM_ID), loc).toBe(Number.POSITIVE_INFINITY)
    }
    const apothecary = { ...base, currentLocationId: APOTHECARY }
    expect(isAtAlchemyStation(launch, apothecary)).toBe(true)
    expect(ingredientOwned(launch, apothecary, KITCHEN_SCRAPS_ITEM_ID)).toBe(0)
    expect(isAmbientIngredientAt(launch, apothecary, KITCHEN_SCRAPS_ITEM_ID)).toBe(false)
  })

  it('cancelling a queued brew refunds everything except water', () => {
    const tonic = getRecipe(launch, 'RCP-0078')!
    let save = { ...createNewSave(launch), currentLocationId: APOTHECARY }
    save = addItemToInventory(save, 'ITEM-0031', 5)
    save = addItemToInventory(save, WATER_ITEM_ID, 2)
    expect(maxCraftsFromMaterials(launch, save, tonic)).toBe(5)

    const queued = beginProductionQueue(launch, save, 'ACT-0020', 'RCP-0078', 3)
    expect(queued.ok).toBe(true)
    if (!queued.ok) return
    expect(queued.save.inventory.find((stack) => stack.itemId === 'ITEM-0031')?.quantity).toBe(2)
    expect(queued.save.inventory.find((stack) => stack.itemId === WATER_ITEM_ID)?.quantity).toBe(2)

    const cancelled = cancelProductionActivity(launch, queued.save)
    expect(cancelled.inventory.find((stack) => stack.itemId === 'ITEM-0031')?.quantity).toBe(5)
    expect(cancelled.inventory.find((stack) => stack.itemId === WATER_ITEM_ID)?.quantity).toBe(2)
  })

  it('Apothecary buys the four new potions but does not sell them', () => {
    const shop = getShop(launch, 'SHP-0010')!
    const potions = [
      { itemId: 'ITEM-0439', price: 4 },
      { itemId: 'ITEM-0440', price: 8 },
      { itemId: 'ITEM-0441', price: 40 },
      { itemId: 'ITEM-0442', price: 240 },
    ]
    const stock = shopStockEntries(shop).map((entry) => entry.itemId)
    let save = { ...createNewSave(launch), currentLocationId: shop['Location ID']!, gold: 0 }
    for (const [index, potion] of potions.entries()) {
      expect(shop[`Entry ${index + 7} Mode`]).toBe('Buy')
      expect(shop[`Entry ${index + 7} Item ID`]).toBe(potion.itemId)
      expect(stock, potion.itemId).not.toContain(potion.itemId)
      expect(shopSellsItem(shop, potion.itemId), potion.itemId).toBe(false)
      expect(playerSellPrice(launch, shop, potion.itemId)).toBe(potion.price)

      const buyFromShop = confirmShopOffer(
        launch,
        { ...save, gold: 10_000 },
        'SHP-0010',
        { buys: [{ itemId: potion.itemId, quantity: 1 }], sells: [] },
        NOW_MS,
      )
      expect(buyFromShop.ok, potion.itemId).toBe(false)

      save = addItemToInventory(save, potion.itemId, 1)
      const sold = confirmShopOffer(
        launch,
        save,
        'SHP-0010',
        { buys: [], sells: [{ itemId: potion.itemId, quantity: 1 }] },
        NOW_MS,
      )
      expect(sold.ok, potion.itemId).toBe(true)
      if (!sold.ok) return
      save = sold.save
    }
    expect(save.gold).toBe(4 + 8 + 40 + 240)
  })

  it('Strength sells for ~260 above Minor Strength; Minor Luck ~120 below Luck', () => {
    expect(item('ITEM-0072')['Base Sell Value']).toBe(260)
    expect(item('ITEM-0211')['Base Sell Value']).toBe(210)
    expect(item('ITEM-0072')['Base Sell Value']!).toBeGreaterThan(item('ITEM-0211')['Base Sell Value']!)
    expect(item('ITEM-0210')['Base Sell Value']).toBe(120)
    expect(item('ITEM-0070')['Base Sell Value']).toBe(294)
    expect(item('ITEM-0210')['Base Sell Value']!).toBeLessThan(item('ITEM-0070')['Base Sell Value']!)
  })

  it('pheasant feathers drop about 15% per hunt', () => {
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0017')!
    expect(action['Drop Chance']).toBe(60)
    expect(action['Reward Table ID']).toBe('RWT-0052')
    const entries = launch.RewardEntries.filter((row) => row['Reward Table ID'] === 'RWT-0052')
    expect(weightedShare(entries, 'ITEM-0039') * 60).toBeCloseTo(15, 5)
  })

  it('Troll Tooth drops about 11.2% on the Rock Troll table', () => {
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0005')!
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0007')!
    expect(action['Reward Table ID']).toBe('RWT-0198')
    expect(enemy['Reward Table ID']).toBe('RWT-0198')
    expect(action['Drop Chance']).toBe(32)
    expect(enemy['Drop Chance']).toBe(32)
    const mother = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0023')!
    expect(mother['Reward Table ID']).toBe('RWT-0012')
    const entries = launch.RewardEntries.filter((row) => row['Reward Table ID'] === 'RWT-0198')
    expect(weightedShare(entries, 'ITEM-0201') * 32).toBeCloseTo(11.2, 5)
  })

  it('Goblin Scouts drop Wooden Dagger, not Bronze Dagger', () => {
    const entries = launch.RewardEntries.filter((row) => row['Reward Table ID'] === 'RWT-0003')
    const rwe0006 = entries.find((row) => row['Reward Entry ID'] === 'RWE-0006')!
    expect(rwe0006['Reward ID / Value']).toBe('ITEM-0125')
    expect(item('ITEM-0125')['Display Name']).toBe('Wooden Dagger')
    expect(entries.some((row) => row['Reward ID / Value'] === 'ITEM-0225')).toBe(false)
    const warrior = launch.RewardEntries.filter((row) => row['Reward Table ID'] === 'RWT-0004')
    expect(warrior.some((row) => row['Reward ID / Value'] === 'ITEM-0225')).toBe(true)
  })

  it('every drop bonus applies when rolling combat loot', () => {
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0003')!
    expect(action['Drop Chance']).toBe(25)
    const base = createNewSave(launch)
    const boosted: PlayerSave = {
      ...base,
      activePotionEffect: {
        scope: 'one_action',
        itemId: 'ITEM-0070',
        damageBonusPercent: null,
        enemyMaxHpDamagePercent: null,
        relativeDropChanceBonusPercent: 25,
        baseDurationReductionPercent: null,
        instantHealMaxHpPercent: null,
        regenMaxHpPercentPerRound: null,
        damageBonusMin: null,
        damageBonusMax: null,
        actionsRemaining: 6,
      },
      equipment: {
        ...base.equipment,
        slots: {
          ...base.equipment.slots,
          'SLOT-0008': { itemId: 'ITEM-0180', quantity: 1 },
        },
      },
    }
    expect(totalRelativeDropChanceBonusPercent(launch, boosted)).toBe(40)
    expect(applyRelativeDropChance(25, 40)).toBe(35)

    const without = resolveActionRewards(launch, base, action, seqRandom([0.3, 0]))
    const withBonus = resolveActionRewards(launch, boosted, action, seqRandom([0.3, 0]))
    expect(without.loot).toEqual([])
    expect(withBonus.loot.length).toBeGreaterThan(0)
  })

  it('Speed does not apply to Alchemy, but Masterwork still does', () => {
    const recipe = launch.Recipes.find((row) => row['Recipe ID'] === 'RCP-0078')!
    const baseMs = recipe['Base Duration Seconds'] * 1000
    let herbs = { ...createNewSave(launch), currentLocationId: APOTHECARY, inventory: [] as PlayerSave['inventory'] }
    herbs = addItemToInventory(herbs, 'ITEM-0031', 4)

    const speed = beginProductionQueue(launch, withPotion(herbs, 'ITEM-0071'), 'ACT-0020', 'RCP-0078', 1)
    expect(speed.ok).toBe(true)
    if (!speed.ok) return
    expect(speed.save.equipment.slots[POTION_SLOT_ID]?.itemId).toBe('ITEM-0071')
    expect(speed.save.activePotionEffect).toBeNull()
    expect(speed.save.actionDurationMs).toBe(baseMs)
    expect(isSpeedPotionItem(launch, 'ITEM-0071')).toBe(true)

    const masterwork = beginProductionQueue(
      launch,
      withPotion(herbs, 'ITEM-0213'),
      'ACT-0020',
      'RCP-0078',
      1,
    )
    expect(masterwork.ok).toBe(true)
    if (!masterwork.ok) return
    expect(masterwork.save.equipment.slots[POTION_SLOT_ID]).toBeNull()
    expect(masterwork.save.activePotionEffect?.itemId).toBe('ITEM-0213')
    expect(masterwork.save.actionDurationMs).toBe(Math.floor(baseMs * 0.85))
  })

  it('unequip and swap discard leftover doses of an active potion', () => {
    let save = addItemToInventory(createNewSave(launch), 'ITEM-0070', 4)
    const equipped = equipItemFromInventory(launch, save, 'ITEM-0070')
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return
    save = {
      ...equipped.save,
      activePotionEffect: {
        scope: 'one_action',
        itemId: 'ITEM-0070',
        damageBonusPercent: null,
        enemyMaxHpDamagePercent: null,
        relativeDropChanceBonusPercent: 25,
        baseDurationReductionPercent: null,
        instantHealMaxHpPercent: null,
        regenMaxHpPercentPerRound: null,
        damageBonusMin: null,
        damageBonusMax: null,
        actionsRemaining: 5,
      },
    }
    const bankBefore = save.bank ?? []
    const unequipped = unequipSlot(save, POTION_SLOT_ID)
    expect(unequipped.ok).toBe(true)
    if (!unequipped.ok) return
    expect(unequipped.save.equipment.slots[POTION_SLOT_ID]).toBeNull()
    expect(unequipped.save.activePotionEffect).toBeNull()
    expect(unequipped.save.inventory.find((stack) => stack.itemId === 'ITEM-0070')).toBeUndefined()
    expect(unequipped.save.bank ?? []).toEqual(bankBefore)

    let swapSave = addItemToInventory(createNewSave(launch), 'ITEM-0070', 3)
    swapSave = addItemToInventory(swapSave, 'ITEM-0071', 2)
    const first = equipItemFromInventory(launch, swapSave, 'ITEM-0070')
    expect(first.ok).toBe(true)
    if (!first.ok) return
    swapSave = {
      ...first.save,
      activePotionEffect: {
        scope: 'one_action',
        itemId: 'ITEM-0070',
        damageBonusPercent: null,
        enemyMaxHpDamagePercent: null,
        relativeDropChanceBonusPercent: 25,
        baseDurationReductionPercent: null,
        instantHealMaxHpPercent: null,
        regenMaxHpPercentPerRound: null,
        damageBonusMin: null,
        damageBonusMax: null,
        actionsRemaining: 4,
      },
    }
    const swapped = equipItemFromInventory(launch, swapSave, 'ITEM-0071')
    expect(swapped.ok).toBe(true)
    if (!swapped.ok) return
    expect(swapped.save.equipment.slots[POTION_SLOT_ID]?.itemId).toBe('ITEM-0071')
    expect(swapped.save.activePotionEffect).toBeNull()
    expect(swapped.save.inventory.find((stack) => stack.itemId === 'ITEM-0070')).toBeUndefined()
  })

  it('renamed potion items keep ids so old saves still resolve them', () => {
    expect(isSpeedPotionItem(launch, 'ITEM-0071')).toBe(true)
    expect(isSpeedPotionItem(launch, 'ITEM-0070')).toBe(false)
    const created = createNewSave(launch)
    const loaded = migrateSave({
      ...created,
      inventory: SIX_DOSE_POTIONS.map((potion) => ({ itemId: potion.itemId, quantity: 1 })),
    })
    expect(loaded.saveVersion).toBe(SAVE_VERSION)
    for (const potion of SIX_DOSE_POTIONS) {
      expect(
        loaded.inventory.some((stack) => stack.itemId === potion.itemId && stack.quantity === 1),
        potion.itemId,
      ).toBe(true)
      expect(item(potion.itemId)['Internal Key'], potion.itemId).toBe(potion.key)
    }
  })

  it('save v64 to v65 migration keeps an active Poison potion', () => {
    const created = createNewSave(launch)
    const migrated = migrateSave({
      ...created,
      saveVersion: 64,
      activePotionEffect: {
        scope: 'one_combat_encounter',
        itemId: 'ITEM-0073',
        damageBonusPercent: null,
        enemyMaxHpDamagePercent: 10,
        relativeDropChanceBonusPercent: null,
        baseDurationReductionPercent: null,
        actionsRemaining: 6,
      },
    } as PlayerSave)
    expect(migrated.saveVersion).toBe(65)
    expect(migrated.activePotionEffect?.itemId).toBe('ITEM-0073')
    expect(migrated.activePotionEffect?.enemyMaxHpDamagePercent).toBe(10)
    expect(migrated.activePotionEffect?.actionsRemaining).toBe(6)
    expect(migrated.activePotionEffect?.instantHealMaxHpPercent).toBeNull()
    expect(applyPotionEnemyRoundDamage(1000, 1000, migrated.activePotionEffect)).toBe(900)
  })

  it('codex and tooltip effect lines are generated with 6 uses', () => {
    expect(equipmentTooltipStatLines(equipment('ITEM-0439'))).toEqual(['Heals 5%, 6 uses'])
    expect(equipmentTooltipStatLines(equipment('ITEM-0440'))).toEqual(['Heals 3% each round, 6 uses'])
    expect(equipmentTooltipStatLines(equipment('ITEM-0441'))).toEqual(['+10–30 damage, 6 uses'])
    expect(equipmentTooltipStatLines(equipment('ITEM-0442'))).toEqual(['+30–90 damage, 6 uses'])
    expect(launchCodex.item('ITEM-0439')?.statLines).toEqual(['Heals 5%, 6 uses'])
    expect(launchCodex.item('ITEM-0440')?.statLines).toEqual(['Heals 3% each round, 6 uses'])
    expect(launchCodex.item('ITEM-0441')?.statLines).toEqual(['+10–30 damage, 6 uses'])
    expect(launchCodex.item('ITEM-0442')?.statLines).toEqual(['+30–90 damage, 6 uses'])
    for (const potion of SIX_DOSE_POTIONS) {
      const lines = equipmentTooltipStatLines(equipment(potion.itemId))
      expect(lines.some((line) => line.includes('6 uses')), potion.itemId).toBe(true)
    }
  })

  it('Willow Log, Cinnamon Log, and Cooked Baby Giant Squid are hidden', () => {
    expect(sourceItem('ITEM-0383')['Display Name']).toBe('Willow Log')
    expect(sourceItem('ITEM-0384')['Display Name']).toBe('Cinnamon Log')
    expect(sourceItem('ITEM-0192')['Display Name']).toBe('Cooked Baby Giant Squid')
    expect(sourceItem('ITEM-0383').Retired).toBe(true)
    expect(sourceItem('ITEM-0384').Retired).toBe(true)
    expect(sourceItem('ITEM-0192').Retired).toBe(true)
    expect(includeInCodexCatalog(sourceItem('ITEM-0383'))).toBe(false)
    expect(includeInCodexCatalog(sourceItem('ITEM-0384'))).toBe(false)
    expect(includeInCodexCatalog(sourceItem('ITEM-0192'))).toBe(false)
    expect(launchCodex.items.some((row) => row.itemId === 'ITEM-0383')).toBe(false)
    expect(launchCodex.items.some((row) => row.itemId === 'ITEM-0384')).toBe(false)
    expect(launchCodex.items.some((row) => row.itemId === 'ITEM-0192')).toBe(false)
    expect(sourceCodex.items.some((row) => row.itemId === 'ITEM-0384')).toBe(false)
    expect(launchCodex.itemsMatching(undefined, 'cinnamon log').map((row) => row.itemId)).not.toContain(
      'ITEM-0384',
    )
  })

  it('five crossbreeding seeds show Crossbreeding seeds and are not retired', () => {
    for (const itemId of CROSSBREEDING_SEEDS) {
      const row = sourceItem(itemId)
      expect(row['Obtained From'], itemId).toBe('Crossbreeding seeds')
      expect(row.Retired, itemId).not.toBe(true)
      expect(includeInCodexCatalog(row), itemId).toBe(true)
      expect(
        (sourceCodex.item(itemId)?.obtainedFrom ?? [])
          .filter((entry) => entry.kind === 'note')
          .map((entry) => entry.title),
        itemId,
      ).toEqual(['Crossbreeding seeds'])
    }
  })
})
