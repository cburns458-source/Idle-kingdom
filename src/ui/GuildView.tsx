import { useEffect, useMemo, useState } from 'react'
import { playerPortraitAssetPath } from '../game/assets/playerAssets'
import { getSession, isSignedIn } from '../game/multiplayer/auth'
import {
  applyToGuild,
  createGuild,
  currentGuildId,
  decideGuildApplication,
  getGuild,
  guildRoleLabel,
  leaveGuild,
  listGuildApplications,
  listGuildMembers,
  listGuilds,
  setGuildJoinPolicy,
  setGuildMemberRole,
  setGuildRankLabels,
} from '../game/multiplayer/guilds'
import {
  DEFAULT_GUILD_RANK_LABELS,
  GUILD_CREATE_GOLD_COST,
  GUILD_EMBLEM_COLORS,
  GUILD_EMBLEM_SYMBOLS,
  GUILD_MAX_MEMBERS,
  PROMOTABLE_GUILD_RANKS,
  type GuildApplication,
  type GuildEmblem,
  type GuildJoinPolicy,
  type GuildMember,
  type GuildRankKey,
  type GuildRecord,
  type GuildRole,
} from '../game/multiplayer/types'
import type { PlayerSave } from '../game/save/types'
import { CloseButton } from './CloseButton'

interface GuildViewProps {
  save: PlayerSave
  onChangeSave: (save: PlayerSave) => void
}

type JoinSort = 'oldest' | 'newest'

const EDITABLE_RANK_KEYS = Object.keys(DEFAULT_GUILD_RANK_LABELS) as GuildRankKey[]

function GuildEmblemBadge({ emblem, tag }: { emblem: GuildEmblem; tag?: string }) {
  return (
    <span
      className="guild-emblem-badge"
      style={{ backgroundColor: emblem.color }}
      title={tag ? `[${tag}]` : undefined}
      aria-hidden
    >
      <span className="guild-emblem-symbol">{emblem.symbol}</span>
    </span>
  )
}

