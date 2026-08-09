interface TopHudProps {
  totalXp: number
  gold: number
  activityLabel: string
  locationLabel: string
}

export function TopHud({ totalXp, gold, activityLabel, locationLabel }: TopHudProps) {
  return (
    <header className="top-hud">
      <div className="top-hud-brand">
        <p className="brand">Idle Kingdoms</p>
        <p className="hud-location">{locationLabel}</p>
      </div>
      <dl className="hud-stats">
        <div>
          <dt>XP</dt>
          <dd>{totalXp.toLocaleString()}</dd>
        </div>
        <div>
          <dt>Gold</dt>
          <dd>{gold.toLocaleString()}</dd>
        </div>
        <div className="hud-activity">
          <dt>Activity</dt>
          <dd>{activityLabel}</dd>
        </div>
      </dl>
    </header>
  )
}
