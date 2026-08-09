import type { RecordStatus, ReleasePhase } from './types'

export interface EnemyRow {
  'Enemy ID': string
  'Internal Key': string
  'Display Name': string
  'Location ID': string | null
  'Combat Level': number | null
  'Maximum HP': number
  'Min Damage': number
  'Max Damage': number
  'Combat XP': number | null
  'Minimum Gold': number | null
  'Maximum Gold': number | null
  'Drop Chance': number | null
  'Reward Table ID': string | null
  'Sprite Asset Key': string | null
  Status: RecordStatus
  'Release Phase': ReleasePhase
  Notes: string | null
}
