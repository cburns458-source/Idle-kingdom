-- BUG-02: the migration cancels open orders for untradeable items, and only those.
\set ON_ERROR_STOP on
\pset pager off

truncate table public.bazaar_collect, public.bazaar_fills, public.bazaar_orders, public.bazaar_prices;
delete from public.player_saves;
delete from public.profiles;
delete from auth.users;

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222');

-- Rows as the exchange would have left them, written directly: the function
-- that placed them no longer would.
insert into public.bazaar_orders
  (id, user_id, username, side, item_id, unit_price, quantity, filled, gold_escrow, slot, status)
values
  -- open Machete sell, 1 listed and none traded
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Seller',
   'sell', 'ITEM-0406', 250, 1, 0, 0, 0, 'open'),
  -- open Stolen Coin Purse sell, 5 listed and 2 traded
  ('aaaaaaaa-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'Seller',
   'sell', 'ITEM-0299', 10, 5, 2, 0, 1, 'open'),
  -- open Excavator's Pickaxe bid, 2 wanted at 100 with 200 held
  ('aaaaaaaa-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222222', 'Buyer',
   'buy', 'ITEM-0313', 100, 2, 0, 200, 0, 'open'),
  -- open Iron Ore sell: tradeable, must stay open
  ('aaaaaaaa-0000-0000-0000-000000000004', '22222222-2222-2222-2222-222222222222', 'Buyer',
   'sell', 'ITEM-0005', 30, 10, 0, 0, 1, 'open'),
  -- a Machete sale that already filled: history, left alone
  ('aaaaaaaa-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111', 'Seller',
   'sell', 'ITEM-0406', 250, 1, 1, 0, 2, 'filled');

\echo '--- apply the migration ---'
\i supabase/migrations/20261012170000_bazaar_cancel_untradeable_orders.sql

\echo '--- order statuses after ---'
select item_id, side, status, gold_escrow from public.bazaar_orders order by id;

\echo '--- what the box now owes ---'
select item_id, quantity, gold, reason from public.bazaar_collect order by item_id nulls first;

do $$
declare
  v_open integer;
begin
  select count(*) into v_open from public.bazaar_orders
   where status = 'open' and item_id in ('ITEM-0406', 'ITEM-0313', 'ITEM-0299', 'ITEM-0300');
  if v_open <> 0 then raise exception 'untradeable orders still open: %', v_open; end if;

  if (select status from public.bazaar_orders where id = 'aaaaaaaa-0000-0000-0000-000000000001')
     <> 'cancelled' then
    raise exception 'Machete sell order was not cancelled';
  end if;
  if not exists (
    select 1 from public.bazaar_collect
     where order_id = 'aaaaaaaa-0000-0000-0000-000000000001'
       and user_id = '11111111-1111-1111-1111-111111111111'
       and item_id = 'ITEM-0406' and quantity = 1 and reason = 'cancelled'
  ) then
    raise exception 'Machete was not returned through the collection box';
  end if;

  if not exists (
    select 1 from public.bazaar_collect
     where order_id = 'aaaaaaaa-0000-0000-0000-000000000002'
       and item_id = 'ITEM-0299' and quantity = 3 and reason = 'cancelled'
  ) then
    raise exception 'the untraded remainder of the coin purse order was not returned';
  end if;

  if not exists (
    select 1 from public.bazaar_collect
     where order_id = 'aaaaaaaa-0000-0000-0000-000000000003'
       and user_id = '22222222-2222-2222-2222-222222222222'
       and item_id is null and gold = 200 and reason = 'cancelled'
  ) then
    raise exception 'the pickaxe bid''s gold was not returned';
  end if;
  if (select gold_escrow from public.bazaar_orders where id = 'aaaaaaaa-0000-0000-0000-000000000003')
     <> 0 then
    raise exception 'the pickaxe bid still holds escrow';
  end if;

  if (select status from public.bazaar_orders where id = 'aaaaaaaa-0000-0000-0000-000000000004')
     <> 'open' then
    raise exception 'a tradeable order was touched';
  end if;
  if (select status from public.bazaar_orders where id = 'aaaaaaaa-0000-0000-0000-000000000005')
     <> 'filled' then
    raise exception 'a filled trade was touched';
  end if;
  if (select count(*) from public.bazaar_collect) <> 3 then
    raise exception 'expected exactly three box rows';
  end if;
  raise notice 'untradeable orders cancelled as expected';
end $$;

\echo '--- a second run finds nothing to do ---'
\i supabase/migrations/20261012170000_bazaar_cancel_untradeable_orders.sql
do $$
begin
  if (select count(*) from public.bazaar_collect) <> 3 then
    raise exception 're-running the migration paid out twice';
  end if;
end $$;
