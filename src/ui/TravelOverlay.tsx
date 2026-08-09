interface TravelOverlayProps {
  fromName: string
  toName: string
  progress: number
}

export function TravelOverlay({ fromName, toName, progress }: TravelOverlayProps) {
  const pct = Math.min(100, Math.max(0, progress * 100))
  return (
    <div className="travel-overlay" role="status" aria-live="polite">
      <div className="panel travel-card">
        <h2>Traveling</h2>
        <p className="lead">
          {fromName} → {toName}
        </p>
        <div
          className="horse-track"
          aria-label={`Travel progress ${Math.round(pct)} percent`}
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={Math.round(pct)}
        >
          <div className="horse-track-line" />
          <div
            className="horse-rider"
            style={{ left: `calc(1.4rem + (100% - 2.8rem) * ${progress})` }}
            aria-hidden
          >
            <HorseSilhouette />
          </div>
        </div>
      </div>
    </div>
  )
}

/** Classic side-facing filled horse silhouette. */
function HorseSilhouette() {
  return (
    <svg className="horse-icon" viewBox="0 0 100 60" role="img" aria-hidden>
      <path
        fill="#14100c"
        d="M8 34c2-8 8-12 14-11 3 .4 5 2 7 4 2-5 7-9 14-9 5 0 9 2 12 5 1-2 3-4 6-5 5-1 10 1 13 5l3 5c2-1 5-1 8 1 4 3 5 8 3 12-2 3-5 5-9 5h-2l1 10c0 2-1 3-3 3h-4c-2 0-3-1-3-3l-1-9H46l1 9c0 2-1 3-3 3h-4c-2 0-3-1-3-3l-1-9H24l1 9c0 2-1 3-3 3h-4c-2 0-3-2-3-3l-1-8c-3 0-6-2-8-5-2-3-1-7 2-10zm66-1c2 0 4-1 5-3 1-2 0-4-2-5-2-1-4 0-5 2-1 2 0 5 2 6z"
      />
    </svg>
  )
}
