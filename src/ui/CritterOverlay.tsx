import { critterAssetPath } from '../game/assets/critterAssets'
import {
  activeSpawnAtLocation,
  collectCritter,
  getCritter,
} from '../game/critters/critters'
import type { PlayerSave } from '../game/save/types'

interface CritterOverlayProps {
  save: PlayerSave
  locationId: string
  onCollect: (save: PlayerSave, message: string) => void
}

/** Clickable Critter overlay on location art — kept clear of the Action UI band. */
export function CritterOverlay({ save, locationId, onCollect }: CritterOverlayProps) {
  const spawn = activeSpawnAtLocation(save, locationId)
  if (!spawn) return null
  const critter = getCritter(spawn.critterId)
  if (!critter) return null

  return (
    <button
      type="button"
      className="critter-overlay"
      aria-label={`Collect ${critter.displayName}`}
      title={critter.displayName}
      onClick={() => {
        const result = collectCritter(save, locationId)
        if (!result.ok) return
        const message =
          result.count > 1
            ? `Collected ${result.critter.displayName} (×${result.count}).`
            : `Collected ${result.critter.displayName}!`
        onCollect(result.save, message)
      }}
    >
      <span
        className="critter-overlay-art"
        style={{ backgroundImage: `url(${critterAssetPath(critter.internalKey)})` }}
        aria-hidden
      />
      <span className="critter-overlay-name">{critter.displayName}</span>
    </button>
  )
}
