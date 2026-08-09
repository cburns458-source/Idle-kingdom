import type { RecordStatus, ReleasePhase } from './types'

export interface ProjectRow {
  'Project ID': string
  'Internal Key': string
  'Display Name': string
  'Skill ID': string
  'Output Item / Target ID': string
  'Output Quantity': number
  'Facility ID': string
  'Recipe ID': string | null
  'XP Reward': number
  'Gold Cost': number
  Instant: string
  Status: RecordStatus
  'Release Phase': ReleasePhase
  Notes: string | null
  'Input 1 Item ID': string | null
  'Input 1 Quantity': number | null
  'Input 2 Item ID': string | null
  'Input 2 Quantity': number | null
  'Input 3 Item ID': string | null
  'Input 3 Quantity': number | null
  'Input 4 Item ID': string | null
  'Input 4 Quantity': number | null
  'Required Skill 1 ID': string | null
  'Required Skill 1 Level': number | null
  'Required Skill 2 ID': string | null
  'Required Skill 2 Level': number | null
  'Required Skill 3 ID': string | null
  'Required Skill 3 Level': number | null
}

export interface EnchantmentRow {
  'Enchantment ID': string
  'Internal Key': string
  'Display Name': string
  'Valid Target': string | null
  Effect: string | null
  'Required Materials': string | null
  Status: RecordStatus
  'Release Phase': ReleasePhase
  Notes: string | null
}