export function GuildView({ save, onChangeSave }: GuildViewProps) {
  const session = getSession()
  const [guildId, setGuildId] = useState<string | null>(() => currentGuildId())
  const [guilds, setGuilds] = useState<Array<GuildRecord & { memberCount: number }>[]>([])
  const [guild, setGuild] = useState<GuildRecord | null>(null)
  const [members, setMembers] = useState<GuildMember[]>([])
  const [applications, setApplications] = useState<GuildApplication[]>([])
  const [search, setSearch] = useState('')
  const [sort, setSort] = useState<JoinSort>('oldest')
  const [createOpen, setCreateOpen] = useState(false)
  const [leaveConfirm, setLeaveConfirm] = useState(false)
  const [rankEditOpen, setRankEditOpen] = useState(false)
  const [notice, setNotice] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function refresh() {
    const id = currentGuildId()
    setGuildId(id)
    if (!id) {
      setGuild(null)
      setMembers([])
      setApplications([])
      setGuilds(await listGuilds())
      return
    }
    const [nextGuild, nextMembers, nextApps] = await Promise.all([
      getGuild(id),
      listGuildMembers(id),
      listGuildApplications(id),
    ])
    setGuild(nextGuild)
    setMembers(nextMembers)
    setApplications(nextApps)
    setGuilds([])
  }

  useEffect(() => {
    if (!isSignedIn()) return
    void refresh()
  }, [notice])

  const filteredGuilds = useMemo(() => {
    const q = search.trim().toLowerCase()
    if (!q) return guilds
    return guilds.filter(
      (row) =>
        row.name.toLowerCase().includes(q) ||
        row.tag.toLowerCase().includes(q) ||
        `[${row.tag.toLowerCase()}]`.includes(q),
    )
  }, [guilds, search])

  const sortedMembers = useMemo(() => {
    const copy = [...members]
    copy.sort((a, b) => {
      const delta = Date.parse(a.joinedAt) - Date.parse(b.joinedAt)
      return sort === 'oldest' ? delta : -delta
    })
    return copy
  }, [members, sort])

  const isLeader = Boolean(session && guild && guild.leaderId === session.userId)

  if (!session) {
    return (
      <section className="panel menu-panel">
        <h1>Guilds</h1>
        <p className="lead">Sign in from Menu → Account to use guilds.</p>
      </section>
    )
  }

  return (
    <section className="panel menu-panel guild-panel">
      <h1>Guilds</h1>

      {!guildId && (
        <>
          <label className="field-label guild-search-label">
            Search guilds
            <input
              className="text-input"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="Name or tag…"
              aria-label="Search guilds"
            />
          </label>
          <ul className="achievement-list guild-browse-list">
            {filteredGuilds.map((row) => (
              <li key={row.id}>
                <GuildEmblemBadge emblem={row.emblem} tag={row.tag} />
                <div className="quest-log-copy">
                  <strong>
                    [{row.tag}] {row.name}
                  </strong>
                  <span className="muted tiny">
                    {row.joinPolicy === 'open' ? 'Accept applications' : 'Closed'} ·{' '}
                    {row.memberCount}/{GUILD_MAX_MEMBERS} · {row.description || 'No description.'}
                  </span>
                </div>
                <button
                  type="button"
                  className="btn secondary"
                  disabled={busy || row.memberCount >= GUILD_MAX_MEMBERS}
                  onClick={() => {
                    setBusy(true)
                    void applyToGuild(row.id, `${save.characterName ?? 'Adventurer'} requests to join`).then(
                      (result) => {
                        setBusy(false)
                        if (!result.ok) {
                          setNotice(result.reason)
                          return
                        }
                        setNotice(
                          result.joined
                            ? `Joined [${row.tag}] ${row.name}.`
                            : `Application sent to [${row.tag}] ${row.name}.`,
                        )
                      },
                    )
                  }}
                >
                  {row.memberCount >= GUILD_MAX_MEMBERS
                    ? 'Full'
                    : row.joinPolicy === 'open'
                      ? 'Join'
                      : 'Apply'}
                </button>
              </li>
            ))}
            {filteredGuilds.length === 0 && (
              <li className="muted tiny">No guilds match that search.</li>
            )}
          </ul>
          <button
            type="button"
            className="btn primary guild-create-open"
            onClick={() => setCreateOpen(true)}
          >
            Create guild ({GUILD_CREATE_GOLD_COST} gold)
          </button>
        </>
      )}

      {guildId && guild && (
        <>
          <header className="guild-home-head">
            <GuildEmblemBadge emblem={guild.emblem} tag={guild.tag} />
            <div className="quest-log-copy">
              <strong>
                [{guild.tag}] {guild.name}
              </strong>
              <span className="muted tiny">
                {guild.joinPolicy === 'open' ? 'Accept applications' : 'Closed'} ·{' '}
                {members.length}/{GUILD_MAX_MEMBERS} members
              </span>
            </div>
          </header>

          {isLeader && (
            <div className="guild-leader-tools">
              <label className="field-label">
                Join policy
                <select
                  className="text-input"
                  value={guild.joinPolicy}
                  onChange={(event) => {
                    const joinPolicy = event.target.value as GuildJoinPolicy
                    void setGuildJoinPolicy(guild.id, joinPolicy).then((result) =>
                      setNotice(result.ok ? `Join policy set to ${joinPolicy === 'open' ? 'Accept applications' : 'Closed'}.` : result.reason),
                    )
                  }}
                >
                  <option value="open">Accept applications</option>
                  <option value="closed">Closed</option>
                </select>
              </label>
              <button
                type="button"
                className="btn secondary"
                onClick={() => setRankEditOpen(true)}
              >
                Edit rank names
              </button>
            </div>
          )}

          <div className="guild-roster-toolbar">
            <h2 className="menu-section-heading">Members</h2>
            <label className="field-label guild-sort-label">
              Sort
              <select
                className="text-input"
                value={sort}
                onChange={(event) => setSort(event.target.value as JoinSort)}
                aria-label="Sort members by join date"
              >
                <option value="oldest">Join date (oldest)</option>
                <option value="newest">Join date (newest)</option>
              </select>
            </label>
          </div>

          <ul className="guild-member-list">
            {sortedMembers.map((member, index) => (
              <li
                key={member.userId}
                className={
                  isLeader && member.role !== 'leader'
                    ? 'guild-member-row guild-member-manage'
                    : 'guild-member-row'
                }
              >
                <span className="guild-member-index">{index + 1}</span>
                <span
                  className="social-portrait"
                  style={{
                    backgroundImage: `url(${playerPortraitAssetPath(member.appearance)})`,
                  }}
                  aria-hidden
                />
                <div className="guild-member-copy">
                  <strong>{member.username}</strong>
                  <span className="muted tiny">
                    {guildRoleLabel(guild, member.role)}
                  </span>
                </div>
                <span className="guild-member-level">{member.totalLevel}</span>
                {isLeader && member.role !== 'leader' && (
                  <label className="guild-rank-select">
                    <span className="visually-hidden">Rank</span>
                    <select
                      className="text-input"
                      value={member.role}
                      onChange={(event) => {
                        const role = event.target.value as GuildRole
                        void setGuildMemberRole(guild.id, member.userId, role).then((result) =>
                          setNotice(result.ok ? 'Rank updated.' : result.reason),
                        )
                      }}
                    >
                      {PROMOTABLE_GUILD_RANKS.map((role) => (
                        <option key={role} value={role}>
                          {guild.rankLabels[role]}
                        </option>
                      ))}
                    </select>
                  </label>
                )}
              </li>
            ))}
          </ul>

          {isLeader && applications.length > 0 && (
            <>
              <h2 className="menu-section-heading">Pending applications</h2>
              <ul className="achievement-list">
                {applications.map((application) => (
                  <li key={application.id}>
                    <div className="quest-log-copy">
                      <strong>{application.username}</strong>
                      <span className="muted tiny">{application.message || 'No message.'}</span>
                    </div>
                    <button
                      type="button"
                      className="btn primary"
                      onClick={() =>
                        void decideGuildApplication(application.id, true).then((result) =>
                          setNotice(result.ok ? 'Accepted.' : result.reason),
                        )
                      }
                    >
                      Accept
                    </button>
                    <button
                      type="button"
                      className="btn secondary"
                      onClick={() =>
                        void decideGuildApplication(application.id, false).then((result) =>
                          setNotice(result.ok ? 'Declined.' : result.reason),
                        )
                      }
                    >
                      Decline
                    </button>
                  </li>
                ))}
              </ul>
            </>
          )}

          {!leaveConfirm ? (
            <button
              type="button"
              className="btn secondary guild-leave-btn"
              onClick={() => setLeaveConfirm(true)}
            >
              Leave guild
            </button>
          ) : (
            <div className="guild-leave-confirm">
              <p className="danger-note">
                Leave [{guild.tag}] {guild.name}? You will need to rejoin or reapply later.
              </p>
              <div className="guild-leave-actions">
                <button
                  type="button"
                  className="btn secondary"
                  onClick={() => setLeaveConfirm(false)}
                >
                  Cancel
                </button>
                <button
                  type="button"
                  className="btn primary"
                  onClick={() =>
                    void leaveGuild().then((result) => {
                      setLeaveConfirm(false)
                      setNotice(result.ok ? 'Left guild.' : result.reason)
                    })
                  }
                >
                  Leave
                </button>
              </div>
            </div>
          )}
        </>
      )}

      {notice && <p className="muted tiny guild-notice">{notice}</p>}

      {createOpen && (
        <CreateGuildModal
          gold={save.gold}
          onClose={() => setCreateOpen(false)}
          onCreated={(goldCost) => {
            onChangeSave({
              ...save,
              gold: Math.max(0, save.gold - goldCost),
              updatedAt: new Date().toISOString(),
            })
            setCreateOpen(false)
            setNotice('Guild created.')
          }}
          onError={setNotice}
        />
      )}

      {rankEditOpen && guild && (
        <RankLabelsModal
          guild={guild}
          onClose={() => setRankEditOpen(false)}
          onSaved={() => {
            setRankEditOpen(false)
            setNotice('Rank names updated.')
          }}
          onError={setNotice}
        />
      )}
    </section>
  )
}

