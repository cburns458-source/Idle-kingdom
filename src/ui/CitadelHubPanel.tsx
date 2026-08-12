import { useEffect, useMemo, useState } from 'react'
import { listBazaarPosts, postToBazaar } from '../game/bazaar/service'
import type { BazaarPost, BazaarPostKind } from '../game/bazaar/types'
import {
  bountyProgressFor,
  isBountyReadyToClaim,
  syncBountyHour,
} from '../game/bounties/progress'
import {
  claimForBounty,
  currentBountyBoard,
  listBountyClaims,
  tryClaimBounty,
} from '../game/bounties/service'
import type { BountyClaimRecord } from '../game/bounties/types'
import { isSignedIn } from '../game/multiplayer/auth'
import type { PlayerSave } from '../game/save/types'
import { CloseButton } from './CloseButton'
import { formatDurationSeconds } from './formatDuration'

export type CitadelHubTab = 'bounties' | 'bazaar'

interface CitadelHubLinksProps {
  onOpen: (tab: CitadelHubTab) => void
}

/** Plaza list entries that open hub panels the same way shops do. */
export function CitadelHubLinks({ onOpen }: CitadelHubLinksProps) {
  return (
    <section className="panel glass-panel location-activities">
      <h2>Citadel Plaza</h2>
      <ul className="interaction-list">
        <li>
          <div>
            <strong>Hourly Bounties</strong>
          </div>
          <button type="button" className="btn secondary" onClick={() => onOpen('bounties')}>
            Open
          </button>
        </li>
        <li>
          <div>
            <strong>Grand Bazaar</strong>
          </div>
          <button type="button" className="btn secondary" onClick={() => onOpen('bazaar')}>
            Open
          </button>
        </li>
      </ul>
    </section>
  )
}

interface CitadelHubPanelProps {
  tab: CitadelHubTab
  save: PlayerSave
  onChangeSave: (save: PlayerSave) => void
  onClose: () => void
  onMessage?: (message: string) => void
}

