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
            <HorseIcon />
          </div>
        </div>
      </div>
    </div>
  )
}

function HorseIcon() {
  return (
    <svg className="horse-icon" viewBox="0 0 64 48" role="img" aria-hidden>
      <ellipse cx="30" cy="28" rx="16" ry="10" fill="#8b5a2b" />
      <path
        d="M42 24c6-1 10-6 12-10 1 5-1 10-4 13l-8 2z"
        fill="#a46b34"
      />
      <path d="M52 14c2-3 5-4 7-3-2 3-3 6-5 8l-4-1z" fill="#6e4220" />
      <circle cx="55" cy="12" r="1.2" fill="#2b1a0e" />
      <rect x="18" y="34" width="3.2" height="10" rx="1" fill="#5a3518" />
      <rect x="26" y="35" width="3.2" height="9" rx="1" fill="#5a3518" />
      <rect x="33" y="34" width="3.2" height="10" rx="1" fill="#5a3518" />
      <rect x="40" y="35" width="3.2" height="9" rx="1" fill="#5a3518" />
      <path d="M20 22c-4-6-9-7-13-5 4 1 7 5 9 9l4-4z" fill="#7a4a24" />
      <path d="M28 18c3-4 8-6 12-4-4 2-7 5-9 8l-3-4z" fill="#d4af37" />
    </svg>
  )
}
