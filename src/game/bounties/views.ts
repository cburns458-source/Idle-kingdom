import type { PlayerSave } from '../save/types'
import { bountyProgressFor, isBountyReadyToClaim } from './progress'
import type { BountyClaimRecord, BountyDefinition, HourlyBountyBoard } from './types'

/** Where a signed-out player is sent to be able to claim anything. */
export const BOUNTY_SIGN_IN_NOTICE = 'Sign in from Menu → Account to claim bounty rewards.'

/**
 * The line above the board.
 *
 * The countdown is formatted by the client, because each one already has a
 * duration formatter the rest of its screens use.
 */
export function bountyRotationLine(remainingLabel: string): string {
  return `Rotates in ${remainingLabel}. First turn-in earns a bonus; others can still claim the base reward.`
}

/** One bounty as the board shows it. */
export interface BountyRowView {
  bountyId: string
  title: string
  description: string
  /** `3 / 10 · 120 gold (+60 first)`. */
  progressLine: string
  /** `First completer: Rowan`, or null while nobody has turned one in. */
  firstCompleterLine: string | null
  /** `Claimed`, `Turn in`, or `In progress`. */
  actionLabel: string
  /** True only when pressing the button would actually claim something. */
  canTurnIn: boolean
}

function rewardLine(bounty: BountyDefinition, progress: number): string {
  const done = Math.min(progress, bounty.amount)
  const bonus = bounty.firstPlaceBonusGold > 0 ? ` (+${bounty.firstPlaceBonusGold} first)` : ''
  return `${done} / ${bounty.amount} · ${bounty.rewardGold} gold${bonus}`
}

export function bountyRowView(
  save: PlayerSave,
  bounty: BountyDefinition,
  claim: BountyClaimRecord | null,
  signedIn: boolean,
  nowMs: number,
): BountyRowView {
  const ready = isBountyReadyToClaim(save, bounty, nowMs)
  const claimed = (save.bountyClaimedIds ?? []).includes(bounty.id)
  return {
    bountyId: bounty.id,
    title: bounty.title,
    description: bounty.description,
    progressLine: rewardLine(bounty, bountyProgressFor(save, bounty, nowMs)),
    firstCompleterLine: claim ? `First completer: ${claim.username}` : null,
    actionLabel: claimed ? 'Claimed' : ready ? 'Turn in' : 'In progress',
    canTurnIn: signedIn && ready && !claimed,
  }
}

/**
 * Every row of the current board.
 *
 * [claims] is the hour's recorded first turn-ins; a bounty nobody has finished
 * is simply absent from it.
 */
export function bountyRows(
  save: PlayerSave,
  board: HourlyBountyBoard,
  claims: BountyClaimRecord[],
  signedIn: boolean,
  nowMs: number,
): BountyRowView[] {
  return board.bounties.map((bounty) => {
    const claim = claims.find((row) => row.bountyId === bounty.id) ?? null
    return bountyRowView(save, bounty, claim, signedIn, nowMs)
  })
}

/** What the turn-in says once a backend has accepted it. */
export function bountyClaimedNotice(goldGained: number, firstCompleter: boolean): string {
  return firstCompleter
    ? `First completer! +${goldGained} gold.`
    : `Bounty claimed. +${goldGained} gold.`
}
