import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const COOKING_SKILL_ID = 'SKL-0007'

/** Recipe → [output item, output quantity, Base Sell Value]. Small meat/fish make 1, medium 2, large 3; everything else makes 1. */
const COOKING_YIELDS: Record<string, [string, number, number]> = {
  'RCP-0001': ['ITEM-0058', 1, 1], // Baked potato
  'RCP-0002': ['ITEM-0059', 1, 1], // Perch fillet
  'RCP-0009': ['ITEM-0066', 3, 2], // Beef steak
  'RCP-0061': ['ITEM-0343', 1, 1], // Dried kelp
  'RCP-0007': ['ITEM-0064', 1, 1], // Roast rabbit
  'RCP-0003': ['ITEM-0060', 1, 1], // Trout fillet
  'RCP-0076': ['ITEM-0424', 1, 1], // Roast duck
  'RCP-0063': ['ITEM-0358', 1, 9], // Crawfish stew
  'RCP-0068': ['ITEM-0364', 1, 1], // Soup stock
  'RCP-0008': ['ITEM-0065', 2, 7], // Pheasant breast
  'RCP-0004': ['ITEM-0061', 2, 6], // Salmon steak
  'RCP-0012': ['ITEM-0068', 1, 19], // Pheasant stew
  'RCP-0077': ['ITEM-0425', 3, 6], // Boar chop
  'RCP-0010': ['ITEM-0067', 3, 29], // Venison steak
  'RCP-0064': ['ITEM-0359', 1, 12], // Red crab stew
  'RCP-0005': ['ITEM-0062', 2, 29], // Bass fillet
  'RCP-0013': ['ITEM-0069', 1, 108], // Venison stew
  'RCP-0067': ['ITEM-0362', 2, 4], // Catfish fillet
  'RCP-0006': ['ITEM-0063', 3, 48], // Shark steak
  'RCP-0065': ['ITEM-0360', 1, 120], // Dungeness stew
  'RCP-0060': ['ITEM-0302', 1, 850], // Squid noodle soup
  'RCP-0044': ['ITEM-0391', 3, 53], // Marlin steak
  'RCP-0066': ['ITEM-0361', 1, 1330], // Lobster stew
  'RCP-0070': ['ITEM-0393', 3, 99], // Swordfish steak
}

/** Stew recipe → XP. Each stew crafts 1; XP is half of the prior 2-output values, except squid. */
const STEW_XP: Record<string, number> = {
  'RCP-0012': 1400, // Pheasant stew (was 2800)
  'RCP-0013': 1667, // Venison stew (was 3333)
  'RCP-0060': 1850, // Squid noodle soup (chosen from ~1850; was 8000)
  'RCP-0063': 1068, // Crawfish stew (was 2135)
  'RCP-0064': 1440, // Red crab stew (was 2880)
  'RCP-0065': 1687, // Dungeness stew (was 3373)
  'RCP-0066': 2001, // Lobster stew (was 4001)
}

describe('SKL-04 cooking yields', () => {
  const { source } = prepareDatabase(rawDatabase)
  const cooking = source.Recipes.filter((row) => row['Skill ID'] === COOKING_SKILL_ID)
  const sellValue = (itemId: string) =>
    source.Items.find((row) => row['Item ID'] === itemId)?.['Base Sell Value']

  it('covers every Cooking recipe', () => {
    expect(cooking.map((row) => row['Recipe ID']).sort()).toEqual(Object.keys(COOKING_YIELDS).sort())
  })

  it('sizes meat and fish (small 1, medium 2, large 3); stews, baked potato, soup stock, and dried kelp make 1', () => {
    for (const recipe of cooking) {
      const [itemId, quantity] = COOKING_YIELDS[recipe['Recipe ID']]!
      expect(recipe['Output Item ID'], recipe['Recipe ID']).toBe(itemId)
      expect(recipe['Output Quantity'], recipe['Recipe ID']).toBe(quantity)
    }
  })

  it('locks the approved cooking sell values', () => {
    for (const [recipeId, [itemId, , value]] of Object.entries(COOKING_YIELDS)) {
      expect(sellValue(itemId), recipeId).toBe(value)
    }
  })

  it('halves stew XP and sets Squid noodle soup to 1850', () => {
    for (const [recipeId, xp] of Object.entries(STEW_XP)) {
      const recipe = cooking.find((row) => row['Recipe ID'] === recipeId)
      expect(recipe?.['XP Reward'], recipeId).toBe(xp)
      const action = source.Actions.find((row) => row['Action ID'] === recipe?.['Action ID'])
      expect(action?.['XP Reward'], recipe?.['Action ID']).toBe(xp)
    }
  })

  it('keeps Baked potato recipe XP at 300 when yield drops to 1', () => {
    const recipe = cooking.find((row) => row['Recipe ID'] === 'RCP-0001')
    expect(recipe?.['Output Quantity']).toBe(1)
    expect(recipe?.['XP Reward']).toBe(300)
  })

  it('locks approved non-cooking sell values from this balance pass', () => {
    expect(sellValue('ITEM-0051')).toBe(50) // Raw shark (chosen from ~50)
    expect(sellValue('ITEM-0211')).toBe(210) // Minor strength potion
    expect(sellValue('ITEM-0040')).toBe(198) // Bull horns
  })
})
