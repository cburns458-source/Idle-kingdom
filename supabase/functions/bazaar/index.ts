// The Bazaar. Everything a player's offers can do to their save happens here.
//
// This is the one place in the game where the server decides rather than checks.
// Play is still resolved on the device: the client fights, gathers, crafts, and
// pushes the result. That is safe while a lie only spoils the liar's own save.
// An exchange is different, because a made-up sell order is gold appearing in
// somebody else's purse, so the items and the gold an offer costs are taken out
// of the copy of the save stored here, by this function, and come back only
// through a collection box this function fills.
//
// The shape of every write is the same:
//
//   1. identify the caller from their JWT
//   2. read the stored save with the service role
//   3. work out the new save with the same arithmetic the client uses
//   4. hand the new save and the book change to one RPC, which commits both
//
// Step 4 is where the atomicity lives (see `024_bazaar_market.sql`). Step 3 is
// where the arithmetic lives (see `../_shared/save_items.ts`). The RPCs are
// revoked from `authenticated`, so this function is the only way to reach them:
// a player who could call `bazaar_place_order` directly could hand it a save
// with the gold already added.
//
// The client is expected to have pushed its save before calling, and to adopt
// the save this returns afterwards. `expectedUpdatedAt` is how a client that did
// neither is told to try again instead of quietly losing an offer.

import { createClient } from 'npm:@supabase/supabase-js@2'

import {
  GOLD_CAP,
  giveGold,
  giveItems,
  goldOf,
  inventoryOf,
  isItemId,
  isTradableStack,
  stamped,
  takeGold,
  takeItems,
  tradableQuantity,
  type SavePayload,
} from '../_shared/save_items.ts'

/** Offers open at once, per account. */
const OFFER_SLOTS = 6

/** Box rows one claim will try to take. */
const COLLECT_BATCH = 40

/** Own trades the history list keeps. */
const HISTORY_LIMIT = 10

/** Guide prices a read hands back, busiest items first. */
const PRICE_LIMIT = 400

/** Resting orders a read looks at when building the book. */
const BOOK_LIMIT = 2000

/**
 * A client for this project, which has no generated `Database` type.
 *
 * Named rather than written as `ReturnType<typeof createClient>`, because that
 * resolves the generic *defaults* — where the schema is `never` — instead of the
 * client `createClient(url, key)` actually returns. Every row read through a
 * `never` schema is itself typed `never`, so `deno check` rejects reading any
 * column off it and the mistake looks like a dozen unrelated errors.
 */
function connect(url: string, key: string, options?: Parameters<typeof createClient>[2]) {
  return createClient(url, key, options)
}

type Client = ReturnType<typeof connect>

type OrderRow = {
  id: string
  user_id: string
  username: string
  side: string
  item_id: string
  unit_price: number
  quantity: number
  filled: number
  gold_escrow: number
  slot: number
  status: string
  created_at: string
  updated_at: string
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: cors() })
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return json({ error: 'Function is missing Supabase secrets.' }, 500)
  }

  const asUser = connect(supabaseUrl, anonKey, {
    global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
  })
  const { data: userData, error: userError } = await asUser.auth.getUser()
  const user = userData.user
  if (userError || !user) {
    return json({ error: 'Sign in to use the Bazaar.' }, 401)
  }

  let payload: Record<string, unknown>
  try {
    payload = (await req.json()) as Record<string, unknown>
  } catch {
    return refused('The Bazaar did not understand that.')
  }

  const admin = connect(supabaseUrl, serviceKey)
  const action = typeof payload.action === 'string' ? payload.action : ''

  try {
    switch (action) {
      case 'read':
        return await read(admin, user.id, payload)
      case 'place':
        return await place(admin, user.id, user.user_metadata, payload)
      case 'cancel':
        return await cancel(admin, user.id, payload)
      case 'collect':
        return await collect(admin, user.id)
      default:
        return refused('Unknown Bazaar action.')
    }
  } catch (error) {
    return refused(refusalFor(error))
  }
})

// --- Reads ------------------------------------------------------------------

/**
 * Everything the screen draws, in one call.
 *
 * The tables are closed to clients, so a read is a function call rather than a
 * query. That is also why the book comes back added up rather than row by row:
 * who is selling is nobody's business, only what is on offer at what price.
 */
