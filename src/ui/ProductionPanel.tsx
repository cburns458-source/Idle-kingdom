import { useMemo, useState } from 'react'
import type { RecipeRow } from '../game/data/recipeTypes'
import type { GameDatabase } from '../game/data/types'
import type { ActivityRow } from '../game/data/types'
import {
  clampProductionQuantity,
  inventoryCount,
  maxCraftsFromMaterials,
  maxCraftsFromQueueCap,
  recipeIngredients,
  recipesForActivity,
} from '../game/production/recipes'
import type { PlayerSave } from '../game/save/types'
import { formatDurationSeconds } from './formatDuration'
import { IngredientIconList } from './IngredientIcons'
import { ItemIcon } from './itemIcons'
import { QuantityNumpad } from './QuantityNumpad'
import { playerCombatAssetPath } from '../game/assets/playerAssets'
import { workstationAssetPath } from '../game/assets/workstationAssets'

interface ProductionPickerProps {
  db: GameDatabase
  save: PlayerSave
  activity: ActivityRow
  onCancel: () => void
  onConfirm: (recipeId: string, quantity: number) => void
}

export function ProductionPicker({
  db,
  save,
  activity,
  onCancel,
  onConfirm,
}: ProductionPickerProps) {
  const recipes = useMemo(
    () => recipesForActivity(db, save, activity['Activity ID']),
    [db, save, activity],
  )
  const [recipeId, setRecipeId] = useState(recipes[0]?.['Recipe ID'] ?? '')
  const recipe = recipes.find((row) => row['Recipe ID'] === recipeId) ?? null
  const materialMax = recipe ? maxCraftsFromMaterials(save, recipe) : 0
  const queueMax = recipe ? maxCraftsFromQueueCap(db, recipe) : 0
  const maxQty = recipe ? clampProductionQuantity(db, save, recipe, 999999) : 0
  const [quantity, setQuantity] = useState(1)
  const [qtyOpen, setQtyOpen] = useState(false)

  const clampedQty = Math.min(Math.max(1, quantity), Math.max(1, maxQty || 1))

  return (
    <section className="panel production-picker">
      <div className="activity-panel-head">
        <div>
          <h2>{activity['Contextual Name'] ?? activity['Internal Key']}</h2>
          <p className="muted">Choose a recipe and queue quantity</p>
        </div>
        <button type="button" className="btn secondary" onClick={onCancel}>
          Cancel
        </button>
      </div>

      {recipes.length === 0 ? (
        <p className="lead">No recipes available. Raise skill level or gather materials.</p>
      ) : (
        <>
          <label className="field-label" htmlFor="recipe-select">
            Recipe
          </label>
          <select
            id="recipe-select"
            className="text-input"
            value={recipeId}
            onChange={(event) => {
              setRecipeId(event.target.value)
              setQuantity(1)
            }}
          >
            {recipes.map((row) => (
              <option key={row['Recipe ID']} value={row['Recipe ID']}>
                {row['Display Name']} (Lv {row['Proficiency Level']})
              </option>
            ))}
          </select>

          {recipe && (
            <>
              <RecipeDetails db={db} save={save} recipe={recipe} />
              <label className="field-label" htmlFor="recipe-qty">
                Quantity (max {maxQty}: materials {materialMax}, queue {queueMax})
              </label>
              <div className="production-qty-row">
                <button
                  id="recipe-qty"
                  type="button"
                  className="text-input qty-open-btn"
                  onClick={() => setQtyOpen(true)}
                >
                  {clampedQty.toLocaleString()}
                </button>
                <button
                  type="button"
                  className="btn secondary"
                  disabled={maxQty <= 0}
                  onClick={() => setQuantity(Math.max(1, maxQty))}
                >
                  Max
                </button>
              </div>
              <p className="muted tiny">
                Queue uses {(clampedQty * recipe['Base Duration Seconds']).toLocaleString()}s of the
                24h cap.
              </p>
              <button
                type="button"
                className="btn primary"
                disabled={maxQty <= 0}
                onClick={() => onConfirm(recipe['Recipe ID'], clampedQty)}
              >
                Start queue
              </button>
            </>
          )}
        </>
      )}

      {qtyOpen && recipe && (
        <QuantityNumpad
          title={recipe['Display Name']}
          subtitle="Queue quantity"
          details={
            <p className="muted tiny">
              Max {maxQty.toLocaleString()} (materials {materialMax}, queue {queueMax})
            </p>
          }
          confirmLabel="Set quantity"
          initialValue={clampedQty}
          max={Math.max(1, maxQty)}
          onCancel={() => setQtyOpen(false)}
          onConfirm={(next) => {
            setQuantity(next)
            setQtyOpen(false)
          }}
        />
      )}
    </section>
  )
}

