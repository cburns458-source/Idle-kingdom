-- The Bazaar: a global order book with server-held escrow.
--
-- This is the first thing in the game the server decides rather than checks.
-- Everywhere else the client resolves play and the backend stores the result,
-- which is fine while a lie can only spoil one player's own save. A market
-- cannot work that way: a made-up sell order is minted gold in someone else's
-- purse, so the items and the gold a player offers have to leave a save the
-- server can see, and come back only through a box the server fills.
--
-- Nothing here is reachable from a client. Every table has row level security
-- on with no policy at all, and every function is revoked from anon and
-- authenticated, so the only way in is the `bazaar` edge function holding the
-- service role. That function is where a caller is identified and where the
-- inventory arithmetic happens; these routines are what make the result atomic.

-- One row per offer. Three may be open per account at a time, each in a numbered
-- slot so the screen can draw the same three boxes whatever is in them.
--
-- `quantity` is what was offered and never changes; `filled` is how much of it
-- has traded. A sell order escrows `quantity - filled` of `item_id`; a buy order
-- escrows `gold_escrow`, which is drawn down as it fills and returned on cancel.
create table if not exists public.bazaar_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  username text not null,
  side text not null check (side in ('buy', 'sell')),
  item_id text not null,
  unit_price bigint not null check (unit_price > 0),
  quantity bigint not null check (quantity > 0),
  filled bigint not null default 0 check (filled >= 0),
  gold_escrow bigint not null default 0 check (gold_escrow >= 0),
  slot smallint not null check (slot between 0 and 2),
  status text not null default 'open' check (status in ('open', 'filled', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint bazaar_orders_filled_fits check (filled <= quantity)
);

comment on column public.bazaar_orders.gold_escrow is
  'Gold the exchange holds for a buy order, always unit_price * (quantity - filled).';
comment on column public.bazaar_orders.slot is
  'Which of the three offer boxes this order occupies while it is open.';

-- A slot belongs to one open order, which is what makes three offers three.
create unique index if not exists bazaar_orders_open_slot_idx
  on public.bazaar_orders (user_id, slot)
  where status = 'open';

-- The read that matters: the resting side of a book, cheapest ask or best bid
-- first, oldest first at the same price.
create index if not exists bazaar_orders_book_idx
  on public.bazaar_orders (item_id, side, unit_price, created_at)
  where status = 'open';

create index if not exists bazaar_orders_owner_idx
  on public.bazaar_orders (user_id, created_at desc);

-- Every trade that has happened, which is both the shared price record and the
-- last-ten-trades list each player sees of their own dealing.
create table if not exists public.bazaar_fills (
  id uuid primary key default gen_random_uuid(),
  item_id text not null,
  unit_price bigint not null,
  quantity bigint not null,
  tax bigint not null default 0,
  buy_order_id uuid references public.bazaar_orders (id) on delete set null,
  sell_order_id uuid references public.bazaar_orders (id) on delete set null,
  buyer_id uuid references auth.users (id) on delete set null,
  seller_id uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

comment on column public.bazaar_fills.unit_price is
  'What the resting order asked, which is the price both sides dealt at.';
comment on column public.bazaar_fills.tax is
  'The 1% taken from the seller, charged only above 100 gold an item.';

create index if not exists bazaar_fills_buyer_idx
  on public.bazaar_fills (buyer_id, created_at desc);

create index if not exists bazaar_fills_seller_idx
  on public.bazaar_fills (seller_id, created_at desc);

create index if not exists bazaar_fills_item_idx
  on public.bazaar_fills (item_id, created_at desc);

-- The collection box. Nothing a trade produces goes straight into a save,
-- because the other player may be mid-tick on another device; it waits here
-- until they come and take it, the same as a cancelled order's remainder.
create table if not exists public.bazaar_collect (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  order_id uuid references public.bazaar_orders (id) on delete set null,
  item_id text,
  quantity bigint not null default 0 check (quantity >= 0),
  gold bigint not null default 0 check (gold >= 0),
  reason text not null check (reason in ('bought', 'sold', 'cancelled', 'refund')),
  created_at timestamptz not null default now(),
  constraint bazaar_collect_holds_something check (
    (item_id is not null and quantity > 0) or (item_id is null and gold > 0)
  )
);

comment on column public.bazaar_collect.reason is
  'bought and sold are trade proceeds; cancelled is an unfilled remainder; '
  'refund is the difference when a buy order bought below what it offered.';

create index if not exists bazaar_collect_owner_idx
  on public.bazaar_collect (user_id, created_at);

-- The guide price. Kept as a running number rather than recomputed from fills,
-- so drawing a list of items costs one read instead of one read an item.
create table if not exists public.bazaar_prices (
  item_id text primary key,
  average_price numeric not null,
  last_price bigint not null,
  volume bigint not null default 0,
  trades bigint not null default 0,
  updated_at timestamptz not null default now()
);

comment on column public.bazaar_prices.average_price is
  'Quantity-weighted rolling average: each trade of q units pulls the average '
  'q/(q + 100) of the way to its price, so one small deal cannot move a guide.';

-- Nothing signed in may touch any of this directly. RLS on with no policies is
-- a closed door for anon and authenticated; the service role goes around it.
alter table public.bazaar_orders enable row level security;
alter table public.bazaar_fills enable row level security;
alter table public.bazaar_collect enable row level security;
alter table public.bazaar_prices enable row level security;

revoke all on table public.bazaar_orders from anon, authenticated;
revoke all on table public.bazaar_fills from anon, authenticated;
revoke all on table public.bazaar_collect from anon, authenticated;
revoke all on table public.bazaar_prices from anon, authenticated;

grant all on table public.bazaar_orders to service_role;
grant all on table public.bazaar_fills to service_role;
grant all on table public.bazaar_collect to service_role;
grant all on table public.bazaar_prices to service_role;

-- 1% of the trade, floored, and only when an item is worth more than 100 gold
-- each. The threshold is the price per item, not the value of the offer, so
-- selling a thousand of something cheap is still untaxed.
create or replace function public.bazaar_tax(p_unit_price bigint, p_quantity bigint)
returns bigint
language sql
immutable
as $$
  select case
    when p_unit_price > 100 and p_quantity > 0 then (p_unit_price * p_quantity) / 100
    else 0::bigint
  end;
$$;

-- Folds one trade into an item's guide price.
create or replace function public.bazaar_note_price(
  p_item_id text,
  p_unit_price bigint,
  p_quantity bigint
)
returns void
language sql
as $$
  insert into public.bazaar_prices as prices (item_id, average_price, last_price, volume, trades)
  values (p_item_id, p_unit_price, p_unit_price, p_quantity, 1)
  on conflict (item_id) do update
     set average_price = prices.average_price
           + (excluded.last_price - prices.average_price)
             * (excluded.volume::numeric / (excluded.volume + 100)),
         last_price = excluded.last_price,
         volume = prices.volume + excluded.volume,
         trades = prices.trades + 1,
         updated_at = now();
$$;

-- Places an offer, matches it against the book, and stores the escrowed save,
-- all in one transaction.
--
-- [p_payload] is the caller's save with the offered items or gold already taken
-- out, worked out by the edge function against the copy stored here. That is
-- why [p_expected_updated_at] exists: if the stored save moved between the read
-- and this call, the arithmetic was done against something that no longer
-- applies, and the whole thing is refused rather than guessed at.
--
-- The resting order always sets the price. A buy order that offered more than
-- the cheapest ask pays the ask and gets the difference back; a sell order that
-- asked less than the best bid is paid the bid. Both are the same rule read from
-- either side, and both are why the incoming order can never do worse than the
-- price it named.
create or replace function public.bazaar_place_order(
  p_user_id uuid,
  p_username text,
  p_side text,
  p_item_id text,
  p_unit_price bigint,
  p_quantity bigint,
  p_payload jsonb,
  p_expected_updated_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stored timestamptz;
  v_slot smallint;
  v_open int;
  v_order public.bazaar_orders;
  v_rest public.bazaar_orders;
  v_remaining bigint := p_quantity;
  v_qty bigint;
  v_price bigint;
  v_tax bigint;
  v_spent bigint := 0;
  v_refund bigint := 0;
  v_earned bigint := 0;
  v_taxed bigint := 0;
  v_next timestamptz;
begin
  if p_side not in ('buy', 'sell') then
    raise exception 'BAZAAR_SIDE';
  end if;
  if p_unit_price <= 0 or p_quantity <= 0 then
    raise exception 'BAZAAR_AMOUNT';
  end if;

  select updated_at into v_stored
    from public.player_saves
   where user_id = p_user_id
     for update;
  if not found then
    raise exception 'BAZAAR_NO_SAVE';
  end if;
  if v_stored is distinct from p_expected_updated_at then
    raise exception 'BAZAAR_STALE';
  end if;

  -- One book at a time per item, so two arriving orders cannot both take the
  -- same resting quantity.
  perform pg_advisory_xact_lock(hashtext('bazaar:' || p_item_id));

  select count(*) into v_open
    from public.bazaar_orders
   where user_id = p_user_id and status = 'open';
  if v_open >= 3 then
    raise exception 'BAZAAR_NO_SLOTS';
  end if;

  select free.slot into v_slot
    from (select generate_series(0, 2)::smallint as slot) as free
   where not exists (
     select 1
       from public.bazaar_orders
      where bazaar_orders.user_id = p_user_id
        and bazaar_orders.status = 'open'
        and bazaar_orders.slot = free.slot
   )
   order by free.slot
   limit 1;
  if v_slot is null then
    raise exception 'BAZAAR_NO_SLOTS';
  end if;

  insert into public.bazaar_orders (
    user_id, username, side, item_id, unit_price, quantity, slot, gold_escrow
  ) values (
    p_user_id,
    p_username,
    p_side,
    p_item_id,
    p_unit_price,
    p_quantity,
    v_slot,
    case when p_side = 'buy' then p_unit_price * p_quantity else 0 end
  ) returning * into v_order;

  for v_rest in
    select *
      from public.bazaar_orders
     where status = 'open'
       and item_id = p_item_id
       and user_id <> p_user_id
       and side = case when p_side = 'buy' then 'sell' else 'buy' end
       and case when p_side = 'buy' then unit_price <= p_unit_price else unit_price >= p_unit_price end
     order by case when p_side = 'buy' then unit_price else -unit_price end, created_at
       for update
  loop
    exit when v_remaining <= 0;
    v_qty := least(v_remaining, v_rest.quantity - v_rest.filled);
    if v_qty <= 0 then
      continue;
    end if;
    v_price := v_rest.unit_price;
    v_tax := public.bazaar_tax(v_price, v_qty);
    v_remaining := v_remaining - v_qty;
    v_spent := v_spent + v_price * v_qty;

    insert into public.bazaar_collect (user_id, order_id, item_id, quantity, reason)
    values (
      case when p_side = 'buy' then p_user_id else v_rest.user_id end,
      case when p_side = 'buy' then v_order.id else v_rest.id end,
      p_item_id,
      v_qty,
      'bought'
    );

    insert into public.bazaar_collect (user_id, order_id, gold, reason)
    values (
      case when p_side = 'buy' then v_rest.user_id else p_user_id end,
      case when p_side = 'buy' then v_rest.id else v_order.id end,
      v_price * v_qty - v_tax,
      'sold'
    );

    insert into public.bazaar_fills (
      item_id, unit_price, quantity, tax, buy_order_id, sell_order_id, buyer_id, seller_id
    ) values (
      p_item_id,
      v_price,
      v_qty,
      v_tax,
      case when p_side = 'buy' then v_order.id else v_rest.id end,
      case when p_side = 'buy' then v_rest.id else v_order.id end,
      case when p_side = 'buy' then p_user_id else v_rest.user_id end,
      case when p_side = 'buy' then v_rest.user_id else p_user_id end
    );

    if p_side = 'buy' then
      v_refund := v_refund + (p_unit_price - v_price) * v_qty;
    else
      v_earned := v_earned + v_price * v_qty - v_tax;
      v_taxed := v_taxed + v_tax;
    end if;

    update public.bazaar_orders
       set filled = filled + v_qty,
           gold_escrow = case when side = 'buy' then gold_escrow - v_price * v_qty else 0 end,
           status = case when filled + v_qty >= quantity then 'filled' else 'open' end,
           updated_at = now()
     where id = v_rest.id;

    perform public.bazaar_note_price(p_item_id, v_price, v_qty);
  end loop;

  if v_refund > 0 then
    insert into public.bazaar_collect (user_id, order_id, gold, reason)
    values (p_user_id, v_order.id, v_refund, 'refund');
  end if;

  update public.bazaar_orders
     set filled = p_quantity - v_remaining,
         gold_escrow = case when p_side = 'buy' then p_unit_price * v_remaining else 0 end,
         status = case when v_remaining <= 0 then 'filled' else 'open' end,
         updated_at = now()
   where id = v_order.id
  returning * into v_order;

  v_next := coalesce((p_payload ->> 'updatedAt')::timestamptz, now());
  update public.player_saves
     set payload = p_payload,
         save_version = coalesce((p_payload ->> 'saveVersion')::int, save_version),
         updated_at = v_next
   where user_id = p_user_id;

  return jsonb_build_object(
    'order', to_jsonb(v_order),
    'traded', p_quantity - v_remaining,
    'spent', v_spent,
    'refunded', v_refund,
    'earned', v_earned,
    'tax', v_taxed,
    'updatedAt', v_next
  );
end;
$$;

-- Takes an offer off the book and puts what is left of it in the box.
--
-- A partly filled order cancels the same way as an untouched one: whatever
-- already traded is in the box already, and this returns only the remainder.
-- No save is touched, because a cancellation gives nothing back directly.
create or replace function public.bazaar_cancel_order(p_user_id uuid, p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.bazaar_orders;
  v_remaining bigint;
  v_gold bigint;
begin
  select * into v_order
    from public.bazaar_orders
   where id = p_order_id and user_id = p_user_id
     for update;
  if not found then
    raise exception 'BAZAAR_NO_ORDER';
  end if;
  if v_order.status <> 'open' then
    raise exception 'BAZAAR_CLOSED';
  end if;

  v_remaining := v_order.quantity - v_order.filled;
  v_gold := case when v_order.side = 'buy' then v_order.gold_escrow else 0 end;

  if v_order.side = 'sell' and v_remaining > 0 then
    insert into public.bazaar_collect (user_id, order_id, item_id, quantity, reason)
    values (p_user_id, v_order.id, v_order.item_id, v_remaining, 'cancelled');
  elsif v_gold > 0 then
    insert into public.bazaar_collect (user_id, order_id, gold, reason)
    values (p_user_id, v_order.id, v_gold, 'cancelled');
  end if;

  update public.bazaar_orders
     set status = 'cancelled', gold_escrow = 0, updated_at = now()
   where id = v_order.id
  returning * into v_order;

  return jsonb_build_object(
    'order', to_jsonb(v_order),
    'returnedQuantity', case when v_order.side = 'sell' then v_remaining else 0 end,
    'returnedGold', v_gold
  );
end;
$$;

-- Empties the named box rows into the save the edge function built from them.
--
-- The rows go and the save lands in the same transaction, so there is no moment
-- where a player has been charged the box and not paid the items. [p_ids] must
-- still all be there: a row that has already gone means this was worked out
-- against a box that has since changed, and the whole claim is refused.
create or replace function public.bazaar_settle_collect(
  p_user_id uuid,
  p_ids uuid[],
  p_payload jsonb,
  p_expected_updated_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stored timestamptz;
  v_wanted int := coalesce(array_length(p_ids, 1), 0);
  v_taken int;
  v_next timestamptz;
begin
  if v_wanted = 0 then
    raise exception 'BAZAAR_NOTHING';
  end if;

  select updated_at into v_stored
    from public.player_saves
   where user_id = p_user_id
     for update;
  if not found then
    raise exception 'BAZAAR_NO_SAVE';
  end if;
  if v_stored is distinct from p_expected_updated_at then
    raise exception 'BAZAAR_STALE';
  end if;

  with gone as (
    delete from public.bazaar_collect
     where user_id = p_user_id and id = any (p_ids)
    returning id
  )
  select count(*) into v_taken from gone;
  if v_taken <> v_wanted then
    raise exception 'BAZAAR_STALE';
  end if;

  v_next := coalesce((p_payload ->> 'updatedAt')::timestamptz, now());
  update public.player_saves
     set payload = p_payload,
         save_version = coalesce((p_payload ->> 'saveVersion')::int, save_version),
         updated_at = v_next
   where user_id = p_user_id;

  return jsonb_build_object('collected', v_taken, 'updatedAt', v_next);
end;
$$;

-- Only the edge function may call any of this. A player who could reach
-- bazaar_place_order themselves could hand it a save with gold added.
revoke all on function public.bazaar_tax(bigint, bigint) from public, anon, authenticated;
revoke all on function public.bazaar_note_price(text, bigint, bigint) from public, anon, authenticated;
revoke all on function public.bazaar_place_order(uuid, text, text, text, bigint, bigint, jsonb, timestamptz)
  from public, anon, authenticated;
revoke all on function public.bazaar_cancel_order(uuid, uuid) from public, anon, authenticated;
revoke all on function public.bazaar_settle_collect(uuid, uuid[], jsonb, timestamptz)
  from public, anon, authenticated;

grant execute on function public.bazaar_tax(bigint, bigint) to service_role;
grant execute on function public.bazaar_note_price(text, bigint, bigint) to service_role;
grant execute on function public.bazaar_place_order(uuid, text, text, text, bigint, bigint, jsonb, timestamptz)
  to service_role;
grant execute on function public.bazaar_cancel_order(uuid, uuid) to service_role;
grant execute on function public.bazaar_settle_collect(uuid, uuid[], jsonb, timestamptz) to service_role;