function CreateGuildModal({
  gold,
  onClose,
  onCreated,
  onError,
}: {
  gold: number
  onClose: () => void
  onCreated: (goldCost: number) => void
  onError: (reason: string) => void
}) {
  const [name, setName] = useState('')
  const [tag, setTag] = useState('')
  const [emblem, setEmblem] = useState<GuildEmblem>({
    color: GUILD_EMBLEM_COLORS[0],
    symbol: GUILD_EMBLEM_SYMBOLS[0],
  })
  const [busy, setBusy] = useState(false)
  const canAfford = gold >= GUILD_CREATE_GOLD_COST

  return (
    <div className="guild-modal-overlay" role="presentation" onClick={onClose}>
      <div
        className="panel guild-modal"
        role="dialog"
        aria-modal="true"
        aria-label="Create guild"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="skill-actions-head">
          <h2>Create guild</h2>
          <CloseButton onClick={onClose} />
        </div>
        <p className="muted tiny">Costs {GUILD_CREATE_GOLD_COST} gold · you have {gold.toLocaleString()}</p>

        <label className="field-label">
          Tag (2–4 letters)
          <input
            className="text-input"
            value={tag}
            maxLength={4}
            onChange={(event) =>
              setTag(event.target.value.replace(/[^a-zA-Z]/g, '').toUpperCase().slice(0, 4))
            }
            placeholder="EG"
            aria-label="Guild tag"
          />
        </label>
        <p className="muted tiny guild-tag-preview">Preview: [{tag || '??'}]</p>

        <label className="field-label">
          Name
          <input
            className="text-input"
            value={name}
            maxLength={28}
            onChange={(event) => setName(event.target.value)}
            placeholder="Guild name"
            aria-label="Guild name"
          />
        </label>

        <div className="guild-emblem-editor">
          <p className="field-label">Emblem</p>
          <div className="guild-emblem-preview-row">
            <GuildEmblemBadge emblem={emblem} tag={tag} />
            <span className="muted tiny">Banner color + symbol</span>
          </div>
          <div className="guild-emblem-swatches" role="listbox" aria-label="Banner color">
            {GUILD_EMBLEM_COLORS.map((color) => (
              <button
                key={color}
                type="button"
                className={
                  emblem.color === color
                    ? 'guild-emblem-swatch active'
                    : 'guild-emblem-swatch'
                }
                style={{ backgroundColor: color }}
                aria-label={`Color ${color}`}
                onClick={() => setEmblem((current) => ({ ...current, color }))}
              />
            ))}
          </div>
          <div className="guild-emblem-symbols" role="listbox" aria-label="Banner symbol">
            {GUILD_EMBLEM_SYMBOLS.map((symbol) => (
              <button
                key={symbol}
                type="button"
                className={
                  emblem.symbol === symbol
                    ? 'guild-emblem-symbol-btn active'
                    : 'guild-emblem-symbol-btn'
                }
                onClick={() => setEmblem((current) => ({ ...current, symbol }))}
              >
                {symbol}
              </button>
            ))}
          </div>
        </div>

        <button
          type="button"
          className="btn primary"
          disabled={busy || !canAfford}
          onClick={() => {
            setBusy(true)
            void createGuild({ name, tag, emblem }, gold).then((result) => {
              setBusy(false)
              if (!result.ok) {
                onError(result.reason)
                return
              }
              onCreated(result.goldCost)
            })
          }}
        >
          {canAfford ? `Create for ${GUILD_CREATE_GOLD_COST} gold` : 'Not enough gold'}
        </button>
      </div>
    </div>
  )
}