async function read(
  admin: Client,
  userId: string,
  request: Record<string, unknown>,
): Promise<Response> {
  const itemId = isItemId(request.itemId) ? request.itemId : null

  const [own, resting, fills, finished, box, prices] = await Promise.all([
    admin
      .from('bazaar_orders')
      .select('*')
      .eq('user_id', userId)
      .eq('status', 'open')
      .order('slot'),
    admin
      .from('bazaar_orders')
      .select('item_id, side, unit_price, quantity, filled')
      .eq('status', 'open')
      .limit(BOOK_LIMIT),
    admin
      .from('bazaar_fills')
      .select('*')
      .or(`buyer_id.eq.${userId},seller_id.eq.${userId}`)
      .order('created_at', { ascending: false })
      .limit(HISTORY_LIMIT * 4),
    admin
      .from('bazaar_orders')
      .select('*')
      .eq('user_id', userId)
      .in('status', ['filled', 'cancelled'])
      .order('updated_at', { ascending: false })
      .limit(HISTORY_LIMIT * 4),
    admin.from('bazaar_collect').select('*').eq('user_id', userId).order('created_at'),
    admin
      .from('bazaar_prices')
      .select('*')
      .order('volume', { ascending: false })
      .limit(PRICE_LIMIT),
  ])

  const open = (resting.data ?? []) as Array<Record<string, unknown>>
  return json(
    {
      ok: true,
      orders: ((own.data ?? []) as OrderRow[]).map(orderJson),
      offers: aggregateOffers(open, itemId),
      market: summarizeMarket(open),
      trades: recentTrades(
        userId,
        (fills.data ?? []) as Array<Record<string, unknown>>,
        (finished.data ?? []) as OrderRow[],
      ),
      collect: ((box.data ?? []) as Array<Record<string, unknown>>).map(collectJson),
      prices: ((prices.data ?? []) as Array<Record<string, unknown>>).map(priceJson),
    },
    200,
  )
}

/** Resting quantity at each price on both sides of one item's book. */
function aggregateOffers(
  open: Array<Record<string, unknown>>,
  itemId: string | null,
): Array<Record<string, unknown>> {
  if (itemId == null) return []
  const totals = new Map<string, { side: string; unitPrice: number; quantity: number; orders: number }>()
  for (const row of open) {
    if (row.item_id !== itemId) continue
    const side = String(row.side)
    const unitPrice = Number(row.unit_price)
    const remaining = Number(row.quantity) - Number(row.filled)
    if (remaining <= 0) continue
    const key = `${side}:${unitPrice}`
    const held = totals.get(key)
    if (held) {
      held.quantity += remaining
      held.orders += 1
    } else {
      totals.set(key, { side, unitPrice, quantity: remaining, orders: 1 })
    }
  }
  return [...totals.values()]
    .sort((a, b) => (a.side === b.side ? b.unitPrice - a.unitPrice : a.side < b.side ? -1 : 1))
    .map((row) => ({ itemId, ...row }))
}

/** One line an item for the browse list: what it can be bought and sold for now. */
function summarizeMarket(open: Array<Record<string, unknown>>): Array<Record<string, unknown>> {
  const rows = new Map<
    string,
    { itemId: string; bestBid: number; bestAsk: number; buyQuantity: number; sellQuantity: number }
  >()
  for (const row of open) {
    const itemId = String(row.item_id)
    const unitPrice = Number(row.unit_price)
    const remaining = Number(row.quantity) - Number(row.filled)
    if (remaining <= 0) continue
    const held =
      rows.get(itemId) ??
      { itemId, bestBid: 0, bestAsk: 0, buyQuantity: 0, sellQuantity: 0 }
    if (row.side === 'buy') {
      held.buyQuantity += remaining
      held.bestBid = Math.max(held.bestBid, unitPrice)
    } else {
      held.sellQuantity += remaining
      held.bestAsk = held.bestAsk === 0 ? unitPrice : Math.min(held.bestAsk, unitPrice)
    }
    rows.set(itemId, held)
  }
  return [...rows.values()].sort((a, b) => a.itemId.localeCompare(b.itemId))
}

// --- Writes -----------------------------------------------------------------

/**
 * Takes the offer out of the stored save and puts it on the book.
 *
 * A sell order costs items out of the bag, never the bank: the server only ever
 * reads `inventory`, which is what makes "withdraw it first" a rule rather than
 * a reminder. A buy order costs the whole offer up front, and gets back
 * whatever it did not need.
 */
