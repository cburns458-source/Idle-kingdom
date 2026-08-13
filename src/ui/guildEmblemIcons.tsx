import { guildEmblemSymbolPath } from '../game/multiplayer/emblems'
import type { GuildEmblem } from '../game/multiplayer/types'

/** Solid filled SVG marks for guild banners (no emoji). */
export function GuildEmblemIcon({
  symbol,
  className = 'guild-emblem-icon',
}: {
  symbol: string
  className?: string
}) {
  return (
    <svg className={className} viewBox="0 0 24 24" aria-hidden>
      <path fill="currentColor" d={guildEmblemSymbolPath(symbol)} />
    </svg>
  )
}

export function GuildEmblemBadge({
  emblem,
  tag,
  className = '',
}: {
  emblem: GuildEmblem
  tag?: string
  className?: string
}) {
  return (
    <span
      className={`guild-emblem-badge ${className}`.trim()}
      style={{ backgroundColor: emblem.color }}
      title={tag ? `[${tag}]` : undefined}
      aria-hidden
    >
      <GuildEmblemIcon symbol={emblem.symbol} />
    </span>
  )
}
