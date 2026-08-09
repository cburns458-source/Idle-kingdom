interface TravelOverlayProps {
  fromName: string
  toName: string
  progress: number
}

export function TravelOverlay({ fromName, toName, progress }: TravelOverlayProps) {
  const pct = Math.round(progress * 100)
  return (
    <div className="travel-overlay" role="status" aria-live="polite">
      <div className="panel travel-card">
        <h2>Traveling</h2>
        <p className="lead">
          {fromName} → {toName}
        </p>
        <div className="travel-bar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={pct}>
          <div className="travel-bar-fill" style={{ width: `${pct}%` }} />
        </div>
        <p className="muted">{pct}%</p>
      </div>
    </div>
  )
}
