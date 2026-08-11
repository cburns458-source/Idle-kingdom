import type { GameDatabase } from '../game/data/types'
import { raceBonusSummaryLines, raceStartingItems, races } from '../game/races/races'

interface RacePickerProps {
  db: GameDatabase
  selectedRaceId: string | null
  onSelect: (raceId: string) => void
  /** When true, show each race's starting kit under the bonuses. */
  showStartingItems?: boolean
}

/** Selectable race list used by character creation, forced picker, and menu testing. */
export function RacePicker({
  db,
  selectedRaceId,
  onSelect,
  showStartingItems = false,
}: RacePickerProps) {
  return (
    <ul className="race-picker-list">
      {races(db).map((race) => {
        const raceId = race['Race ID']
        const selected = selectedRaceId === raceId
        const bonuses = raceBonusSummaryLines(db, raceId)
        const starters = showStartingItems ? raceStartingItems(db, raceId) : []
        return (
          <li key={raceId}>
            <button
              type="button"
              className={`race-picker-option${selected ? ' selected' : ''}`}
              onClick={() => onSelect(raceId)}
              aria-pressed={selected}
            >
              <strong>{race['Display Name']}</strong>
              {race.Description && <p className="muted tiny">{race.Description}</p>}
              {bonuses.length > 0 && (
                <p className="muted tiny">{bonuses.join(' · ')}</p>
              )}
              {starters.length > 0 && (
                <p className="muted tiny">
                  Starts with{' '}
                  {starters
                    .map((row) => {
                      const name =
                        db.Items.find((item) => item['Item ID'] === row['Item ID'])?.[
                          'Display Name'
                        ] ?? row['Item ID']
                      return row.Quantity > 1 ? `${name} ×${row.Quantity}` : name
                    })
                    .join(', ')}
                </p>
              )}
            </button>
          </li>
        )
      })}
    </ul>
  )
}
