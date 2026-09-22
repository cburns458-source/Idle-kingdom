-- Six open offers per account at the Bazaar, up from three.
--
-- The client draws one box per slot and the edge function counts them, but the
-- slot number is also a check constraint and a range inside
-- `bazaar_place_order`, so without this the fourth offer is refused by the
-- database instead of being placed.
--
-- Open orders keep the slots they already hold; only the ceiling moves.

do $$
declare
  v_name text;
begin
  for v_name in
    select conname
      from pg_constraint
     where conrelid = 'public.bazaar_orders'::regclass
       and contype = 'c'
       and pg_get_constraintdef(oid) ilike '%slot%'
  loop
    execute format('alter table public.bazaar_orders drop constraint %I', v_name);
  end loop;
end
$$;

alter table public.bazaar_orders
  add constraint bazaar_orders_slot_check check (slot between 0 and 5);

comment on column public.bazaar_orders.slot is
  'Which of the six offer boxes this order occupies while it is open.';

-- Verbatim from 024 apart from the slot ceiling: a plpgsql body cannot be
-- patched in place, so the whole routine is replaced.

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
  if v_open >= 6 then
    raise exception 'BAZAAR_NO_SLOTS';
  end if;

  select free.slot into v_slot
    from (select generate_series(0, 5)::smallint as slot) as free
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

-- Replacing a function resets its grants.
revoke all on function public.bazaar_place_order(uuid, text, text, text, bigint, bigint, jsonb, timestamptz)
  from public, anon, authenticated;
grant execute on function public.bazaar_place_order(uuid, text, text, text, bigint, bigint, jsonb, timestamptz)
  to service_role;
