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
            <RunningGirlSilhouette />
          </div>
        </div>
      </div>
    </div>
  )
}

/** Side-view silhouette: girl in a dress running to the right. */
function RunningGirlSilhouette() {
  return (
    <svg className="travel-runner-icon" viewBox="0 0 64 64" role="img" aria-hidden>
      <circle cx="38" cy="10" r="6" fill="#14100c" />
      <path
        fill="#14100c"
        d="M36 17c-2 3-3 6-2 9 4 1 8 3 10 7l5 8c.8 1.4.3 3.2-1.1 4l-2.4 1.2c-1.5.7-3.3.1-4.1-1.3L38 38l-2.2 3.2 7.4 5.2c1.4 1 2 2.8 1.4 4.4L42 59c-.6 1.5-2.2 2.3-3.8 1.8l-2.2-.7c-1.5-.5-2.4-2.1-1.9-3.6l1.8-5.2-7.6-4.4c-1.6-1-2.5-2.9-2.1-4.8l3.2-12.2c.3-1.2 1.1-2.2 2.2-2.8l.6-.3c-1.4-2.2-4-3.7-7.1-3.9-2.1-.1-3.7-1.9-3.6-4 .1-2 1.9-3.5 3.9-3.4 5.2.3 9.7 2.4 13.2 5.9z"
      />
      <path
        fill="#14100c"
        d="M28 34c2.2.8 3.6 2.8 3.6 5.1v2.2c0 1.4-1.1 2.5-2.5 2.5h-1.8c-1.4 0-2.5-1.1-2.5-2.5v-1.3c0-1.1-.6-2.1-1.5-2.6l-7.4-3.5c-1.3-.6-1.8-2.2-1.2-3.5.6-1.3 2.2-1.8 3.5-1.2L28 34z"
      />
      <path
        fill="#14100c"
        d="M33 37c2.4-.2 4.7 1.2 5.6 3.5l4.8 12.2c.6 1.5-.1 3.2-1.6 3.8l-2 .8c-1.5.6-3.2-.1-3.8-1.6L33.5 47l-1.5 2.2 5.4 6.4c1.1 1.3 1.1 3.2 0 4.5l-3.4 3.8c-1.1 1.2-2.9 1.3-4.1.3l-1.5-1.3c-1.2-1.1-1.3-2.9-.3-4.1l2.4-2.8-6.8-5.6c-1.4-1.2-2-3.2-1.4-5l3.8-10.2c.7-1.9 2.5-3.1 4.5-3.2z"
      />
    </svg>
  )
}
