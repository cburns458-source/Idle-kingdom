import { useMemo, useState } from 'react'
import type { GameDatabase } from '../game/data/types'
import { inventoryCount } from '../game/production/recipes'
import type { PlayerSave } from '../game/save/types'
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
              return (
                <li key={entry.itemId}>
                  <ItemIcon item={item} />
                  <div>
                    <strong>{item?.['Display Name'] ?? entry.itemId}</strong>
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
                      setError(null)
                      setBuys((current) => bumpLine(current, entry.itemId, 1))
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
              return (
                <li key={row.itemId}>
                  <ItemIcon item={item} />
                  <div>
                    <strong>{item?.['Display Name'] ?? row.itemId}</strong>
                    <p className="muted tiny">
                      {row.unit.toLocaleString()} gold · own {owned}
                      {inOffer > 0 ? ` · offer ${inOffer}` : ''}
                    </p>
                  </div>
                  <button
                    type="button"
                    className="btn secondary"
                    disabled={inOffer >= owned}
                    onClick={() => {
                      setError(null)
                      setSells((current) => {
                        const have = inventoryCount(save, row.itemId)
                        const offered =
                          current.find((line) => line.itemId === row.itemId)?.quantity ?? 0
                        if (offered >= have) return current
                        return bumpLine(current, row.itemId, 1)
                      })
                    }}
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
    </section>
  )
}
