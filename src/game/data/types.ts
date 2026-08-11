/** Raw compact database shape (source field names preserved). */

import type { EnemyRow } from './enemyTypes'
import type { EnchantmentRow, ProjectRow } from './projectTypes'
import type { RecipeRow } from './recipeTypes'

export type { EnemyRow, EnchantmentRow, ProjectRow, RecipeRow }

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

export interface EquipmentRow {
  'Equipment ID': string
  'Item ID': string
  'Slot ID': string | null
  'Required Skill ID': string | null
  'Required Level': number | null
  'Secondary Required Skill ID': string | null
  'Secondary Required Level': number | null
  'Min Damage': number | null
  'Max Damage': number | null
  'Damage Reduction': number | null
  'HP Bonus': number | null
  'Healing Amount': number | null
  'Action Time Reduction %': number | null
  'Capabilities / Effects': string | null
  Status: RecordStatus
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

export interface MapRow {
  'Map ID': string
  'Internal Key': string
  'Display Name': string
  'Map Type': string | null
  'Asset Key': string | null
  Status: RecordStatus
  'Release Phase': ReleasePhase
  Description: string | null
}

export interface TravelConnectionRow {
  'Connection ID': string
  'From Location ID': string
  'To Location ID': string
  Method: string | null
  Direction: string | null
  'Base Duration': number | null
  'Required Mount / Status': string | null
  Status: RecordStatus
  'Release Phase': ReleasePhase
  Notes: string | null
}

export interface FacilityRow {
  'Facility ID': string
  'Internal Key': string
  'Display Name': string
  'Facility Type': string | null
  'Location ID': string
  'Skill ID': string | null
  Status: RecordStatus
  'Release Phase': ReleasePhase
  Description: string | null
  Notes: string | null
}

export interface ActivityRow {
  'Activity ID': string
  'Internal Key': string
  'Contextual Name': string | null
  'Location ID': string
  'Pool ID': string | null
  'Pool Internal Key': string | null
  Description: string | null
  'Danger Warning Combat Level': number | null
  Status: RecordStatus
  'Release Phase': ReleasePhase
  Notes: string | null
}

export interface PoolEntryRow {
  'Pool Entry ID': string
  'Pool ID': string
  'Action ID': string
  Weight: number | null
  Status: RecordStatus
  Notes: string | null
}

export interface ActionRow {
  'Action ID': string
  'Internal Key': string
  'Display Name': string
  Category: string
  'Relevant Skill ID': string
  'Target Type': string | null
  'Target ID': string | null
  'Proficiency Level': number | null
  'Base Duration Seconds': number | null
  'XP Reward': number | null
  'Guaranteed Gold': number | null
  'Drop Chance': number | null
  'Reward Table ID': string | null
  'Secondary Drop Chance': number | null
  'Secondary Reward Table ID': string | null
  Status: RecordStatus
  'Release Phase': ReleasePhase
  Notes: string | null
}

export interface RequirementRow {
  'Requirement ID': string
  'Entity Type': string
  'Entity ID': string
  'Requirement Group': string | null
  'Group Logic': string | null
  'Requirement Type': string
  'Reference ID / Value': string | number | null
  Operator: string | null
  'Required Value': number | null
  Status: RecordStatus
  Notes: string | null
}

export interface RewardEntryRow {
  'Reward Entry ID': string
  'Reward Table ID': string
  'Reward Table Name': string | null
  Purpose: string | null
  'Reward Type': string
  'Reward ID / Value': string | null
  Weight: number | null
  'Minimum Quantity': number | null
  'Maximum Quantity': number | null
  'Skill ID': string | null
  'XP Amount': number | null
  Status: RecordStatus
  Notes: string | null
}

export interface NpcRow {
  'NPC ID': string
  'Internal Key': string
  'Display Name': string
  'Location ID': string
  Role: string | null
  Status: RecordStatus
  'Release Phase': ReleasePhase
  Description: string | null
  Notes: string | null
}

export interface ShopRow {
  'Shop ID': string
  'Internal Key': string
  'Display Name': string
  'Location ID': string
  'Shop Type': string | null
  Status: RecordStatus
  'Release Phase': ReleasePhase
  Description: string | null
  Notes: string | null
  /** Dynamic Entry N Item/Mode/Price/Currency fields are read at runtime. */
  [entryField: string]: string | number | null | undefined
}

export interface CosmeticSlotRow {
  'Cosmetic Slot ID': string
  'Internal Key': string
  'Display Name': string
  'Slot Group': string | null
  Status: RecordStatus
  'Release Phase': ReleasePhase
  Notes: string | null
}

export interface CosmeticRow {
  'Cosmetic ID': string
  'Item ID': string
  'Cosmetic Slot ID': string
  /** Semicolon-separated: crafting; unlock; shop_gold; shop_real_money; starter. */
  'Acquisition Tags': string | null
  Status: RecordStatus
  'Release Phase': ReleasePhase
  Notes: string | null
}

export type AppearanceCategoryKey =
  | 'skin_tone'
  | 'hairstyle'
  | 'hair_color'
  | 'expression'
  | 'beard'
  | 'gender_presentation'

export interface AppearanceOptionRow {
  'Appearance Option ID': string
  Category: AppearanceCategoryKey | string
  'Display Name': string
  /** Hex swatch color for swatch-style categories (skin tone, hair color); null otherwise. */
  'Swatch Color': string | null
  'Sort Order': number | null
  Status: RecordStatus
  'Release Phase': ReleasePhase
  Notes: string | null
}

export interface GameDatabase {
  Config: ConfigRow[]
  Skills: SkillRow[]
  XPCurve: XPCurveRow[]
  EquipmentSlots: EquipmentSlotRow[]
  Items: ItemRow[]
  Equipment: EquipmentRow[]
  Statistics: Record<string, unknown>[]
  Enchantments: EnchantmentRow[]
  Maps: MapRow[]
  Locations: LocationRow[]
  TravelConnections: TravelConnectionRow[]
  Facilities: FacilityRow[]
  Activities: ActivityRow[]
  PoolEntries: PoolEntryRow[]
  Actions: ActionRow[]
  Requirements: RequirementRow[]
  Enemies: EnemyRow[]
  RewardEntries: RewardEntryRow[]
  Recipes: RecipeRow[]
  Projects: ProjectRow[]
  NPCs: NpcRow[]
  Shops: ShopRow[]
  Quests: Record<string, unknown>[]
  Achievements: Record<string, unknown>[]
  CosmeticSlots: CosmeticSlotRow[]
  Cosmetics: CosmeticRow[]
  AppearanceOptions: AppearanceOptionRow[]
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
  'CosmeticSlots',
  'Cosmetics',
  'AppearanceOptions',
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
  mapsById: Map<string, MapRow>
  activitiesById: Map<string, ActivityRow>
  actionsById: Map<string, ActionRow>
  facilitiesByLocationId: Map<string, FacilityRow[]>
  activitiesByLocationId: Map<string, ActivityRow[]>
  npcsByLocationId: Map<string, NpcRow[]>
  shopsByLocationId: Map<string, ShopRow[]>
  poolEntriesByPoolId: Map<string, PoolEntryRow[]>
  rewardEntriesByTableId: Map<string, RewardEntryRow[]>
}
