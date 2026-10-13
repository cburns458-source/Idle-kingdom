import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const COOKING_SKILL_ID = 'SKL-0007'

/** Recipe → [output item, output quantity, Base Sell Value]. Only fish and meat make 2. */
const COOKING_YIELDS: Record<string, [string, number, number]> = {
  'RCP-0001': ['ITEM-0058', 1, 1], // Baked Potato
  'RCP-0002': ['ITEM-0059', 2, 1], // Cooked Perch
  'RCP-0009': ['ITEM-0066', 2, 2], // Cooked Beef
  'RCP-0061': ['ITEM-0343', 1, 1], // Dried Kelp
  'RCP-0007': ['ITEM-0064', 2, 1], // Cooked Rabbit
  'RCP-0003': ['ITEM-0060', 2, 1], // Cooked Trout
  'RCP-0076': ['ITEM-0424', 2, 1], // Cooked Duck
  'RCP-0063': ['ITEM-0358', 1, 9], // Crawfish Stew
  'RCP-0068': ['ITEM-0364', 1, 1], // Soup Stock
  'RCP-0008': ['ITEM-0065', 2, 7], // Cooked Pheasant
  'RCP-0004': ['ITEM-0061', 2, 6], // Cooked Salmon
  'RCP-0012': ['ITEM-0068', 1, 19], // Pheasant Stew
  'RCP-0077': ['ITEM-0425', 2, 6], // Cooked Boar Meat
  'RCP-0010': ['ITEM-0067', 2, 29], // Cooked Venison
  'RCP-0064': ['ITEM-0359', 1, 12], // Red Crab Stew
  'RCP-0005': ['ITEM-0062', 2, 29], // Cooked Bass
  'RCP-0013': ['ITEM-0069', 1, 108], // Venison Stew
  'RCP-0067': ['ITEM-0362', 2, 4], // Cooked Catfish
  'RCP-0006': ['ITEM-0063', 2, 48], // Cooked Shark
  'RCP-0065': ['ITEM-0360', 1, 120], // Dungeness Stew
  'RCP-0060': ['ITEM-0302', 1, 850], // Squid Noodle Soup
  'RCP-0044': ['ITEM-0391', 2, 53], // Cooked Marlin
  'RCP-0066': ['ITEM-0361', 1, 1330], // Lobster Stew
  'RCP-0070': ['ITEM-0393', 2, 99], // Cooked Swordfish
}

/** Stew recipe → XP. Each stew crafts 1; XP is half of the prior 2-output values, except squid. */
const STEW_XP: Record<string, number> = {
  'RCP-0012': 1400, // Pheasant Stew (was 2800)
  'RCP-0013': 1667, // Venison Stew (was 3333)
  'RCP-0060': 1850, // Squid Noodle Soup (chosen from ~1850; was 8000)
  'RCP-0063': 1068, // Crawfish Stew (was 2135)
  'RCP-0064': 1440, // Red Crab Stew (was 2880)
  'RCP-0065': 1687, // Dungeness Stew (was 3373)
  'RCP-0066': 2001, // Lobster Stew (was 4001)
}

describe('SKL-04 cooking yields', () => {
  const { source } = prepareDatabase(rawDatabase)
  const cooking = source.Recipes.filter((row) => row['Skill ID'] === COOKING_SKILL_ID)
  const sellValue = (itemId: string) =>
    source.Items.find((row) => row['Item ID'] === itemId)?.['Base Sell Value']

  it('covers every Cooking recipe', () => {
    expect(cooking.map((row) => row['Recipe ID']).sort()).toEqual(Object.keys(COOKING_YIELDS).sort())
  })

  it('makes 2 per craft for fish and meat only; stews, baked potato, soup stock, and dried kelp make 1', () => {
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

  it('halves stew XP and sets Squid Noodle Soup to 1850', () => {
    for (const [recipeId, xp] of Object.entries(STEW_XP)) {
      const recipe = cooking.find((row) => row['Recipe ID'] === recipeId)
      expect(recipe?.['XP Reward'], recipeId).toBe(xp)
      const action = source.Actions.find((row) => row['Action ID'] === recipe?.['Action ID'])
      expect(action?.['XP Reward'], recipe?.['Action ID']).toBe(xp)
    }
  })

  it('keeps Baked Potato recipe XP at 300 when yield drops to 1', () => {
    const recipe = cooking.find((row) => row['Recipe ID'] === 'RCP-0001')
    expect(recipe?.['Output Quantity']).toBe(1)
    expect(recipe?.['XP Reward']).toBe(300)
  })

  it('locks approved non-cooking sell values from this balance pass', () => {
    expect(sellValue('ITEM-0051')).toBe(50) // Raw Shark (chosen from ~50)
    expect(sellValue('ITEM-0211')).toBe(210) // Minor Strength Potion
    expect(sellValue('ITEM-0040')).toBe(198) // Bull Horns
  })
})
