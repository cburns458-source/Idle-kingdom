export interface BuildingDef {
  id: string
  name: string
  description: string
  icon: string
  /** Cost of the very first building of this type, in gold. */
  baseCost: number
  /** Multiplicative cost growth per owned building. */
  costGrowth: number
  /** Gold produced per second by a single building. */
  production: number
}

export interface GameState {
  /** Current amount of gold. */
  gold: number
  /** Total gold earned across the whole run (used for stats). */
  totalEarned: number
  /** Number of manual "collect taxes" clicks. */
  clicks: number
  /** Number of owned buildings, keyed by building id. */
  buildings: Record<string, number>
}