export function CitadelHubPanel({
  tab,
  save,
  onChangeSave,
  onClose,
  onMessage,
}: CitadelHubPanelProps) {
  const signedIn = isSignedIn()
  const [nowMs, setNowMs] = useState(() => Date.now())
  const [claims, setClaims] = useState<BountyClaimRecord[]>([])
  const [posts, setPosts] = useState<BazaarPost[]>([])
  const [bazaarKind, setBazaarKind] = useState<BazaarPostKind>('message')
  const [bazaarBody, setBazaarBody] = useState('')
  const [notice, setNotice] = useState<string | null>(null)

  const board = useMemo(() => currentBountyBoard(nowMs), [nowMs])
  const synced = useMemo(() => syncBountyHour(save, nowMs), [save, nowMs])
  const remainingMs = Math.max(0, board.expiresAtMs - nowMs)

  useEffect(() => {
    const timer = window.setInterval(() => setNowMs(Date.now()), 1000)
    return () => window.clearInterval(timer)
  }, [])

  useEffect(() => {
    if (synced.bountyHourKey !== save.bountyHourKey) {
      onChangeSave(synced)
    }
  }, [synced, save.bountyHourKey, onChangeSave])

  useEffect(() => {
    setClaims(listBountyClaims(board.hourKey))
    setPosts(listBazaarPosts())
  }, [board.hourKey, nowMs, tab])

  function flash(message: string) {
    setNotice(message)
    onMessage?.(message)
  }

  function handleClaim(bountyId: string) {
    const bounty = board.bounties.find((row) => row.id === bountyId)
    if (!bounty) return
    const result = tryClaimBounty(save, bounty, nowMs)
    if (!result.ok) {
      flash(result.reason)
      setClaims(listBountyClaims(board.hourKey))
      return
    }
    onChangeSave(result.save)
    setClaims(listBountyClaims(board.hourKey))
    flash(
      result.firstCompleter
        ? `First completer! +${bounty.rewardGold} gold.`
        : `Bounty claimed. +${bounty.rewardGold} gold.`,
    )
  }

  function handleBazaarPost() {
    const result = postToBazaar(bazaarKind, bazaarBody)
    if (!result.ok) {
      flash(result.reason)
      return
    }
    setBazaarBody('')
    setPosts(listBazaarPosts())
    flash('Posted to the Grand Bazaar.')
  }

  if (tab === 'bounties') {
    return (
      <section className="panel glass-panel shop-panel citadel-hub-panel">
        <div className="activity-panel-head">
          <div>
            <h2>Hourly Bounties</h2>
            <p className="muted tiny">
              Rotates in {formatDurationSeconds(remainingMs / 1000)}. First completer claims the
              board slot.
            </p>
          </div>
          <CloseButton onClick={onClose} />
        </div>
        {!signedIn && (
          <p className="muted tiny">
            Sign in from Menu → Account to claim first-completer rewards.
          </p>
        )}
        <ul className="interaction-list">
          {board.bounties.map((bounty) => {
            const progress = bountyProgressFor(synced, bounty, nowMs)
            const claimed =
              claimForBounty(board.hourKey, bounty.id) ??
              claims.find((row) => row.bountyId === bounty.id) ??
              null
            const ready = isBountyReadyToClaim(synced, bounty, nowMs)
            const selfClaimed = (synced.bountyClaimedIds ?? []).includes(bounty.id)
            return (
              <li key={bounty.id}>
                <div>
                  <strong>{bounty.title}</strong>
                  <p className="muted tiny">{bounty.description}</p>
                  <p className="muted tiny">
                    {Math.min(progress, bounty.amount)} / {bounty.amount} · {bounty.rewardGold} gold
                  </p>
                  {claimed && (
                    <p className="muted tiny">First completer: {claimed.username}</p>
                  )}
                </div>
                <button
                  type="button"
                  className="btn primary"
                  disabled={!signedIn || !ready || selfClaimed || Boolean(claimed)}
                  onClick={() => handleClaim(bounty.id)}
                >
                  {selfClaimed || claimed ? 'Claimed' : ready ? 'Claim' : 'In progress'}
                </button>
              </li>
            )
          })}
        </ul>
        {notice && <p className="muted tiny">{notice}</p>}
      </section>
    )
  }

  return (
    <section className="panel glass-panel shop-panel citadel-hub-panel">
      <div className="activity-panel-head">
        <div>
          <h2>Grand Bazaar</h2>
          <p className="muted tiny">Plaza board for messages, recruitment, and trade notices.</p>
        </div>
        <CloseButton onClick={onClose} />
      </div>
      {!signedIn ? (
        <p className="muted tiny">Sign in to post.</p>
      ) : (
        <div className="citadel-bazaar-compose">
          <label className="field-label">
            Kind
            <select
              className="text-input"
              value={bazaarKind}
              onChange={(event) => setBazaarKind(event.target.value as BazaarPostKind)}
            >
              <option value="message">Message</option>
              <option value="recruit">Recruit</option>
              <option value="trade">Trade</option>
            </select>
          </label>
          <label className="field-label">
            Post
            <input
              className="text-input"
              value={bazaarBody}
              maxLength={240}
              placeholder="Write a short notice…"
              onChange={(event) => setBazaarBody(event.target.value)}
            />
          </label>
          <button type="button" className="btn secondary" onClick={handleBazaarPost}>
            Post
          </button>
        </div>
      )}
      <ul className="interaction-list citadel-bazaar-list">
        {posts.length === 0 && (
          <li>
            <div>
              <strong>Quiet for now</strong>
              <p className="muted tiny">Be the first to post.</p>
            </div>
          </li>
        )}
        {[...posts].reverse().map((post) => (
          <li key={post.id}>
            <div>
              <strong>
                {post.username} · {post.kind}
              </strong>
              <p className="muted tiny">{post.body}</p>
            </div>
          </li>
        ))}
      </ul>
      {notice && <p className="muted tiny">{notice}</p>}
    </section>
  )
}
