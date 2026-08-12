import { useEffect, useState } from 'react'
import { locationAssetPath, mapAssetPath } from '../game/assets/assetMap'
import type { GameDatabase, LocationRow } from '../game/data/types'
import {
  EAST_MAP_ID,
  MAIN_MAP_ID,
  WEST_MAP_ID,
  adjacentMapForHorizon,
  isFutureHorizonLocation,
} from '../game/world/constants'
import { layoutForMap } from '../game/world/mapLayout'
import type { PlayerSave } from '../game/save/types'
import { locationsForMapView } from '../game/world/travel'

interface WorldMapViewProps {
  db: GameDatabase
  save: PlayerSave
  mapId: string
  currentLocationId: string
  selectedLocationId: string | null
  onSelect: (locationId: string) => void
  onTravel: (locationId: string) => void
  onBrowseMap?: (mapId: string) => void
  onShowWorldMap?: () => void
  travelDisabled?: boolean
  travelLockReason?: string
}

export function WorldMapView({
  db,
  save,
  mapId,
  currentLocationId,
  selectedLocationId,
  onSelect,
  onTravel,
  onBrowseMap,
  onShowWorldMap,
  travelDisabled = false,
  travelLockReason,
}: WorldMapViewProps) {
  const map = db.Maps.find((entry) => entry['Map ID'] === mapId)
  const nodes = locationsForMapView(db, mapId, save)
  const layout = layoutForMap(mapId)
  const selected = nodes.find((location) => location['Location ID'] === selectedLocationId) ?? null
  const isFutureRegion = mapId === WEST_MAP_ID || mapId === EAST_MAP_ID
  const [selectionHidden, setSelectionHidden] = useState(false)

  useEffect(() => {
    setSelectionHidden(false)
  }, [selectedLocationId, mapId])

  return (
    <section className="map-view">
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
          const future = isFutureHorizonLocation(location['Location ID'])
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
                future ? 'future-horizon' : '',
              ]
                .filter(Boolean)
                .join(' ')}
              style={{ left: `${pos.x}%`, top: `${pos.y}%` }}
              onClick={() => onSelect(location['Location ID'])}
              onDoubleClick={() => {
                if (future || travelDisabled) return
                if (location['Location ID'] === currentLocationId) return
                onTravel(location['Location ID'])
              }}
              title={
                future
                  ? undefined
                  : travelDisabled
                    ? travelLockReason
                    : 'Click to select · Double-click to travel'
              }
            >
              <span className="map-node-dot" />
              <span className="map-node-label">{location['Display Name']}</span>
            </button>
          )
        })}
      </div>

      <div className="map-toolbar map-overlay-top">
        <h1>{map?.['Display Name'] ?? 'Map'}</h1>
        {mapId !== MAIN_MAP_ID && onShowWorldMap && (
          <button type="button" className="btn secondary" onClick={onShowWorldMap}>
            World Map
          </button>
        )}
      </div>

      <div className="map-overlay-bottom">
        {selectionHidden ? (
          <button
            type="button"
            className="btn secondary map-selection-reveal"
            onClick={() => setSelectionHidden(false)}
          >
            Show selection
          </button>
        ) : isFutureRegion ? (
          <div className="panel location-card">
            <div className="location-card-body" style={{ gridColumn: '1 / -1' }}>
              <div className="location-card-head">
                <h2>{map?.['Display Name'] ?? 'Uncharted lands'}</h2>
              </div>
              <p className="lead location-card-desc">
                {map?.Description ?? 'Reserved for future content.'}
              </p>
              <p className="muted tiny">No destinations here yet.</p>
            </div>
          </div>
        ) : (
          <SelectedLocationCard
            mapId={mapId}
            location={selected}
            isCurrent={selected?.['Location ID'] === currentLocationId}
            onTravel={() => selected && onTravel(selected['Location ID'])}
            onViewAdjacent={() => {
              if (!selected) return
              const adjacent = adjacentMapForHorizon(selected['Location ID'])
              if (adjacent && onBrowseMap) onBrowseMap(adjacent)
            }}
            onHide={() => setSelectionHidden(true)}
            travelDisabled={travelDisabled}
            travelLockReason={travelLockReason}
          />
        )}
      </div>
    </section>
  )
}

function SelectedLocationCard({
  mapId,
  location,
  isCurrent,
  onTravel,
  onViewAdjacent,
  onHide,
  travelDisabled,
  travelLockReason,
}: {
  mapId: string
  location: LocationRow | null
  isCurrent: boolean
  onTravel: () => void
  onViewAdjacent: () => void
  onHide: () => void
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

  const future = isFutureHorizonLocation(location['Location ID'])

  return (
    <div className="panel location-card">
      {!future && (
        <div
          className="location-card-art"
          style={{ backgroundImage: `url(${locationAssetPath(location['Location ID'])})` }}
          aria-hidden
        />
      )}
      <div className="location-card-body" style={future ? { gridColumn: '1 / -1' } : undefined}>
        <div className="location-card-head">
          <h2>{location['Display Name']}</h2>
          <button type="button" className="btn secondary location-card-hide" onClick={onHide}>
            Hide
          </button>
        </div>
        {location['Danger / Hostility'] && (
          <p className="danger-note">{location['Danger / Hostility']}</p>
        )}
        {future ? (
          <button type="button" className="btn primary" onClick={onViewAdjacent}>
            View lands
          </button>
        ) : isCurrent ? (
          <p className="muted">You are here.</p>
        ) : (
          <>
            <button
              type="button"
              className="btn primary"
              disabled={travelDisabled}
              onClick={onTravel}
            >
              {mapId !== MAIN_MAP_ID
                ? `Enter ${location['Display Name']}`
                : 'Travel'}
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
