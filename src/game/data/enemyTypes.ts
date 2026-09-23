import type { RecordStatus, ReleasePhase } from './types'

export interface EnemyRow {
  'Enemy ID': string
  'Internal Key': string
  'Display Name': string
  'Location ID': string | null
  /** Might skill level. Scales encounter damage the same way player Might does. */
  'Might Level': number | null
  /** Vitality skill level. Scales encounter HP the same way player Vitality does. */
  'Vitality Level': number | null
  /** Derived Combat Level = ceil((Might + Vitality) × 0.75). */
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