function RankLabelsModal({
  guild,
  onClose,
  onSaved,
  onError,
}: {
  guild: GuildRecord
  onClose: () => void
  onSaved: () => void
  onError: (reason: string) => void
}) {
  const [labels, setLabels] = useState(guild.rankLabels)
  const [busy, setBusy] = useState(false)

  return (
    <div className="guild-modal-overlay" role="presentation" onClick={onClose}>
      <div
        className="panel guild-modal"
        role="dialog"
        aria-modal="true"
        aria-label="Edit rank names"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="skill-actions-head">
          <h2>Rank names</h2>
          <CloseButton onClick={onClose} />
        </div>
        <p className="muted tiny">Rename Leader and the four promotable ranks.</p>
        {EDITABLE_RANK_KEYS.map((role) => (
          <label key={role} className="field-label">
            {DEFAULT_GUILD_RANK_LABELS[role]} slot
            <input
              className="text-input"
              value={labels[role] ?? DEFAULT_GUILD_RANK_LABELS[role]}
              maxLength={18}
              onChange={(event) =>
                setLabels((current) => ({ ...current, [role]: event.target.value }))
              }
            />
          </label>
        ))}
        <button
          type="button"
          className="btn primary"
          disabled={busy}
          onClick={() => {
            setBusy(true)
            void setGuildRankLabels(guild.id, labels).then((result) => {
              setBusy(false)
              if (!result.ok) {
                onError(result.reason)
                return
              }
              onSaved()
            })
          }}
        >
          Save rank names
        </button>
      </div>
    </div>
  )
}