function RecipeDetails({
  db,
  save,
  recipe,
}: {
  db: GameDatabase
  save: PlayerSave
  recipe: RecipeRow
}) {
  const ingredients = recipeIngredients(recipe)
  const output = db.Items.find((item) => item['Item ID'] === recipe['Output Item ID'])
  return (
    <div className="recipe-details">
      <div className="recipe-output">
        <ItemIcon item={output} />
        <div>
          <strong>
            {output?.['Display Name'] ?? recipe['Display Name']} ×{recipe['Output Quantity']}
          </strong>
          <p className="muted tiny">
            {recipe['Base Duration Seconds']}s · {recipe['XP Reward'].toLocaleString()} XP
          </p>
        </div>
      </div>
      <IngredientIconList
        ingredients={ingredients.map((ingredient) => ({
          itemId: ingredient.itemId,
          item: db.Items.find((row) => row['Item ID'] === ingredient.itemId),
          need: ingredient.quantity,
          owned: inventoryCount(save, ingredient.itemId),
        }))}
      />
    </div>
  )
}

interface ProductionProgressProps {
  db: GameDatabase
  activity: ActivityRow
  recipe: RecipeRow
  save: PlayerSave
  progress: number
  onStop: () => void
  /** Optional floating craft completion over the workstation. */
  craftPopup?: { itemId: string; name: string; key: number } | null
}

export function ProductionProgress({
  db,
  activity,
  recipe,
  save,
  progress,
  onStop,
  craftPopup = null,
}: ProductionProgressProps) {
  const total = save.productionQuantityTotal ?? 0
  const remaining = save.productionQuantityRemaining ?? 0
  const completed = Math.max(0, total - remaining)
  const clamped = Math.min(1, Math.max(0, progress))
  const pct = Math.round(clamped * 100)
  const craftSeconds = Math.max(0, (save.actionDurationMs ?? 0) / 1000)
  const craftRemainingSeconds = Math.max(0, craftSeconds - clamped * craftSeconds)
  const upcomingCrafts = Math.max(0, remaining - (remaining > 0 ? 1 : 0))
  const queueRemainingSeconds = craftRemainingSeconds + upcomingCrafts * craftSeconds
  const stationArt = workstationAssetPath(recipe['Facility ID'])
  const outputItem = db.Items.find((item) => item['Item ID'] === recipe['Output Item ID'])
  const popupItem = craftPopup
    ? db.Items.find((item) => item['Item ID'] === craftPopup.itemId)
    : undefined

  return (
    <section className="panel activity-panel gather-panel production-progress-panel" aria-label="Production">
      <div className="activity-panel-head">
        <div>
          <h2>{activity['Contextual Name'] ?? activity['Internal Key']}</h2>
          <p className="muted tiny">
            {recipe['Display Name']} · {completed}/{total} ·{' '}
            {formatDurationSeconds(queueRemainingSeconds)} left
          </p>
        </div>
        <button type="button" className="btn secondary" onClick={onStop}>
          Stop
        </button>
      </div>

      <div className="combat-layout gather-layout">
        <div className="combat-side combat-player-side">
          <div className="combat-portrait combat-portrait-player">
            <div
              className="combat-player-art"
              style={{ backgroundImage: `url(${playerCombatAssetPath()})` }}
              role="img"
              aria-label="Adventurer"
            />
          </div>
        </div>

        <div className="combat-side combat-enemy-side">
          <div className="combat-portrait combat-portrait-enemy production-station-portrait">
            <div
              className="combat-enemy-art gather-action-art production-station-art"
              style={{ backgroundImage: `url(${stationArt})` }}
              role="img"
              aria-label={recipe['Display Name']}
            />
            {craftPopup && (
              <div key={craftPopup.key} className="production-craft-float" aria-live="polite">
                <ItemIcon item={popupItem ?? outputItem} />
                <span>{craftPopup.name}</span>
              </div>
            )}
          </div>
          <div className="combat-meta combat-meta-enemy">
            <p className="combat-enemy-name">{recipe['Display Name']}</p>
          </div>
        </div>
      </div>

      <div className="gather-progress-row">
        <div
          className="combat-round-bar gather-progress-bar"
          role="progressbar"
          aria-label="Craft progress"
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={pct}
        >
          <div
            className="combat-round-bar-fill gather-progress-fill"
            style={{ transform: `scaleX(${clamped})` }}
          />
        </div>
        <p className="gather-progress-time muted tiny">
          {formatDurationSeconds(Math.max(0, craftSeconds - craftRemainingSeconds))} /{' '}
          {formatDurationSeconds(craftSeconds)}
        </p>
      </div>
    </section>
  )
}