async function place(
  admin: Client,
  userId: string,
  metadata: Record<string, unknown> | undefined,
  request: Record<string, unknown>,
): Promise<Response> {
  const side = request.side === 'buy' || request.side === 'sell' ? request.side : null
  if (side == null) return refused('Choose to buy or to sell.')
  if (!isItemId(request.itemId)) return refused('That is not a tradable item.')
  const itemId = request.itemId

  const unitPrice = wholeNumber(request.unitPrice)
  const quantity = wholeNumber(request.quantity)
  if (unitPrice == null || unitPrice < 1 || unitPrice > GOLD_CAP) {
    return refused('Choose a price of at least 1 gold an item.')
  }
  if (quantity == null || quantity < 1) {
    return refused('Choose how many.')
  }
  if (unitPrice * quantity > GOLD_CAP) {
    return refused(`An offer cannot be worth more than ${formatGold(GOLD_CAP)} gold.`)
  }

  const stored = await loadSave(admin, userId)
  if ('error' in stored) return refused(stored.error)

  const open = await admin
    .from('bazaar_orders')
    .select('id')
    .eq('user_id', userId)
    .eq('status', 'open')
  if ((open.data ?? []).length >= OFFER_SLOTS) {
    return refused('All six offer slots are in use.')
  }

  let next: SavePayload | null
  if (side === 'sell') {
    if (heldEnchantedOrFavorited(stored.payload, itemId, quantity)) {
      return refused('Enchanted and favourited stacks stay with you. Unfavourite it to sell it.')
    }
    next = takeItems(stored.payload, itemId, quantity)
    if (next == null) {
      return refused(
        `You are carrying ${tradableQuantity(stored.payload, itemId)} of those. ` +
          'Withdraw more from the bank first.',
      )
    }
  } else {
    next = takeGold(stored.payload, unitPrice * quantity)
    if (next == null) {
      return refused(`That offer costs ${formatGold(unitPrice * quantity)} gold.`)
    }
  }

  const iso = new Date().toISOString()
  const escrowed = stamped(next, iso)
  const { data, error } = await admin.rpc('bazaar_place_order', {
    p_user_id: userId,
    p_username: await resolveUsername(admin, userId, metadata),
    p_side: side,
    p_item_id: itemId,
    p_unit_price: unitPrice,
    p_quantity: quantity,
    p_payload: escrowed,
    p_expected_updated_at: stored.updatedAt,
  })
  if (error) return refused(refusalFor(error))

  const result = (data ?? {}) as Record<string, unknown>
  const order = (result.order ?? {}) as OrderRow
  return json(
    {
      ok: true,
      save: escrowed,
      order: orderJson(order),
      traded: Number(result.traded ?? 0),
      spent: Number(result.spent ?? 0),
      refunded: Number(result.refunded ?? 0),
      earned: Number(result.earned ?? 0),
      tax: Number(result.tax ?? 0),
      message: placedMessage(side, order, Number(result.traded ?? 0)),
    },
    200,
  )
}

/**
 * Takes an offer off the book. What has not traded goes to the box.
 *
 * The save is not touched, which is why this needs no version check: a
 * cancellation gives nothing back directly, only something to come and collect.
 */
async function cancel(
  admin: Client,
  userId: string,
  request: Record<string, unknown>,
): Promise<Response> {
  const orderId = typeof request.orderId === 'string' ? request.orderId.trim() : ''
  if (!orderId) return refused('Choose an offer to cancel.')

  const { data, error } = await admin.rpc('bazaar_cancel_order', {
    p_user_id: userId,
    p_order_id: orderId,
  })
  if (error) return refused(refusalFor(error))

  const result = (data ?? {}) as Record<string, unknown>
  const returnedQuantity = Number(result.returnedQuantity ?? 0)
  const returnedGold = Number(result.returnedGold ?? 0)
  return json(
    {
      ok: true,
      order: orderJson((result.order ?? {}) as OrderRow),
      returnedQuantity,
      returnedGold,
      message:
        returnedQuantity > 0 || returnedGold > 0
          ? 'Offer cancelled. What was left is in the collection box.'
          : 'Offer cancelled.',
    },
    200,
  )
}

/**
 * Empties as much of the box into the save as will fit.
 *
 * A row is taken whole or left alone. Splitting one would mean remembering the
 * half that did not fit, and a bag with a free slot is a much easier thing for a
 * player to arrange than the game inventing a place to keep the rest.
 */
