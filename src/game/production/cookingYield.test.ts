import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const COOKING_SKILL_ID = 'SKL-0007'

/** SKL-04: recipe → [output item, output quantity, Base Sell Value, sell value before SKL-04]. */
const COOKING_YIELDS: Record<string, [string, number, number, number]> = {
  'RCP-0001': ['ITEM-0058', 2, 1, 1], // Baked Potato
  'RCP-0002': ['ITEM-0059', 2, 1, 1], // Cooked Perch
  'RCP-0009': ['ITEM-0066', 2, 2, 4], // Cooked Beef
  'RCP-0061': ['ITEM-0343', 1, 1, 1], // Dried Kelp
  'RCP-0007': ['ITEM-0064', 2, 1, 3], // Cooked Rabbit
  'RCP-0003': ['ITEM-0060', 2, 1, 2], // Cooked Trout
  'RCP-0076': ['ITEM-0424', 2, 1, 2], // Cooked Duck
  'RCP-0063': ['ITEM-0358', 2, 1, 3], // Crawfish Stew
  'RCP-0068': ['ITEM-0364', 1, 1, 1], // Soup Stock
  'RCP-0008': ['ITEM-0065', 2, 7, 14], // Cooked Pheasant
  'RCP-0004': ['ITEM-0061', 2, 6, 12], // Cooked Salmon
  'RCP-0012': ['ITEM-0068', 2, 19, 39], // Pheasant Stew
  'RCP-0077': ['ITEM-0425', 2, 6, 12], // Cooked Boar Meat
  'RCP-0010': ['ITEM-0067', 2, 29, 58], // Cooked Venison
  'RCP-0064': ['ITEM-0359', 2, 12, 24], // Red Crab Stew
  'RCP-0005': ['ITEM-0062', 2, 29, 58], // Cooked Bass
  'RCP-0013': ['ITEM-0069', 2, 108, 216], // Venison Stew
  'RCP-0067': ['ITEM-0362', 2, 4, 9], // Cooked Catfish
  'RCP-0006': ['ITEM-0063', 2, 301, 602], // Cooked Shark
  'RCP-0065': ['ITEM-0360', 2, 53, 106], // Dungeness Stew
  'RCP-0060': ['ITEM-0302', 2, 415, 830], // Squid Noodle Soup
  'RCP-0044': ['ITEM-0391', 2, 53, 106], // Cooked Marlin
  'RCP-0066': ['ITEM-0361', 2, 203, 406], // Lobster Stew
  'RCP-0070': ['ITEM-0393', 2, 99, 198], // Cooked Swordfish
}

describe('SKL-04 cooking yields', () => {
  const { source } = prepareDatabase(rawDatabase)
  const cooking = source.Recipes.filter((row) => row['Skill ID'] === COOKING_SKILL_ID)
  const sellValue = (itemId: string) =>
    source.Items.find((row) => row['Item ID'] === itemId)?.['Base Sell Value']

  it('covers every Cooking recipe', () => {
    expect(cooking.map((row) => row['Recipe ID']).sort()).toEqual(Object.keys(COOKING_YIELDS).sort())
  })

  it('makes 2 per craft at every level, except Soup Stock and Dried Kelp at 1', () => {
    for (const recipe of cooking) {
      const [itemId, quantity] = COOKING_YIELDS[recipe['Recipe ID']]!
      expect(recipe['Output Item ID'], recipe['Recipe ID']).toBe(itemId)
      expect(recipe['Output Quantity'], recipe['Recipe ID']).toBe(quantity)
    }
  })

  it('halves the sell value of doubled food, rounding down to a minimum of 1', () => {
    for (const [recipeId, [itemId, quantity, value, before]] of Object.entries(COOKING_YIELDS)) {
      expect(value, recipeId).toBe(quantity === 2 ? Math.max(1, Math.floor(before / 2)) : before)
      expect(sellValue(itemId), recipeId).toBe(value)
    }
  })
})
