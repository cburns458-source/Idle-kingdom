import { useEffect, useMemo, useState } from 'react'
import { playerPortraitAssetPath } from '../game/assets/playerAssets'
import { getSession, isSignedIn } from '../game/multiplayer/auth'
import {
  applyToGuild,
  createGuild,
  currentGuildId,
  decideGuildApplication,
  getGuild,
  leaveGuild,
  listGuildApplications,
  listGuildMembers,
  listGuilds,
  setGuildEmblem,
  setGuildJoinPolicy,
  setGuildMemberRole,
  setGuildRankLabels,
} from '../game/multiplayer/guilds'
import {
  GUILD_EMBLEM_COLORS,
  GUILD_EMBLEM_SYMBOLS,
  type GuildApplication,
  type GuildEmblem,
  type GuildJoinPolicy,
  type GuildListing,
  type GuildMember,
  type GuildRankKey,
  type GuildRecord,
  type GuildRole,
} from '../game/multiplayer/types'
import {
  createGuildFormView,
  defaultApplicationMessage,
  guildApplicationRows,
  guildBrowseRows,
  guildHomeHeader,
  guildRankOptions,
  guildRosterRows,
  leaveGuildPrompt,
  rankLabelFields,
  sanitizeGuildTagInput,
  GUILD_SIGN_IN_PROMPT,
  type GuildRosterSort,
} from '../game/multiplayer/views'
import type { PlayerSave } from '../game/save/types'
import { CloseButton } from './CloseButton'
import { GuildEmblemBadge, GuildEmblemIcon } from './guildEmblemIcons'

interface GuildViewProps {
  save: PlayerSave
  onChangeSave: (save: PlayerSave) => void
}

function GearIcon() {
  return (
    <svg className="guild-gear-svg" viewBox="0 0 24 24" aria-hidden>
      <path
        fill="currentColor"
        d="M19.1 12.9c0-.3 0-.6-.1-.9l2-1.5-1.9-3.3-2.3.8c-.5-.4-1-.7-1.6-.9L14.8 4h-3.8l-.4 2.4c-.6.2-1.1.5-1.6.9l-2.3-.8L4.8 9.8l2 1.5c0 .3-.1.6-.1.9s0 .6.1.9l-2 1.5 1.9 3.3 2.3-.8c.5.4 1 .7 1.6.9l.4 2.4h3.8l.4-2.4c.6-.2 1.1-.5 1.6-.9l2.3.8 1.9-3.3-2-1.5c.1-.3.1-.6.1-.9zM12.9 15.2c-1.8 0-3.2-1.4-3.2-3.2s1.4-3.2 3.2-3.2 3.2 1.4 3.2 3.2-1.4 3.2-3.2 3.2z"
      />
    </svg>
  )
}

function EmblemEditor({
  emblem,
  onChange,
  tag,
}: {
  emblem: GuildEmblem
  onChange: (emblem: GuildEmblem) => void
  tag?: string
}) {
  return (
    <div className="guild-emblem-editor">
      <p className="field-label">Banner</p>
      <div className="guild-emblem-preview-row">
        <GuildEmblemBadge emblem={emblem} tag={tag} />
        <span className="muted tiny">Color + solid icon</span>
      </div>
      <div className="guild-emblem-swatches" role="listbox" aria-label="Banner color">
        {GUILD_EMBLEM_COLORS.map((color) => (
          <button
            key={color}
            type="button"
            className={
              emblem.color === color ? 'guild-emblem-swatch active' : 'guild-emblem-swatch'
            }
            style={{ backgroundColor: color }}
            aria-label={`Color ${color}`}
            onClick={() => onChange({ ...emblem, color })}
          />
        ))}
      </div>
      <div className="guild-emblem-symbols" role="listbox" aria-label="Banner icon">
        {GUILD_EMBLEM_SYMBOLS.map((symbol) => (
          <button
            key={symbol}
            type="button"
            className={
              emblem.symbol === symbol
                ? 'guild-emblem-symbol-btn active'
                : 'guild-emblem-symbol-btn'
            }
            aria-label={symbol}
            onClick={() => onChange({ ...emblem, symbol })}
          >
            <GuildEmblemIcon symbol={symbol} />
          </button>
        ))}
      </div>
    </div>
  )
}

