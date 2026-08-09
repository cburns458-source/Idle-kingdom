import { locationAssetPath, mapAssetPath } from '../game/assets/assetMap'
import type { GameDatabase, LocationRow } from '../game/data/types'
import { MAIN_MAP_ID } from '../game/world/constants'
import { layoutForMap } from '../game/world/mapLayout'
import { locationsForMapView } from '../game/world/travel'

interface WorldMapViewProps {
  db: GameDatabase
  mapId: string
  currentLocationId: string
  selectedLocationId: string | null
  onSelect: (locationId: string) => void
  onTravel: (locationId: string) => void
  onShowWorldMap?: () => void
  travelDisabled?: boolean
  travelLockReason?: string
}

export function WorldMapView({
  db,
  mapId,
  currentLocationId,
  selectedLocationId,
  onSelect,
  onTravel,
  onShowWorldMap,
  travelDisabled = false,
  travelLockReason,
}: WorldMapViewProps) {
  const map = db.Maps.find((entry) => entry['Map ID'] === mapId)
  const nodes = locationsForMapView(db, mapId)
  const layout = layoutForMap(mapId)
  const selected = nodes.find((location) => location['Location ID'] === selectedLocationId) ?? null

  return (
    <section className="map-view">
      <div className="map-toolbar">
        <h1>{map?.['Display Name'] ?? 'Map'}</h1>
        {mapId !== MAIN_MAP_ID && onShowWorldMap && (
          <button type="button" className="btn secondary" onClick={onShowWorldMap}>
            World Map
          </button>
        )}
      </div>

      <div
        className="map-stage"
        style={{ backgroundImage: `url(${mapAssetPath(mapId)})` }}
        role="list"
        aria-label="Location nodes"
      >
        {nodes.map((location) => {
          const pos = layout[location['Location ID']] ?? { x: 50, y: 50 }
          const isCurrent = location['Location ID'] === currentLocationId
          const isSelected = location['Location ID'] === selectedLocationId
          const dangerous = Boolean(location['Danger / Hostility'])
          return (
            <button
              key={location['Location ID']}
              type="button"
              role="listitem"
              className={[
                'map-node',
                isCurrent ? 'current' : '',
                isSelected ? 'selected' : '',
                dangerous ? 'dangerous' : '',
              ]
                .filter(Boolean)
                .join(' ')}
              style={{ left: `${pos.x}%`, top: `${pos.y}%` }}
              onClick={() => onSelect(location['Location ID'])}
            >
              <span className="map-node-dot" />
              <span className="map-node-label">{location['Display Name']}</span>
            </button>
          )
        })}
      </div>

      <SelectedLocationCard
        location={selected}
        isCurrent={selected?.['Location ID'] === currentLocationId}
        onTravel={() => selected && onTravel(selected['Location ID'])}
        travelDisabled={travelDisabled}
        travelLockReason={travelLockReason}
      />
    </section>
  )
}

function SelectedLocationCard({
  location,
  isCurrent,
  onTravel,
  travelDisabled,
  travelLockReason,
}: {
  location: LocationRow | null
  isCurrent: boolean
  onTravel: () => void
  travelDisabled: boolean
  travelLockReason?: string
}) {
  if (!location) {
    return (
      <div className="panel panel-quiet">
        <p className="lead">Select a location node to travel.</p>
      </div>
    )
  }

  return (
    <div className="panel location-card">
      <div
        className="location-card-art"
        style={{ backgroundImage: `url(${locationAssetPath(location['Location ID'])})` }}
        aria-hidden
      />
      <div className="location-card-body">
        <h2>{location['Display Name']}</h2>
        {location['Danger / Hostility'] && (
          <p className="danger-note">{location['Danger / Hostility']}</p>
        )}
        <p className="lead">{location.Description ?? 'A place in Idale.'}</p>
        {isCurrent ? (
          <p className="muted">You are here.</p>
        ) : (
          <>
            <button
              type="button"
              className="btn primary"
              disabled={travelDisabled}
              onClick={onTravel}
            >
              Travel
            </button>
            {travelDisabled && travelLockReason && (
              <p className="muted tiny">{travelLockReason}</p>
            )}
          </>
        )}
      </div>
    </div>
  )
}
