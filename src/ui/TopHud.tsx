interface TopHudProps {
  characterName: string | null
  totalLevel: number
  totalXp: number
  gold: number
  currentHp: number
  maxHp: number
  activityLabel: string
  locationLabel: string
}

export function TopHud({
  characterName,
  totalLevel,
  totalXp,
  gold,
  currentHp,
  maxHp,
  activityLabel,
  locationLabel,
}: TopHudProps) {
  return (
    <header className="top-hud">
      <div className="top-hud-brand">
        <p className="brand">{characterName?.trim() || 'Adventurer'}</p>
        <p className="hud-location">
          {locationLabel}
          <span className="hud-sep">·</span>
          {activityLabel}
        </p>
      </div>
      <dl className="hud-stats">
        <div>
          <dt>Lvl</dt>
          <dd>{totalLevel.toLocaleString()}</dd>
        </div>
        <div>
          <dt>XP</dt>
          <dd>{totalXp.toLocaleString()}</dd>
        </div>
        <div>
          <dt>Gold</dt>
          <dd>{gold.toLocaleString()}</dd>
        </div>
        <div>
          <dt>HP</dt>
          <dd>
            {currentHp.toLocaleString()}/{maxHp.toLocaleString()}
          </dd>
        </div>
      </dl>
    </header>
  )
}
