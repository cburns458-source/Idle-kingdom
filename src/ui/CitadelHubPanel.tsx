import { useEffect, useMemo, useState } from 'react'
import { listBazaarPosts, postToBazaar } from '../game/bazaar/service'
import type { BazaarPost, BazaarPostKind } from '../game/bazaar/types'
import {
  BAZAAR_BLURB,
  BAZAAR_BODY_MAX_LENGTH,
  BAZAAR_EMPTY_BODY,
  BAZAAR_EMPTY_HEADING,
  BAZAAR_PLACEHOLDER,
  BAZAAR_POSTED_NOTICE,
  BAZAAR_SIGN_IN_NOTICE,
  bazaarKindOptions,
  bazaarRows,
} from '../game/bazaar/views'
import { syncBountyHour } from '../game/bounties/progress'
import {
  claimForBounty,
  currentBountyBoard,
  listBountyClaims,
  tryClaimBounty,
} from '../game/bounties/service'
import type { BountyClaimRecord } from '../game/bounties/types'
import {
  BOUNTY_SIGN_IN_NOTICE,
  bountyClaimedNotice,
  bountyRotationLine,
  bountyRowView,
} from '../game/bounties/views'
import type { GameDatabase } from '../game/data/types'
import { isSignedIn } from '../game/multiplayer/auth'
import {
  CITADEL_HUB_TAB_LABELS,
  type CitadelHubTab,
} from '../game/multiplayer/citadel'
import type { PlayerSave } from '../game/save/types'
import { CloseButton } from './CloseButton'
import { formatDurationSeconds } from './formatDuration'

export type { CitadelHubTab }

interface CitadelHubLinksProps {
  tabs: CitadelHubTab[]
  title?: string
  onOpen: (tab: CitadelHubTab) => void
}

/** Location list entries that open hub panels the same way shops do. */
export function CitadelHubLinks({ tabs, title = 'Citadel', onOpen }: CitadelHubLinksProps) {
  if (tabs.length === 0) return null
  return (
    <section className="panel glass-panel location-activities">
      <h2>{title}</h2>
      <ul className="interaction-list">
        {tabs.map((tab) => (
          <li key={tab}>
            <div>
              <strong>{CITADEL_HUB_TAB_LABELS[tab]}</strong>
            </div>
            <button type="button" className="btn secondary" onClick={() => onOpen(tab)}>
              Open
            </button>
          </li>
        ))}
      </ul>
    </section>
  )
}

interface CitadelHubPanelProps {
  tab: CitadelHubTab
  db: GameDatabase
  save: PlayerSave
  onChangeSave: (save: PlayerSave) => void
  onClose: () => void
  onMessage?: (message: string) => void
  onOpenGuilds?: () => void
}

export function CitadelHubPanel({
  tab,
  db,
  save,
  onChangeSave,
  onClose,
  onMessage,
  onOpenGuilds,
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
    const result = tryClaimBounty(db, save, bounty, nowMs)
    if (!result.ok) {
      flash(result.reason)
      setClaims(listBountyClaims(board.hourKey))
      return
    }
    onChangeSave(result.save)
    setClaims(listBountyClaims(board.hourKey))
    flash(bountyClaimedNotice(result.goldGained, result.firstCompleter))
  }

  function handleBazaarPost() {
    const result = postToBazaar(bazaarKind, bazaarBody)
    if (!result.ok) {
      flash(result.reason)
      return
    }
    setBazaarBody('')
    setPosts(listBazaarPosts())
    flash(BAZAAR_POSTED_NOTICE)
  }

  if (tab === 'bounties') {
    return (
      <section className="panel glass-panel shop-panel citadel-hub-panel">
        <div className="activity-panel-head">
          <div>
            <h2>{CITADEL_HUB_TAB_LABELS.bounties}</h2>
            <p className="muted tiny">
              {bountyRotationLine(formatDurationSeconds(remainingMs / 1000))}
            </p>
          </div>
          <CloseButton onClick={onClose} />
        </div>
        {!signedIn && <p className="muted tiny">{BOUNTY_SIGN_IN_NOTICE}</p>}
        <ul className="interaction-list">
          {board.bounties.map((bounty) => {
            const claim =
              claimForBounty(board.hourKey, bounty.id) ??
              claims.find((row) => row.bountyId === bounty.id) ??
              null
            const row = bountyRowView(synced, bounty, claim, signedIn, nowMs)
            return (
              <li key={row.bountyId}>
                <div>
                  <strong>{row.title}</strong>
                  <p className="muted tiny">{row.description}</p>
                  <p className="muted tiny">{row.progressLine}</p>
                  {row.firstCompleterLine && (
                    <p className="muted tiny">{row.firstCompleterLine}</p>
                  )}
                </div>
                <button
                  type="button"
                  className="btn primary"
                  disabled={!row.canTurnIn}
                  onClick={() => handleClaim(row.bountyId)}
                >
                  {row.actionLabel}
                </button>
              </li>
            )
          })}
        </ul>
        {notice && <p className="muted tiny">{notice}</p>}
      </section>
    )
  }

  const rows = bazaarRows(posts)

  return (
    <section className="panel glass-panel shop-panel citadel-hub-panel">
      <div className="activity-panel-head">
        <div>
          <h2>{CITADEL_HUB_TAB_LABELS.bazaar}</h2>
          <p className="muted tiny">{BAZAAR_BLURB}</p>
        </div>
        <CloseButton onClick={onClose} />
      </div>
      {!signedIn ? (
        <p className="muted tiny">{BAZAAR_SIGN_IN_NOTICE}</p>
      ) : (
        <div className="citadel-bazaar-compose">
          <label className="field-label">
            Kind
            <select
              className="text-input"
              value={bazaarKind}
              onChange={(event) => setBazaarKind(event.target.value as BazaarPostKind)}
            >
              {bazaarKindOptions().map((option) => (
                <option key={option.kind} value={option.kind}>
                  {option.label}
                </option>
              ))}
            </select>
          </label>
          <label className="field-label">
            Post
            <input
              className="text-input"
              value={bazaarBody}
              maxLength={BAZAAR_BODY_MAX_LENGTH}
              placeholder={BAZAAR_PLACEHOLDER}
              onChange={(event) => setBazaarBody(event.target.value)}
            />
          </label>
          <div className="button-row">
            <button type="button" className="btn secondary" onClick={handleBazaarPost}>
              Post
            </button>
            {bazaarKind === 'recruit' && onOpenGuilds && (
              <button type="button" className="btn secondary" onClick={onOpenGuilds}>
                Open Guilds
              </button>
            )}
          </div>
        </div>
      )}
      <ul className="interaction-list citadel-bazaar-list">
        {rows.length === 0 && (
          <li>
            <div>
              <strong>{BAZAAR_EMPTY_HEADING}</strong>
              <p className="muted tiny">{BAZAAR_EMPTY_BODY}</p>
            </div>
          </li>
        )}
        {rows.map((row) => (
          <li key={row.postId}>
            <div>
              <strong>{row.heading}</strong>
              <p className="muted tiny">{row.body}</p>
            </div>
          </li>
        ))}
      </ul>
      {notice && <p className="muted tiny">{notice}</p>}
    </section>
  )
}
