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
import { ItemIcon } from './itemIcons'

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
              <input
                id="recipe-qty"
                className="text-input"
                type="number"
                min={1}
                max={Math.max(1, maxQty)}
                value={clampedQty}
                onChange={(event) => setQuantity(Number(event.target.value) || 1)}
              />
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
      <ul className="plain-list recipe-ingredients">
        {ingredients.map((ingredient) => {
          const item = db.Items.find((row) => row['Item ID'] === ingredient.itemId)
          const owned = inventoryCount(save, ingredient.itemId)
          const short = owned < ingredient.quantity
          return (
            <li key={ingredient.itemId} className={short ? 'danger-note' : undefined}>
              {item?.['Display Name'] ?? ingredient.itemId} ×{ingredient.quantity}{' '}
              <span className="muted">(have {owned})</span>
            </li>
          )
        })}
      </ul>
    </div>
  )
}

interface ProductionProgressProps {
  activity: ActivityRow
  recipe: RecipeRow
  save: PlayerSave
  progress: number
  lastMessage: string | null
  onStop: () => void
}

export function ProductionProgress({
  activity,
  recipe,
  save,
  progress,
  lastMessage,
  onStop,
}: ProductionProgressProps) {
  const total = save.productionQuantityTotal ?? 0
  const remaining = save.productionQuantityRemaining ?? 0
  const completed = Math.max(0, total - remaining)
  const pct = Math.round(Math.min(1, Math.max(0, progress)) * 100)
  const totalSeconds = Math.max(0, (save.actionDurationMs ?? 0) / 1000)
  const elapsedSeconds = Math.min(totalSeconds, progress * totalSeconds)
  const output = recipe['Display Name']

  return (
    <section className="panel activity-panel">
      <div className="activity-panel-head">
        <div>
          <h2>{activity['Contextual Name'] ?? activity['Internal Key']}</h2>
          <p className="muted">Standard Production</p>
        </div>
        <button type="button" className="btn secondary" onClick={onStop}>
          Stop
        </button>
      </div>
      <p className="lead">
        Crafting <strong>{output}</strong>
      </p>
      <p className="muted">
        Queue {completed}/{total} done · {remaining} remaining
      </p>
      <div className="action-bar">
        <div className="action-bar-fill" style={{ width: `${pct}%` }} />
      </div>
      <p className="muted tiny">
        {Math.floor(elapsedSeconds)} / {Math.floor(totalSeconds)}s
      </p>
      {lastMessage && <p className="loot-message">{lastMessage}</p>}
    </section>
  )
}
