# The Bazaar function's contract

What `supabase/functions/bazaar/index.ts` accepts and answers, and — more
importantly — what it decides for itself rather than taking on trust.

One endpoint, four actions, chosen by `action` in the body. The client reaches it
through `functions.invoke('bazaar', body)`; `packages/ik_net/lib/src/remote_service.dart`
is the only caller.

## What the function trusts

The request body carries **no gold, no inventory, and no save**. These six fields
are the whole of it:

| Field | Actions | Checked as |
| --- | --- | --- |
| `action` | all | one of `read`, `place`, `cancel`, `collect` |
| `itemId` | `read`, `place` | `/^ITEM-\d{3,6}$/` |
| `side` | `place` | exactly `buy` or `sell` |
| `unitPrice` | `place` | whole number, 1 to 1,000,000,000 |
| `quantity` | `place` | whole number, at least 1 |
| `orderId` | `cancel` | non-empty string, then checked to be the caller's own open order |

Everything else is read by the function itself:

- **Who is calling** comes from the `Authorization` JWT, through
  `auth.getUser()` on an anon-key client. Nothing in the body names a user, so a
  caller cannot act as somebody else. A request without a usable token is `401`.
- **What they are holding** comes from `player_saves`, read with the service role.
- **What the new save is** is computed here, by `takeItems`, `takeGold`,
  `giveItems`, and `giveGold` in `../_shared/save_items.ts`, against that stored
  row. The client is sent the result to adopt; it never supplies it.
- **What a trade is worth** is computed in SQL. `bazaar_tax` and the matching
  loop in `024_bazaar_market.sql` set the price and the tax, so the numbers the
  client named bound the offer but do not decide the settlement.

`p_expected_updated_at` carries the `updated_at` the payload was derived from.
The routine refuses if the stored row moved in between, so an offer is never
escrowed out of a save that no longer exists.

## Where the trust actually ends

The function does not trust the request. It does trust `player_saves`, and that
row is writable by the account that owns it:

```sql
create policy "saves are self only" on public.player_saves
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

That is not an oversight in the exchange; it is how the whole game works. Play is
resolved on the device and the result is stored, which is safe everywhere else
because a forged save only spoils the forger's own game. An exchange is the first
place it stops being self-contained: a forged save can be sold, and the gold that
comes back is real gold out of a real player's purse.

So the honest summary of what is and is not closed:

- **Closed.** Spending gold you do not have, listing items you are not carrying,
  listing from the bank, listing an enchanted or favourited stack, taking a
  fourth slot, cancelling somebody else's offer, collecting a box twice, paying a
  seller the wrong price, or losing the escrow to a half-applied write. All of
  these are decided server-side and settled in one transaction.
- **Open.** Inflating your own save first and then selling the result. Nothing
  here can tell an honest thousand logs from a forged thousand logs, because
  nothing in the game watches them being gathered.

Closing that last one means the server resolving play, not a change to this
function. Until then the exchange is as tight as it can be given what is on the
other side of it, and the exposure is worth knowing about rather than discovering.

## Routes

Refusals a player is meant to read answer **200** with `{"ok": false, "error": "..."}`.
This is deliberate: `functions.invoke` throws on any status at or above 400 and
hands the caller a stringified body rather than the reason inside it, and "all
three slots are in use" is the exchange working rather than a fault. Genuine
faults answer `401` (no usable token) and `500` (missing function secrets).

### `read`

```jsonc
{ "action": "read", "itemId": "ITEM-0005" }   // itemId optional
```

```jsonc
{
  "ok": true,
  "orders":  [{ "id": "…", "side": "sell", "itemId": "ITEM-0005", "unitPrice": 30,
                "quantity": 60, "filled": 10, "goldEscrow": 0, "slot": 0,
                "status": "open", "createdAt": "…" }],
  "offers":  [{ "itemId": "ITEM-0005", "side": "sell", "unitPrice": 30,
                "quantity": 50, "orders": 2 }],
  "market":  [{ "itemId": "ITEM-0005", "bestBid": 25, "bestAsk": 30,
                "buyQuantity": 10, "sellQuantity": 50 }],
  "trades":  [{ "id": "…", "itemId": "ITEM-0005", "unitPrice": 30, "quantity": 10,
                "tax": 0, "side": "sell", "createdAt": "…" }],
  "collect": [{ "id": "…", "itemId": null, "quantity": 0, "gold": 200,
                "reason": "refund", "createdAt": "…" }],
  "prices":  [{ "itemId": "ITEM-0005", "averagePrice": 28, "lastPrice": 30,
                "volume": 500, "trades": 12 }]
}
```

`orders` is the caller's own open offers, at most three. `offers` is the depth of
one item's book and is empty unless `itemId` was named — the book comes back added
up rather than row by row, because who is selling is nobody's business. `market`
is one line per item with anything resting, for browsing. `trades` is the caller's
own last ten, newest first, with `side` being which side of it they were on.
`collect` has `itemId: null` on a gold entry, and `reason` is one of `bought`,
`sold`, `cancelled`, `refund`.

### `place`

```jsonc
{ "action": "place", "side": "sell", "itemId": "ITEM-0005",
  "unitPrice": 30, "quantity": 60 }
```

```jsonc
{
  "ok": true,
  "save": { /* the escrowed save, for the client to adopt */ },
  "order": { /* as in orders above */ },
  "traded": 10, "spent": 300, "refunded": 0, "earned": 0, "tax": 0,
  "message": "Selling offer placed; 10 traded straight away."
}
```

A sell order costs items out of `inventory` only, which is what makes "withdraw
it from the bank first" a rule rather than a reminder. A buy order costs the whole
offer up front and gets back what it did not need. Matching happens in the same
transaction: the resting order names the price, so a buy above the cheapest ask
pays the ask and is refunded the difference, and a sell below the best bid is paid
the bid. Anything that trades goes to the collection box, never straight into a
save — the other player may be mid-tick on another device.

### `cancel`

```jsonc
{ "action": "cancel", "orderId": "…" }
```

```jsonc
{ "ok": true, "order": { /* now cancelled */ },
  "returnedQuantity": 50, "returnedGold": 0,
  "message": "Offer cancelled. What was left is in the collection box." }
```

Works the same on a part-filled offer: what already traded is in the box already,
and this returns only the remainder. No save is written, which is why this needs
no version check.

### `collect`

```jsonc
{ "action": "collect" }
```

```jsonc
{ "ok": true, "save": { /* … */ }, "items": 10, "gold": 200, "left": 0,
  "message": "Collected 10 items and 200 gold." }
```

Up to 40 rows a claim, oldest first. A row is taken whole or left alone, and
`left` counts the ones that would not fit — splitting a row would mean
remembering the half that did not, and a free bag slot is an easier thing for a
player to arrange than the game inventing somewhere to keep the rest.

## Limits

| | |
| --- | --- |
| Offers open per account | 3 |
| Own trades kept in history | 10 |
| Box rows per claim | 40 |
| Guide prices per read | 400, busiest first |
| Resting orders read for the book | 2000 |
| Most an offer may be worth | 1,000,000,000 gold, matching the cap a save is validated against |
| Tax | 1% of the trade, floored, only above 100 gold **per item** |

## Deploying

```bash
supabase functions deploy bazaar
```

Needs `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY`, all
of which Supabase injects into deployed functions. `verify_jwt` is on, declared in
`supabase/config.toml`. `supabase/migrations/024_bazaar_market.sql` has to be
applied first, or every action refuses.