async function collect(admin: Client, userId: string): Promise<Response> {
  const stored = await loadSave(admin, userId)
  if ('error' in stored) return refused(stored.error)

  const box = await admin
    .from('bazaar_collect')
    .select('*')
    .eq('user_id', userId)
    .order('created_at')
    .limit(COLLECT_BATCH)
  const rows = (box.data ?? []) as Array<Record<string, unknown>>
  if (rows.length === 0) return refused('The collection box is empty.')

  let payload = stored.payload
  const taken: string[] = []
  let items = 0
  let gold = 0
  let left = 0
  for (const row of rows) {
    const itemId = typeof row.item_id === 'string' ? row.item_id : null
    const quantity = Number(row.quantity ?? 0)
    const coin = Number(row.gold ?? 0)
    const applied =
      itemId != null && quantity > 0
        ? giveItems(payload, itemId, quantity)
        : giveGold(payload, coin)
    if (applied == null) {
      left += 1
      continue
    }
    payload = applied
    taken.push(String(row.id))
    if (itemId != null && quantity > 0) items += quantity
    else gold += coin
  }

  if (taken.length === 0) {
    return refused(
      goldOf(payload) >= GOLD_CAP
        ? 'Your purse is full.'
        : 'Your bag is full. Make room and collect again.',
    )
  }

  const iso = new Date().toISOString()
  const filled = stamped(payload, iso)
  const { error } = await admin.rpc('bazaar_settle_collect', {
    p_user_id: userId,
    p_ids: taken,
    p_payload: filled,
    p_expected_updated_at: stored.updatedAt,
  })
  if (error) return refused(refusalFor(error))

  return json(
    {
      ok: true,
      save: filled,
      items,
      gold,
      left,
      message: collectedMessage(items, gold, left),
    },
    200,
  )
}

// --- Helpers ----------------------------------------------------------------

async function loadSave(
  admin: Client,
  userId: string,
): Promise<{ payload: SavePayload; updatedAt: string } | { error: string }> {
  const { data, error } = await admin
    .from('player_saves')
    .select('updated_at, payload')
    .eq('user_id', userId)
    .maybeSingle()
  if (error) return { error: refusalFor(error) }
  if (!data || typeof data.payload !== 'object' || data.payload == null) {
    return { error: 'Play a little and let the game save before trading.' }
  }
  return { payload: data.payload as SavePayload, updatedAt: String(data.updated_at) }
}

/**
 * True when the bag holds enough of the item only by counting stacks the
 * exchange will not take, so the refusal can say which rule got in the way.
 */
function heldEnchantedOrFavorited(
  payload: SavePayload,
  itemId: string,
  quantity: number,
): boolean {
  if (tradableQuantity(payload, itemId) >= quantity) return false
  let total = 0
  let blocked = false
  for (const stack of inventoryOf(payload)) {
    if (stack.itemId !== itemId) continue
    total += Math.floor(stack.quantity)
    if (!isTradableStack(stack)) blocked = true
  }
  return blocked && total >= quantity
}

function wholeNumber(value: unknown): number | null {
  const parsed = typeof value === 'number' ? value : Number(value)
  if (!Number.isFinite(parsed)) return null
  return Math.floor(parsed)
}

function placedMessage(side: string, order: OrderRow, traded: number): string {
  const verb = side === 'buy' ? 'Buying' : 'Selling'
  if (traded <= 0) return `${verb} offer placed.`
  if (order.status === 'filled') {
    return side === 'buy'
      ? 'Bought at once. Collect it from the box.'
      : 'Sold at once. Collect the gold from the box.'
  }
  return `${verb} offer placed; ${traded} traded straight away.`
}

function collectedMessage(items: number, gold: number, left: number): string {
  const parts: string[] = []
  if (items > 0) parts.push(`${items} item${items === 1 ? '' : 's'}`)
  if (gold > 0) parts.push(`${gold} gold`)
  const took = parts.length === 0 ? 'Collected.' : `Collected ${parts.join(' and ')}.`
  return left > 0 ? `${took} ${left} more would not fit.` : took
}

