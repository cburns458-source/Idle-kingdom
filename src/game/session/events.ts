import type { ActionRewardBundle } from '../activity/types'

/**
 * Everything a tick can tell the UI about, so the session never touches
 * presentation and the Flutter client can react to the same list.
 */
export type SessionEvent =
  /** One completed action's combined XP / loot / gold line. */
  | { kind: 'rewards'; bundle: ActionRewardBundle }
  /** Transient status line, e.g. the blow-by-blow of a combat round. */
  | { kind: 'message'; text: string }
  /** The running activity ended on its own; the text explains why. */
  | { kind: 'activity-stopped'; reason: string }
  /** A standard production craft finished, for the item pop. */
  | { kind: 'craft-completed'; itemId: string; displayName: string }
  /** A craft is blocked until the player frees a bag slot. */
  | { kind: 'inventory-full' }
  | {
      kind: 'combat-round'
      enemyId: string
      enemyName: string
      playerHit: number
      playerCrit: boolean
      offhandHit: number | null
      enemyHit: number | null
      thornsHit: number
      outcome: 'ongoing' | 'victory' | 'defeat'
    }
  | { kind: 'enemy-defeated'; enemyId: string; enemyName: string }
  | { kind: 'player-defeated'; enemyId: string; enemyName: string }
  /** A death pause elapsed and the activity picked back up. */
  | { kind: 'recovered' }
  | { kind: 'critter-spawned'; critterId: string; displayName: string }
