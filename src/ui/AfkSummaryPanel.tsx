export interface AfkSummaryData {
  title?: string
  subtitle?: string
  elapsedLabel: string
  gatheringActions: number
  craftsCompleted: number
  combatVictories: number
  combatDeaths: number
  messages: string[]
  example?: boolean
}

interface AfkSummaryPanelProps {
  summary: AfkSummaryData
  onClose: () => void
}

export function exampleAfkSummary(): AfkSummaryData {
  return {
    title: 'Welcome back',
    subtitle: 'Example AFK summary (demo preview)',
    elapsedLabel: '4 hours away',
    gatheringActions: 312,
    craftsCompleted: 18,
    combatVictories: 27,
    combatDeaths: 2,
    messages: [
      'Won 27 fights while away.',
      'Gathered through 312 actions while away.',
      'Crafted 1 Baked Potato (+120 XP)',
      'Crafted 1 Baked Potato (+120 XP)',
      '…and 16 more crafts.',
      'Defeated by Cow while away.',
    ],
    example: true,
  }
}

function formatElapsed(ms: number): string {
  const totalMinutes = Math.max(0, Math.floor(ms / 60_000))
  const hours = Math.floor(totalMinutes / 60)
  const minutes = totalMinutes % 60
  if (hours <= 0) return `${minutes} minute${minutes === 1 ? '' : 's'} away`
  if (minutes <= 0) return `${hours} hour${hours === 1 ? '' : 's'} away`
  return `${hours}h ${minutes}m away`
}

export function afkSummaryFromUnattended(result: {
  gatheringActions: number
  craftsCompleted: number
  combatVictories: number
  combatDeaths: number
  effectiveElapsedMs: number
  messages: string[]
}): AfkSummaryData {
  return {
    title: 'Welcome back',
    subtitle: 'Progress while you were away',
    elapsedLabel: formatElapsed(result.effectiveElapsedMs),
    gatheringActions: result.gatheringActions,
    craftsCompleted: result.craftsCompleted,
    combatVictories: result.combatVictories,
    combatDeaths: result.combatDeaths,
    messages: result.messages,
    example: false,
  }
}

export function AfkSummaryPanel({ summary, onClose }: AfkSummaryPanelProps) {
  const lines = [
    summary.gatheringActions > 0
      ? `${summary.gatheringActions.toLocaleString()} gathering actions`
      : null,
    summary.craftsCompleted > 0
      ? `${summary.craftsCompleted.toLocaleString()} crafts finished`
      : null,
    summary.combatVictories > 0
      ? `${summary.combatVictories.toLocaleString()} combat victories`
      : null,
    summary.combatDeaths > 0
      ? `${summary.combatDeaths.toLocaleString()} defeats`
      : null,
  ].filter(Boolean) as string[]

  return (
    <div
      className="afk-summary-overlay"
      role="dialog"
      aria-modal="true"
      aria-labelledby="afk-summary-title"
    >
      <div className="panel afk-summary-card">
        {summary.example && <p className="muted tiny">Demo preview</p>}
        <h2 id="afk-summary-title">{summary.title ?? 'Welcome back'}</h2>
        <p className="lead">{summary.subtitle ?? 'Progress while you were away'}</p>
        <p className="afk-summary-elapsed">{summary.elapsedLabel}</p>

        {lines.length > 0 ? (
          <ul className="afk-summary-stats">
            {lines.map((line) => (
              <li key={line}>{line}</li>
            ))}
          </ul>
        ) : (
          <p className="muted">No activity progress this absence.</p>
        )}

        {summary.messages.length > 0 && (
          <ul className="afk-summary-messages">
            {summary.messages.slice(0, 8).map((message, index) => (
              <li key={`${index}-${message}`}>{message}</li>
            ))}
          </ul>
        )}

        <button type="button" className="btn primary" onClick={onClose}>
          Continue
        </button>
      </div>
    </div>
  )
}