export function GuildView({ save, onChangeSave }: GuildViewProps) {
  const session = getSession()
  const [guildId, setGuildId] = useState<string | null>(() => currentGuildId())
  const [guilds, setGuilds] = useState<GuildListing[]>([])
  const [guild, setGuild] = useState<GuildRecord | null>(null)
  const [members, setMembers] = useState<GuildMember[]>([])
  const [applications, setApplications] = useState<GuildApplication[]>([])
  const [search, setSearch] = useState('')
  const [sort, setSort] = useState<GuildRosterSort>('oldest')
  const [createOpen, setCreateOpen] = useState(false)
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [leaveConfirm, setLeaveConfirm] = useState(false)
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

  const browseRows = useMemo(() => guildBrowseRows(guilds, search), [guilds, search])
  const header = useMemo(
    () => (guild ? guildHomeHeader(guild, members.length, session?.userId ?? null) : null),
    [guild, members.length, session?.userId],
  )
  const rosterRows = useMemo(
    () => (guild ? guildRosterRows(guild, members, sort, session?.userId ?? null) : []),
    [guild, members, sort, session?.userId],
  )
  const rankOptions = useMemo(() => (guild ? guildRankOptions(guild) : []), [guild])
  const applicationRows = useMemo(() => guildApplicationRows(applications), [applications])

  if (!session) {
    return (
      <section className="panel menu-panel">
        <h1>Guilds</h1>
        <p className="lead">{GUILD_SIGN_IN_PROMPT}</p>
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
            {browseRows.map((row) => (
              <li key={row.guildId}>
                <GuildEmblemBadge emblem={row.emblem} tag={row.tag} />
                <div className="quest-log-copy">
                  <strong>{row.title}</strong>
                  <span className="muted tiny">{row.subtitle}</span>
                </div>
                <button
                  type="button"
                  className="btn secondary"
                  disabled={busy || row.full}
                  onClick={() => {
                    setBusy(true)
                    void applyToGuild(
                      row.guildId,
                      defaultApplicationMessage(save.characterName),
                    ).then((result) => {
                      setBusy(false)
                      if (!result.ok) {
                        setNotice(result.reason)
                        return
                      }
                      setNotice(
                        result.joined
                          ? `Joined ${row.title}.`
                          : `Application sent to ${row.title}.`,
                      )
                    })
                  }}
                >
                  {row.actionLabel}
                </button>
              </li>
            ))}
            {browseRows.length === 0 && (
              <li className="muted tiny">No guilds match that search.</li>
            )}
          </ul>
          <button
            type="button"
            className="btn primary guild-create-open"
            onClick={() => setCreateOpen(true)}
          >
            Create guild ({createGuildFormView(save.gold, '').goldCost} gold)
          </button>
        </>
      )}

      {guildId && guild && header && (
        <>
          <header className="guild-home-head">
            <GuildEmblemBadge emblem={header.emblem} tag={header.tag} />
            <div className="quest-log-copy">
              <strong>{header.title}</strong>
              <span className="muted tiny">{header.subtitle}</span>
            </div>
            {header.canManage && (
              <button
                type="button"
                className="guild-settings-btn"
                aria-label="Guild settings"
                title="Guild settings"
                onClick={() => setSettingsOpen(true)}
              >
                <GearIcon />
              </button>
            )}
          </header>

          <div className="guild-roster-toolbar">
            <h2 className="menu-section-heading">Members</h2>
            <label className="field-label guild-sort-label">
              Sort
              <select
                className="text-input"
                value={sort}
                onChange={(event) => setSort(event.target.value as GuildRosterSort)}
                aria-label="Sort members by join date"
              >
                <option value="oldest">Join date (oldest)</option>
                <option value="newest">Join date (newest)</option>
              </select>
            </label>
          </div>

          <ul className="guild-member-list">
            {rosterRows.map((row) => (
              <li
                key={row.userId}
                className={
                  row.manageable ? 'guild-member-row guild-member-manage' : 'guild-member-row'
                }
              >
                <span className="guild-member-index">{row.position}</span>
                <span
                  className="social-portrait"
                  style={{ backgroundImage: `url(${playerPortraitAssetPath(row.appearance)})` }}
                  aria-hidden
                />
                <div className="guild-member-copy">
                  <strong>{row.username}</strong>
                  <span className="muted tiny">{row.rankLabel}</span>
                </div>
                <span className="guild-member-level">{row.totalLevel}</span>
                {row.manageable && (
                  <label className="guild-rank-select">
                    <span className="visually-hidden">Rank</span>
                    <select
                      className="text-input"
                      value={row.role}
                      onChange={(event) => {
                        const role = event.target.value as GuildRole
                        void setGuildMemberRole(guild.id, row.userId, role).then((result) =>
                          setNotice(result.ok ? 'Rank updated.' : result.reason),
                        )
                      }}
                    >
                      {rankOptions.map((option) => (
                        <option key={option.role} value={option.role}>
                          {option.label}
                        </option>
                      ))}
                    </select>
                  </label>
                )}
              </li>
            ))}
          </ul>

          {header.canManage && applicationRows.length > 0 && (
            <>
              <h2 className="menu-section-heading">Pending applications</h2>
              <ul className="achievement-list">
                {applicationRows.map((row) => (
                  <li key={row.applicationId}>
                    <div className="quest-log-copy">
                      <strong>{row.username}</strong>
                      <span className="muted tiny">{row.message}</span>
                    </div>
                    <button
                      type="button"
                      className="btn primary"
                      onClick={() =>
                        void decideGuildApplication(row.applicationId, true).then((result) =>
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
                        void decideGuildApplication(row.applicationId, false).then((result) =>
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
              className="btn danger guild-leave-btn"
              onClick={() => setLeaveConfirm(true)}
            >
              Leave guild
            </button>
          ) : (
            <div className="guild-leave-confirm">
              <p className="danger-note">{leaveGuildPrompt(guild)}</p>
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
                  className="btn danger"
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

      {settingsOpen && guild && (
        <GuildSettingsModal
          guild={guild}
          onClose={() => setSettingsOpen(false)}
          onChanged={setNotice}
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
  const form = createGuildFormView(gold, tag)

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
        <p className="muted tiny">{form.costLine}</p>

        <label className="field-label">
          Tag (2–4 letters)
          <input
            className="text-input"
            value={tag}
            maxLength={4}
            onChange={(event) => setTag(sanitizeGuildTagInput(event.target.value))}
            placeholder="EG"
            aria-label="Guild tag"
          />
        </label>
        <p className="muted tiny guild-tag-preview">Preview: {form.tagPreview}</p>

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

        <EmblemEditor emblem={emblem} onChange={setEmblem} tag={tag} />

        <button
          type="button"
          className="btn primary"
          disabled={busy || !form.canAfford}
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
          {form.submitLabel}
        </button>
      </div>
    </div>
  )
}

function GuildSettingsModal({
  guild,
  onClose,
  onChanged,
}: {
  guild: GuildRecord
  onClose: () => void
  onChanged: (message: string) => void
}) {
  const [joinPolicy, setJoinPolicy] = useState<GuildJoinPolicy>(guild.joinPolicy)
  const [labels, setLabels] = useState<Record<GuildRankKey, string>>(() => {
    const initial = {} as Record<GuildRankKey, string>
    for (const field of rankLabelFields(guild)) initial[field.role] = field.value
    return initial
  })
  const [emblem, setEmblem] = useState<GuildEmblem>(guild.emblem)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  return (
    <div className="guild-modal-overlay" role="presentation" onClick={onClose}>
      <div
        className="panel guild-modal"
        role="dialog"
        aria-modal="true"
        aria-label="Guild settings"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="skill-actions-head">
          <h2>Guild settings</h2>
          <CloseButton onClick={onClose} />
        </div>

        <label className="field-label">
          Join policy
          <select
            className="text-input"
            value={joinPolicy}
            onChange={(event) => setJoinPolicy(event.target.value as GuildJoinPolicy)}
          >
            <option value="open">Accept applications</option>
            <option value="closed">Closed</option>
          </select>
        </label>

        <EmblemEditor emblem={emblem} onChange={setEmblem} tag={guild.tag} />

        <h3 className="menu-section-heading">Rank names</h3>
        <p className="muted tiny">Rename Leader and the four promotable ranks.</p>
        {rankLabelFields(guild).map((field) => (
          <label key={field.role} className="field-label">
            {field.fieldLabel}
            <input
              className="text-input"
              value={labels[field.role]}
              maxLength={18}
              onChange={(event) =>
                setLabels((current) => ({ ...current, [field.role]: event.target.value }))
              }
            />
          </label>
        ))}

        {error && <p className="danger-note">{error}</p>}

        <button
          type="button"
          className="btn primary"
          disabled={busy}
          onClick={() => {
            setBusy(true)
            setError(null)
            void (async () => {
              const policyResult = await setGuildJoinPolicy(guild.id, joinPolicy)
              if (!policyResult.ok) {
                setBusy(false)
                setError(policyResult.reason)
                return
              }
              const emblemResult = await setGuildEmblem(guild.id, emblem)
              if (!emblemResult.ok) {
                setBusy(false)
                setError(emblemResult.reason)
                return
              }
              const ranksResult = await setGuildRankLabels(guild.id, labels)
              setBusy(false)
              if (!ranksResult.ok) {
                setError(ranksResult.reason)
                return
              }
              onChanged('Guild settings saved.')
              onClose()
            })()
          }}
        >
          Save settings
        </button>
      </div>
    </div>
  )
}
