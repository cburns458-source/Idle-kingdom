import { useEffect, useMemo, useRef, useState } from 'react'
import type { GameDatabase } from '../game/data/types'
import { inventoryCount } from '../game/production/recipes'
import type { PlayerSave } from '../game/save/types'
import { parseShopQuantity } from '../game/shops/quantity'
import {
  canAccessShop,
  getShop,
  playerBuyPrice,
  playerSellPrice,
  shopStockEntries,
} from '../game/shops/shops'
import { confirmShopOffer, type ShopOfferLine } from '../game/shops/transactions'
import { ItemIcon } from './itemIcons'

interface ShopPanelProps {
  db: GameDatabase
  save: PlayerSave
  shopId: string
  onClose: () => void
  onComplete: (save: PlayerSave, message: string) => void
}

type QtyDialog =
  | {
      mode: 'buy'
      itemId: string
      name: string
      unit: number
    }
  | {
      mode: 'sell'
      itemId: string
      name: string
      unit: number
      owned: number
      alreadyOffered: number
    }

function bumpLine(lines: ShopOfferLine[], itemId: string, delta: number): ShopOfferLine[] {
  const next = lines.map((line) => ({ ...line }))
  const existing = next.find((line) => line.itemId === itemId)
  if (!existing) {
    if (delta <= 0) return next
    return [...next, { itemId, quantity: delta }]
  }
  existing.quantity += delta
  return next.filter((line) => line.quantity > 0)
}

