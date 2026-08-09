/** Raw compact database shape (source field names preserved). */

export type ReleasePhase = 'Launch' | 'Expansion' | string
export type RecordStatus = 'Confirmed' | 'Planned' | 'Needs Data' | 'Proposed' | string

export interface ConfigRow {
  Key: string
  Value: string | number | boolean | null
  Unit: string | null
  Notes: string | null
}

export interface SkillRow {
  'Skill ID': string
  'Internal Key': string
  'Display Name': string
  Category: string
  Description: string | null
  Status: RecordStatus
  'Release Phase': ReleasePhase
  'Rules / Notes': string | null
}

export interface XPCurveRow {
  Level: number
  'Total XP at Level': number
  'XP to Next Level': number | null
}

export interface EquipmentSlotRow {
  'Slot ID': string
  'Internal Key': string
  'Display Name': string
  'Slot Group': string | null
  Status: RecordStatus
  Notes: string | null
}

export interface ItemRow {
  'Item ID': string
  'Internal Key': string
  'Display Name': string
  Category: string | null
  Subtype: string | null
  Status: RecordStatus
  'Release Phase': ReleasePhase
  'Associated Skill ID': string | null
  'Equipment Slot ID': string | null
  'Base Sell Value': number | null
  'Icon Asset Key': string | null
  Description: string | null
  'Functional / Source Tags': string | null
  Notes: string | null
}

export interface LocationRow {
  'Location ID': string
  'Internal Key': string
  'Display Name': string
  'Map ID': string | null
  'Location Type': string | null
  'Parent Location ID': string | null
  'Node ID': string | null
  Status: RecordStatus
  'Release Phase': ReleasePhase
  Description: string | null
  'Danger / Hostility': string | null
  'Background Asset Key': string | null
  Notes: string | null
}

export interface GameDatabase {
  Config: ConfigRow[]
  Skills: SkillRow[]
  XPCurve: XPCurveRow[]
  EquipmentSlots: EquipmentSlotRow[]
  Items: ItemRow[]
  Equipment: Record<string, unknown>[]
  Statistics: Record<string, unknown>[]
  Enchantments: Record<string, unknown>[]
  Maps: Record<string, unknown>[]
  Locations: LocationRow[]
  TravelConnections: Record<string, unknown>[]
  Facilities: Record<string, unknown>[]
  Activities: Record<string, unknown>[]
  PoolEntries: Record<string, unknown>[]
  Actions: Record<string, unknown>[]
  Requirements: Record<string, unknown>[]
  Enemies: Record<string, unknown>[]
  RewardEntries: Record<string, unknown>[]
  Recipes: Record<string, unknown>[]
  Projects: Record<string, unknown>[]
  NPCs: Record<string, unknown>[]
  Shops: Record<string, unknown>[]
  Quests: Record<string, unknown>[]
  Achievements: Record<string, unknown>[]
}

export const DATABASE_TABLES = [
  'Config',
  'Skills',
  'XPCurve',
  'EquipmentSlots',
  'Items',
  'Equipment',
  'Statistics',
  'Enchantments',
  'Maps',
  'Locations',
  'TravelConnections',
  'Facilities',
  'Activities',
  'PoolEntries',
  'Actions',
  'Requirements',
  'Enemies',
  'RewardEntries',
  'Recipes',
  'Projects',
  'NPCs',
  'Shops',
  'Quests',
  'Achievements',
] as const

export type DatabaseTableName = (typeof DATABASE_TABLES)[number]

export interface ValidationIssue {
  severity: 'error' | 'warning'
  table?: string
  id?: string
  message: string
}

export interface DatabaseIndexes {
  byTableId: Map<string, Map<string, Record<string, unknown>>>
  configByKey: Map<string, ConfigRow>
  skillsById: Map<string, SkillRow>
  locationsById: Map<string, LocationRow>
  itemsById: Map<string, ItemRow>
}
