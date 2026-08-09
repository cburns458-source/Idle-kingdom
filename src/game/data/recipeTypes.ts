import type { RecordStatus, ReleasePhase } from './types'

export interface RecipeRow {
  'Recipe ID': string
  'Internal Key': string
  'Display Name': string
  'Skill ID': string
  'Output Item ID': string
  'Output Quantity': number
  'Facility ID': string
  'Proficiency Level': number
  'Base Duration Seconds': number
  'XP Reward': number
  'Knowledge Source': string | null
  'Action ID': string
  Status: RecordStatus
  'Release Phase': ReleasePhase
  Notes: string | null
  'Ingredient 1 Item ID': string | null
  'Ingredient 1 Quantity': number | null
  'Ingredient 2 Item ID': string | null
  'Ingredient 2 Quantity': number | null
  'Ingredient 3 Item ID': string | null
  'Ingredient 3 Quantity': number | null
}