export function ShopPanel({ db, save, shopId, onClose, onComplete }: ShopPanelProps) {
  const shop = getShop(db, shopId)
  const access = shop ? canAccessShop(db, save, shop) : { ok: false as const, reason: 'Shop missing.' }
  const stock = shop ? shopStockEntries(shop) : []
  const [buys, setBuys] = useState<ShopOfferLine[]>([])
  const [sells, setSells] = useState<ShopOfferLine[]>([])
  const [error, setError] = useState<string | null>(null)
  const [qtyDialog, setQtyDialog] = useState<QtyDialog | null>(null)
  const [qtyText, setQtyText] = useState('1')
  const [qtyError, setQtyError] = useState<string | null>(null)
  const qtyInputRef = useRef<HTMLInputElement | null>(null)

  const sellable = useMemo(() => {
    if (!shop) return []
    return save.inventory
      .filter((stack) => !stack.enchantmentId)
      .map((stack) => {
        const unit = playerSellPrice(db, shop, stack.itemId)
        if (unit == null) return null
        return { itemId: stack.itemId, owned: stack.quantity, unit }
      })
      .filter((row): row is { itemId: string; owned: number; unit: number } => row != null)
  }, [db, save.inventory, shop])

  useEffect(() => {
    if (!qtyDialog) return
    qtyInputRef.current?.focus()
    qtyInputRef.current?.select()
  }, [qtyDialog])

  useEffect(() => {
    if (!qtyDialog) return
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') {
        event.preventDefault()
        setQtyDialog(null)
        setQtyError(null)
      }
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [qtyDialog])

  if (!shop) {
    return (
      <section className="panel glass-panel">
        <p className="lead">Shop unavailable.</p>
        <button type="button" className="btn secondary" onClick={onClose}>
          Close
        </button>
      </section>
    )
  }

  if (!access.ok) {
    return (
      <section className="panel glass-panel shop-panel">
        <div className="activity-panel-head">
          <div>
            <h2>{shop['Display Name']}</h2>
            <p className="muted">{shop.Description}</p>
          </div>
          <button type="button" className="btn secondary" onClick={onClose}>
            Close
          </button>
        </div>
        <p className="danger-note">{access.reason}</p>
      </section>
    )
  }

  const buyTotal = buys.reduce((sum, line) => {
    const unit = playerBuyPrice(db, shop, line.itemId) ?? 0
    return sum + unit * line.quantity
  }, 0)
  const sellTotal = sells.reduce((sum, line) => {
    const unit = playerSellPrice(db, shop, line.itemId) ?? 0
    return sum + unit * line.quantity
  }, 0)
  const net = sellTotal - buyTotal

  function openBuyDialog(itemId: string, unit: number, name: string) {
    setError(null)
    setQtyError(null)
    setQtyText('1')
    setQtyDialog({ mode: 'buy', itemId, unit, name })
  }

  function openSellDialog(itemId: string, unit: number, name: string, owned: number) {
    const alreadyOffered = sells.find((line) => line.itemId === itemId)?.quantity ?? 0
    setError(null)
    setQtyError(null)
    setQtyText('1')
    setQtyDialog({ mode: 'sell', itemId, unit, name, owned, alreadyOffered })
  }

  function applyQuantity() {
    if (!qtyDialog) return
    const max =
      qtyDialog.mode === 'sell'
        ? Math.max(0, qtyDialog.owned - qtyDialog.alreadyOffered)
        : undefined
    const parsed = parseShopQuantity(qtyText, max)
    if (!parsed.ok) {
      setQtyError(parsed.reason)
      return
    }
    setQtyError(null)
    if (qtyDialog.mode === 'buy') {
      setBuys((current) => bumpLine(current, qtyDialog.itemId, parsed.quantity))
    } else {
      setSells((current) => bumpLine(current, qtyDialog.itemId, parsed.quantity))
    }
    setQtyDialog(null)
  }

  function confirm() {
    const result = confirmShopOffer(db, save, shopId, { buys, sells })
    if (!result.ok) {
      setError(result.reason)
      return
    }
    setError(null)
    setBuys([])
    setSells([])
    onComplete(result.save, result.message)
  }

  const typedQty = /^\d+$/.test(qtyText.trim()) ? Number(qtyText.trim()) : 0
  const liveTotal =
    qtyDialog && typedQty >= 1 ? qtyDialog.unit * typedQty : null
  const sellRemaining =
    qtyDialog?.mode === 'sell'
      ? Math.max(0, qtyDialog.owned - qtyDialog.alreadyOffered)
      : null
  const buyAffordHint =
    qtyDialog?.mode === 'buy' && qtyDialog.unit > 0
      ? Math.max(0, Math.floor(save.gold / qtyDialog.unit))
      : null

  return (
    <section className="panel glass-panel shop-panel">
      <div className="activity-panel-head">
        <div>
          <h2>{shop['Display Name']}</h2>
          <p className="muted">{shop.Description}</p>
        </div>
        <button type="button" className="btn secondary" onClick={onClose}>
          Close
        </button>
      </div>

      <div className="shop-columns">
        <div>
          <h3>Store</h3>
          <ul className="shop-list">
            {stock.map((entry) => {
              const item = db.Items.find((row) => row['Item ID'] === entry.itemId)
              const unit = playerBuyPrice(db, shop, entry.itemId)
              const inOffer = buys.find((line) => line.itemId === entry.itemId)?.quantity ?? 0
              const name = item?.['Display Name'] ?? entry.itemId
              return (
                <li key={entry.itemId}>
                  <ItemIcon item={item} />
                  <div>
                    <strong>{name}</strong>
                    <p className="muted tiny">
                      {unit != null ? `${unit.toLocaleString()} gold` : 'No price'}
                      {inOffer > 0 ? ` · offer ${inOffer}` : ''}
                    </p>
                  </div>
                  <button
                    type="button"
                    className="btn secondary"
                    disabled={unit == null}
                    onClick={() => {
                      if (unit == null) return
                      openBuyDialog(entry.itemId, unit, name)
                    }}
                  >
                    Buy
                  </button>
                </li>
              )
            })}
            {stock.length === 0 && <li className="muted">No stock listed.</li>}
          </ul>
        </div>

        <div>
          <h3>Your items</h3>
          <ul className="shop-list">
            {sellable.map((row) => {
              const item = db.Items.find((entry) => entry['Item ID'] === row.itemId)
              const inOffer = sells.find((line) => line.itemId === row.itemId)?.quantity ?? 0
              const owned = inventoryCount(save, row.itemId)
              const name = item?.['Display Name'] ?? row.itemId
              return (
                <li key={row.itemId}>
                  <ItemIcon item={item} />
                  <div>
                    <strong>{name}</strong>
                    <p className="muted tiny">
                      {row.unit.toLocaleString()} gold · own {owned}
                      {inOffer > 0 ? ` · offer ${inOffer}` : ''}
                    </p>
                  </div>
                  <button
                    type="button"
                    className="btn secondary"
                    disabled={inOffer >= owned}
                    onClick={() => openSellDialog(row.itemId, row.unit, name, owned)}
                  >
                    Sell
                  </button>
                </li>
              )
            })}
            {sellable.length === 0 && <li className="muted">Nothing this shop will buy.</li>}
          </ul>
        </div>
      </div>

      <div className="shop-offer">
        <p className="lead">
          Offer — buy {buyTotal.toLocaleString()} / sell {sellTotal.toLocaleString()} · net{' '}
          {net >= 0 ? '+' : ''}
          {net.toLocaleString()} gold
        </p>
        <div className="shop-offer-actions">
          <button
            type="button"
            className="btn secondary"
            onClick={() => {
              setBuys([])
              setSells([])
              setError(null)
            }}
          >
            Clear offer
          </button>
          <button
            type="button"
            className="btn primary"
            disabled={buys.length === 0 && sells.length === 0}
            onClick={confirm}
          >
            Confirm trade
          </button>
        </div>
        {error && <p className="danger-note">{error}</p>}
      </div>

      {qtyDialog && (
        <div
          className="quest-reward-overlay shop-qty-overlay"
          role="dialog"
          aria-modal="true"
          aria-labelledby="shop-qty-title"
        >
          <div className="panel quest-reward-card shop-qty-card">
            <p className="muted tiny">{qtyDialog.mode === 'buy' ? 'Buy' : 'Sell'}</p>
            <h2 id="shop-qty-title">{qtyDialog.name}</h2>
            <p className="muted">
              {qtyDialog.unit.toLocaleString()} gold each
              {liveTotal != null ? ` · ${liveTotal.toLocaleString()} gold total` : ''}
            </p>
            {qtyDialog.mode === 'sell' && (
              <p className="lead shop-qty-available">
                Available in inventory: {qtyDialog.owned.toLocaleString()}
                {qtyDialog.alreadyOffered > 0
                  ? ` · ${sellRemaining?.toLocaleString() ?? 0} left to offer`
                  : ''}
              </p>
            )}
            {qtyDialog.mode === 'buy' && buyAffordHint != null && (
              <p className="muted tiny">Afford up to {buyAffordHint.toLocaleString()} with current gold</p>
            )}
            <label className="field-label" htmlFor="shop-qty-input">
              Amount
            </label>
            <div className="shop-qty-row">
              <input
                id="shop-qty-input"
                ref={qtyInputRef}
                className="text-input"
                type="text"
                inputMode="numeric"
                autoComplete="off"
                value={qtyText}
                onChange={(event) => {
                  setQtyText(event.target.value)
                  setQtyError(null)
                }}
                onKeyDown={(event) => {
                  if (event.key === 'Enter') {
                    event.preventDefault()
                    applyQuantity()
                  }
                }}
              />
              <button
                type="button"
                className="btn secondary"
                disabled={
                  qtyDialog.mode === 'sell'
                    ? (sellRemaining ?? 0) <= 0
                    : (buyAffordHint ?? 0) <= 0
                }
                onClick={() => {
                  if (qtyDialog.mode === 'sell') {
                    setQtyText(String(Math.max(1, sellRemaining ?? 1)))
                  } else {
                    setQtyText(String(Math.max(1, buyAffordHint ?? 1)))
                  }
                  setQtyError(null)
                }}
              >
                Max
              </button>
            </div>
            {qtyError && <p className="danger-note">{qtyError}</p>}
            <div className="button-row shop-qty-actions">
              <button
                type="button"
                className="btn secondary"
                onClick={() => {
                  setQtyDialog(null)
                  setQtyError(null)
                }}
              >
                Cancel
              </button>
              <button type="button" className="btn primary" onClick={applyQuantity}>
                Add to offer
              </button>
            </div>
          </div>
        </div>
      )}
    </section>
  )
}