/** The refusals the RPCs raise, said the way a player would want to hear them. */
function refusalFor(error: unknown): string {
  const message =
    typeof error === 'object' && error != null && 'message' in error
      ? String((error as { message: unknown }).message)
      : String(error)
  if (message.includes('BAZAAR_STALE')) {
    return 'Your save moved while that was being placed. Try again.'
  }
  if (message.includes('BAZAAR_NO_SAVE')) {
    return 'Play a little and let the game save before trading.'
  }
  if (message.includes('BAZAAR_NO_SLOTS')) return 'All six offer slots are in use.'
  if (message.includes('BAZAAR_NO_ORDER')) return 'That offer is not yours.'
  if (message.includes('BAZAAR_CLOSED')) return 'That offer has already closed.'
  if (message.includes('BAZAAR_NOTHING')) return 'The collection box is empty.'
  if (message.includes('BAZAAR_SIDE')) return 'Choose to buy or to sell.'
  if (message.includes('BAZAAR_AMOUNT')) return 'Choose a price and a quantity.'
  if (message.includes('Signed in on another device')) return 'Signed in on another device.'
  return message || 'The Bazaar did not accept that.'
}

async function resolveUsername(
  admin: Client,
  userId: string,
  metadata: Record<string, unknown> | undefined,
): Promise<string> {
  const { data } = await admin
    .from('profiles')
    .select('username')
    .eq('user_id', userId)
    .maybeSingle()
  const fromProfile = typeof data?.username === 'string' ? data.username.trim() : ''
  if (fromProfile) return fromProfile.slice(0, 24)
  const fromMeta = typeof metadata?.username === 'string' ? metadata.username.trim() : ''
  return (fromMeta || 'Adventurer').slice(0, 24)
}

function orderJson(row: OrderRow): Record<string, unknown> {
  return {
    id: String(row.id ?? ''),
    side: String(row.side ?? ''),
    itemId: String(row.item_id ?? ''),
    unitPrice: Number(row.unit_price ?? 0),
    quantity: Number(row.quantity ?? 0),
    filled: Number(row.filled ?? 0),
    goldEscrow: Number(row.gold_escrow ?? 0),
    slot: Number(row.slot ?? 0),
    status: String(row.status ?? ''),
    createdAt: String(row.created_at ?? ''),
  }
}

function tradeJson(row: Record<string, unknown>, userId: string): Record<string, unknown> {
  return {
    id: String(row.id ?? ''),
    itemId: String(row.item_id ?? ''),
    unitPrice: Number(row.unit_price ?? 0),
    quantity: Number(row.quantity ?? 0),
    tax: Number(row.tax ?? 0),
    side: row.buyer_id === userId ? 'buy' : 'sell',
    status: 'filled',
    createdAt: String(row.created_at ?? ''),
  }
}

/** Fills from finished offers. Cancelled offers that never traded stay hidden. */
function recentTrades(
  userId: string,
  fills: Array<Record<string, unknown>>,
  finished: OrderRow[],
): Array<Record<string, unknown>> {
  const done = new Set(finished.map((row) => String(row.id)))
  return fills
    .filter((row) => {
      const orderId = row.buyer_id === userId ? row.buy_order_id : row.sell_order_id
      return typeof orderId === 'string' && done.has(orderId)
    })
    .map((row) => tradeJson(row, userId))
    .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)))
    .slice(0, HISTORY_LIMIT)
}

function collectJson(row: Record<string, unknown>): Record<string, unknown> {
  return {
    id: String(row.id ?? ''),
    itemId: typeof row.item_id === 'string' ? row.item_id : null,
    quantity: Number(row.quantity ?? 0),
    gold: Number(row.gold ?? 0),
    reason: String(row.reason ?? ''),
    createdAt: String(row.created_at ?? ''),
  }
}

function priceJson(row: Record<string, unknown>): Record<string, unknown> {
  return {
    itemId: String(row.item_id ?? ''),
    averagePrice: Math.round(Number(row.average_price ?? 0)),
    lastPrice: Number(row.last_price ?? 0),
    volume: Number(row.volume ?? 0),
    trades: Number(row.trades ?? 0),
  }
}

function formatGold(amount: number): string {
  return amount.toLocaleString('en-US')
}

function cors(): HeadersInit {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }
}

/**
 * A refusal the player is meant to read, answered 200 on purpose.
 *
 * The client reaches this through `functions.invoke`, which throws on any status
 * at or above 400 and hands the caller a stringified body rather than the reason
 * in it. A refusal is not a fault — "all six slots are in use" is the exchange
 * working — so it comes back as a result the client can read the message out of.
 * Genuine faults still answer 401 and 500.
 */
function refused(message: string): Response {
  return json({ ok: false, error: message }, 200)
}

function json(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors(), 'Content-Type': 'application/json' },
  })
}
