import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { canKnowRecipe, getRecipe } from '../production/recipes'
import { createNewSave } from '../save/saveStore'
import { recipeBookView } from './bookView'
import {
  isAutomaticLevelUnlock,
  knowsRecipe,
  listRecipeBookEntries,
  recipeBookForSkill,
  unlockRecipeId,
} from './knowledge'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('recipe knowledge', () => {
  it('gates automatic recipes by proficiency and unlocks explicit IDs', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    const luck = getRecipe(launch, 'RCP-0053')!
    expect(canKnowRecipe(save, launch, luck)).toBe(false)

    const starter = launch.Recipes.find(
      (recipe) =>
        recipe['Proficiency Level'] === 1 &&
        (recipe['Knowledge Source'] ?? '').toLowerCase().includes('automatic'),
    )
    if (starter) {
      expect(knowsRecipe(save, launch, starter['Recipe ID'])).toBe(true)
    }

    save = unlockRecipeId(save, 'RCP-0053')
    expect(knowsRecipe(save, launch, 'RCP-0053')).toBe(true)
    expect(canKnowRecipe(save, launch, luck)).toBe(true)
  })

  it('lists recipes and projects in the recipe book', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const entries = listRecipeBookEntries(save, launch)
    expect(entries.some((entry) => entry.kind === 'recipe')).toBe(true)
    expect(entries.some((entry) => entry.known)).toBe(true)
    const gloves = entries.find((entry) => entry.name === "Falconer's Gloves")
    expect(gloves?.materials).toContain('Great Stag Hide')
    expect(gloves?.materials).not.toContain('Ancient Binding')
    expect(gloves?.materials).not.toContain('ITEM-0290')
    const lockpicks = launch.Recipes.find((recipe) => recipe['Recipe ID'] === 'RCP-0062')
    expect(lockpicks).toBeDefined()
    expect(isAutomaticLevelUnlock(lockpicks!)).toBe(true)
    const crafter = {
      ...save,
      skills: save.skills.map((skill) =>
        skill.skillId === 'SKL-0009' ? { ...skill, level: 20 } : skill,
      ),
    }
    expect(knowsRecipe(crafter, launch, 'RCP-0062')).toBe(true)
    expect(canKnowRecipe(crafter, launch, lockpicks!)).toBe(false)
    const thiefCrafter = {
      ...save,
      skills: save.skills.map((skill) =>
        skill.skillId === 'SKL-0009' || skill.skillId === 'SKL-0015'
          ? { ...skill, level: 20 }
          : skill,
      ),
    }
    expect(canKnowRecipe(thiefCrafter, launch, lockpicks!)).toBe(true)
    const leftover = launch.Recipes.find((recipe) => recipe['Recipe ID'] === 'RCP-0044')
    expect(leftover?.Status).toBe('Needs Data')
    expect(leftover?.['Ingredient 3 Item ID']).toBe('ITEM-0208')
    const soup = entries.find((entry) => entry.name === 'Squid Noodle Soup')
    expect(soup?.materials).toContain('Soup Stock')
    expect(soup?.materials).not.toContain('Starroot')
  })

  it('skill recipe books list locked and unlocked rows for that skill', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const cooking = recipeBookForSkill(save, launch, 'SKL-0007')
    expect(cooking.length).toBeGreaterThan(0)
    expect(cooking.some((entry) => entry.known)).toBe(true)
    expect(cooking.some((entry) => !entry.known)).toBe(true)
    expect(cooking.every((entry) => entry.skill === 'Cooking')).toBe(true)
    expect(cooking.some((entry) => entry.name === 'Squid Noodle Soup' && !entry.known)).toBe(true)
    expect(cooking.some((entry) => entry.name === 'Cooked Baby Giant Squid')).toBe(false)
    const artisanry = recipeBookForSkill(save, launch, 'SKL-0012')
    expect(artisanry.some((entry) => entry.name === 'Leather Helmet' && entry.known)).toBe(true)
    expect(artisanry.some((entry) => entry.name === 'Leather Gloves' && entry.known)).toBe(true)
    expect(artisanry.some((entry) => entry.name === 'Regular Bow' && !entry.known)).toBe(true)
    expect(artisanry.some((entry) => entry.name === 'Quiver' && !entry.known)).toBe(true)
    expect(
      artisanry.find((entry) => entry.name === 'Regular Bow')?.knowledgeSource,
    ).toBe('Mentor: Quill')

    const taught = recipeBookForSkill({ ...save, unlockedNpcIds: ['NPC-0002'] }, launch, 'SKL-0012')
    expect(taught.some((entry) => entry.name === 'Regular Bow' && entry.known)).toBe(true)
    expect(taught.some((entry) => entry.name === 'Quiver' && entry.known)).toBe(true)
  })

  it('lists the recipe book by proficiency, leaving locked rows in place', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const entries = listRecipeBookEntries(save, launch)
    const levels = entries.map((entry) => entry.proficiency)
    expect(levels).toEqual([...levels].sort((a, b) => a - b))
    expect(entries.some((entry) => !entry.known)).toBe(true)
    const firstLocked = entries.findIndex((entry) => !entry.known)
    const laterKnown = entries.slice(firstLocked + 1).some((entry) => entry.known)
    expect(laterKnown).toBe(true)
  })

  it('expands skill-menu groups into individual recipe-book rows', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const smithing = recipeBookView(save, launch, 'SKL-0011')
    expect(smithing.tabs.map((tab) => tab.label)).toContain('Basic metal')
    const steel = smithing.tabs[0]?.sections.find((section) => section.title === 'Steel items')
    expect(steel?.entries.some((entry) => entry.name === 'Steel Sword')).toBe(true)
    expect(steel?.entries.some((entry) => entry.name === 'Steel items')).toBe(false)

    const artisanry = recipeBookView(save, launch, 'SKL-0012')
    expect(artisanry.tabs.map((tab) => tab.label)).toEqual(
      expect.arrayContaining(['Bows', 'Jewelry', 'Other']),
    )
    const other = artisanry.tabs.find((tab) => tab.id === 'other')
    expect(other?.sections.some((section) => section.title === 'Leather equipment')).toBe(true)
    expect(
      other?.sections
        .flatMap((section) => section.entries)
        .some((entry) => entry.name === 'Leather Helmet'),
    ).toBe(true)
  })
})
