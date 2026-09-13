-- What the exchange does, checked against a scratch database.
\set ON_ERROR_STOP on
\pset pager off

-- Two players: one carrying a hundred of something, one carrying gold.
truncate table public.bazaar_collect, public.bazaar_fills, public.bazaar_orders, public.bazaar_prices;
delete from public.player_saves;
delete from public.profiles;
delete from auth.users;

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222');

insert into public.player_saves (user_id, save_version, updated_at, payload) values
  ('11111111-1111-1111-1111-111111111111', 7, '2026-01-01T00:00:00Z',
   '{"saveVersion":7,"updatedAt":"2026-01-01T00:00:00.000Z","gold":0,"inventory":[{"itemId":"ITEM-0100","quantity":100}]}'),
  ('22222222-2222-2222-2222-222222222222', 7, '2026-01-01T00:00:00Z',
   '{"saveVersion":7,"updatedAt":"2026-01-01T00:00:00.000Z","gold":100000,"inventory":[]}');

\echo '--- tax: 100 is untaxed, 101 is not, and it is 1% floored ---'
select public.bazaar_tax(100, 10) as at_100,
       public.bazaar_tax(101, 1) as at_101_one,
       public.bazaar_tax(500, 3) as at_500_three,
       public.bazaar_tax(1000, 7) as at_1000_seven;

\echo '--- seller asks 500 for 40 ---'
select public.bazaar_place_order(
  '11111111-1111-1111-1111-111111111111', 'Seller', 'sell', 'ITEM-0100', 500, 40,
  '{"saveVersion":7,"updatedAt":"2026-01-01T00:01:00.000Z","gold":0,"inventory":[{"itemId":"ITEM-0100","quantity":60}]}',
  '2026-01-01T00:00:00Z'
) -> 'order' -> 'status' as status;

\echo '--- a stale expected timestamp is refused ---'
do $$
begin
  perform public.bazaar_place_order(
    '11111111-1111-1111-1111-111111111111', 'Seller', 'sell', 'ITEM-0100', 500, 10,
    '{}'::jsonb, '2020-01-01T00:00:00Z');
  raise exception 'stale write was allowed';
exception when others then
  if position('BAZAAR_STALE' in sqlerrm) = 0 then raise; end if;
  raise notice 'refused as expected: %', sqlerrm;
end $$;

\echo '--- buyer offers 600 for 25, so pays 500 and is owed 100 each back ---'
select public.bazaar_place_order(
  '22222222-2222-2222-2222-222222222222', 'Buyer', 'buy', 'ITEM-0100', 600, 25,
  '{"saveVersion":7,"updatedAt":"2026-01-01T00:02:00.000Z","gold":85000,"inventory":[]}',
  '2026-01-01T00:00:00Z'
) as placed;

\echo '--- the fill: 25 at 500, tax 125 ---'
select item_id, unit_price, quantity, tax from public.bazaar_fills;

\echo '--- the box: buyer gets items and change, seller gets gold less tax ---'
select case user_id::text
         when '11111111-1111-1111-1111-111111111111' then 'seller' else 'buyer' end as who,
       reason, item_id, quantity, gold
  from public.bazaar_collect
 order by who, reason;

\echo '--- the seller order is part filled, the buy order closed and freed its slot ---'
select side, quantity, filled, gold_escrow, slot, status from public.bazaar_orders order by side;

\echo '--- guide price after one trade of 25 units: 500, not moved by nothing ---'
select item_id, round(average_price) as average, last_price, volume, trades from public.bazaar_prices;

\echo '--- collecting: the box rows go and the save lands, in one go ---'
select public.bazaar_settle_collect(
  '22222222-2222-2222-2222-222222222222',
  array(select id from public.bazaar_collect where user_id = '22222222-2222-2222-2222-222222222222'),
  '{"saveVersion":7,"updatedAt":"2026-01-01T00:03:00.000Z","gold":87500,"inventory":[{"itemId":"ITEM-0100","quantity":25}]}',
  '2026-01-01T00:02:00Z'
) as settled;

select updated_at, payload -> 'gold' as gold from public.player_saves
 where user_id = '22222222-2222-2222-2222-222222222222';

\echo '--- claiming a box row twice is refused ---'
do $$
declare v_id uuid;
begin
  select id into v_id from public.bazaar_collect
   where user_id = '11111111-1111-1111-1111-111111111111' limit 1;
  perform public.bazaar_settle_collect(
    '11111111-1111-1111-1111-111111111111', array[v_id, gen_random_uuid()],
    '{"updatedAt":"2026-01-01T00:04:00.000Z"}'::jsonb, '2026-01-01T00:01:00Z');
  raise exception 'a missing box row was allowed';
exception when others then
  if position('BAZAAR_STALE' in sqlerrm) = 0 then raise; end if;
  raise notice 'refused as expected: %', sqlerrm;
end $$;

\echo '--- cancelling the part filled sell order returns only the remainder ---'
select public.bazaar_cancel_order(
  '11111111-1111-1111-1111-111111111111',
  (select id from public.bazaar_orders where side = 'sell')
) -> 'returnedQuantity' as returned_quantity;

select reason, item_id, quantity, gold from public.bazaar_collect
 where user_id = '11111111-1111-1111-1111-111111111111' order by reason;

\echo '--- cancelling twice is refused ---'
do $$
begin
  perform public.bazaar_cancel_order(
    '11111111-1111-1111-1111-111111111111',
    (select id from public.bazaar_orders where side = 'sell'));
  raise exception 'a closed order cancelled again';
exception when others then
  if position('BAZAAR_CLOSED' in sqlerrm) = 0 then raise; end if;
  raise notice 'refused as expected: %', sqlerrm;
end $$;

\echo '--- three slots, then no more ---'
delete from public.bazaar_orders;
update public.player_saves set updated_at = '2026-02-01T00:00:00Z'
 where user_id = '22222222-2222-2222-2222-222222222222';
select (public.bazaar_place_order('22222222-2222-2222-2222-222222222222', 'Buyer', 'buy',
  'ITEM-0200', 10, 1, '{"updatedAt":"2026-02-01T00:00:01.000Z"}'::jsonb, '2026-02-01T00:00:00Z')
  -> 'order' -> 'slot') as slot_one;
select (public.bazaar_place_order('22222222-2222-2222-2222-222222222222', 'Buyer', 'buy',
  'ITEM-0201', 10, 1, '{"updatedAt":"2026-02-01T00:00:02.000Z"}'::jsonb, '2026-02-01T00:00:01Z')
  -> 'order' -> 'slot') as slot_two;
select (public.bazaar_place_order('22222222-2222-2222-2222-222222222222', 'Buyer', 'buy',
  'ITEM-0202', 10, 1, '{"updatedAt":"2026-02-01T00:00:03.000Z"}'::jsonb, '2026-02-01T00:00:02Z')
  -> 'order' -> 'slot') as slot_three;
do $$
begin
  perform public.bazaar_place_order('22222222-2222-2222-2222-222222222222', 'Buyer', 'buy',
    'ITEM-0203', 10, 1, '{"updatedAt":"2026-02-01T00:00:04.000Z"}'::jsonb, '2026-02-01T00:00:03Z');
  raise exception 'a fourth offer was allowed';
exception when others then
  if position('BAZAAR_NO_SLOTS' in sqlerrm) = 0 then raise; end if;
  raise notice 'refused as expected: %', sqlerrm;
end $$;

\echo '--- cancelling one frees its slot for the next offer to reuse ---'
select public.bazaar_cancel_order('22222222-2222-2222-2222-222222222222',
  (select id from public.bazaar_orders where item_id = 'ITEM-0201')) -> 'returnedGold' as returned_gold;
select (public.bazaar_place_order('22222222-2222-2222-2222-222222222222', 'Buyer', 'buy',
  'ITEM-0204', 10, 1, '{"updatedAt":"2026-02-01T00:00:05.000Z"}'::jsonb, '2026-02-01T00:00:03Z')
  -> 'order' -> 'slot') as reused_slot;

\echo '--- an incoming sell below the best bid is paid the bid ---'
delete from public.bazaar_orders;
delete from public.bazaar_collect;
update public.player_saves set updated_at = '2026-03-01T00:00:00Z';
select public.bazaar_place_order('22222222-2222-2222-2222-222222222222', 'Buyer', 'buy',
  'ITEM-0300', 900, 10, '{"updatedAt":"2026-03-01T00:00:01.000Z"}'::jsonb, '2026-03-01T00:00:00Z')
  -> 'order' -> 'status' as bid_status;
select public.bazaar_place_order('11111111-1111-1111-1111-111111111111', 'Seller', 'sell',
  'ITEM-0300', 100, 10, '{"updatedAt":"2026-03-01T00:00:02.000Z"}'::jsonb, '2026-03-01T00:00:00Z')
  as sold_into_the_bid;

\echo '--- and no self dealing ---'
delete from public.bazaar_orders;
update public.player_saves set updated_at = '2026-04-01T00:00:00Z'
 where user_id = '22222222-2222-2222-2222-222222222222';
select public.bazaar_place_order('22222222-2222-2222-2222-222222222222', 'Buyer', 'sell',
  'ITEM-0400', 50, 5, '{"updatedAt":"2026-04-01T00:00:01.000Z"}'::jsonb, '2026-04-01T00:00:00Z')
  -> 'order' -> 'status' as own_ask;
select public.bazaar_place_order('22222222-2222-2222-2222-222222222222', 'Buyer', 'buy',
  'ITEM-0400', 50, 5, '{"updatedAt":"2026-04-01T00:00:02.000Z"}'::jsonb, '2026-04-01T00:00:01Z')
  -> 'traded' as traded_against_self;
