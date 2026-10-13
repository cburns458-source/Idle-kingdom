-- ECO-01: new offers need total level 200; existing ones still fill and collect.
\set ON_ERROR_STOP on
\pset pager off

truncate table public.bazaar_collect, public.bazaar_fills, public.bazaar_orders, public.bazaar_prices;
delete from public.player_saves;
delete from public.profiles;
delete from auth.users;

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222');

-- Low: total 199. High: total 200. Grandfathered sell is inserted before the
-- trigger exists so the test can prove fills and collects still run.
insert into public.player_saves (user_id, save_version, updated_at, payload) values
  ('11111111-1111-1111-1111-111111111111', 7, '2026-01-01T00:00:00Z',
   '{"saveVersion":7,"updatedAt":"2026-01-01T00:00:00.000Z","gold":0,"inventory":[{"itemId":"ITEM-0100","quantity":60}],"skills":[{"skillId":"SKL-0001","level":199,"xp":0}]}'),
  ('22222222-2222-2222-2222-222222222222', 7, '2026-01-01T00:00:00Z',
   '{"saveVersion":7,"updatedAt":"2026-01-01T00:00:00.000Z","gold":100000,"inventory":[],"skills":[{"skillId":"SKL-0001","level":200,"xp":0}]}');

insert into public.bazaar_orders
  (id, user_id, username, side, item_id, unit_price, quantity, filled, gold_escrow, slot, status)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Low',
   'sell', 'ITEM-0100', 500, 40, 0, 0, 0, 'open');

\echo '--- apply ECO-01 ---'
\i supabase/migrations/20261013180000_eco01_bazaar_total_level_gate.sql

\echo '--- helper sums skill levels ---'
select public.bazaar_payload_total_level(
         '{"skills":[{"level":199}]}'::jsonb) as at_199,
       public.bazaar_payload_total_level(
         '{"skills":[{"level":100},{"level":100}]}'::jsonb) as at_200,
       public.bazaar_payload_total_level('{}'::jsonb) as missing,
       public.bazaar_user_total_level('11111111-1111-1111-1111-111111111111') as owner_199,
       public.bazaar_user_total_level('22222222-2222-2222-2222-222222222222') as owner_200;

do $$
begin
  if public.bazaar_payload_total_level('{"skills":[{"level":199}]}'::jsonb) <> 199 then
    raise exception '199 sum was wrong';
  end if;
  if public.bazaar_payload_total_level('{"skills":[{"level":100},{"level":100}]}'::jsonb) <> 200 then
    raise exception '200 sum was wrong';
  end if;
  if public.bazaar_payload_total_level('{}'::jsonb) <> 0 then
    raise exception 'missing skills should be 0';
  end if;
end $$;

\echo '--- 199 cannot place a new SELL ---'
do $$
begin
  perform public.bazaar_place_order(
    '11111111-1111-1111-1111-111111111111', 'Low', 'sell', 'ITEM-0100', 30, 1,
    '{"saveVersion":7,"updatedAt":"2026-01-01T00:01:00.000Z","gold":0,"inventory":[{"itemId":"ITEM-0100","quantity":59}],"skills":[{"skillId":"SKL-0001","level":199,"xp":0}]}',
    '2026-01-01T00:00:00Z');
  raise exception '199 sell was allowed';
exception when others then
  if position('BAZAAR_TOTAL_LEVEL' in sqlerrm) = 0 then raise; end if;
  raise notice '199 sell refused: %', sqlerrm;
end $$;

\echo '--- 199 cannot place a new BUY ---'
do $$
begin
  perform public.bazaar_place_order(
    '11111111-1111-1111-1111-111111111111', 'Low', 'buy', 'ITEM-0005', 10, 1,
    '{"saveVersion":7,"updatedAt":"2026-01-01T00:01:00.000Z","gold":0,"inventory":[{"itemId":"ITEM-0100","quantity":60}],"skills":[{"skillId":"SKL-0001","level":199,"xp":0}]}',
    '2026-01-01T00:00:00Z');
  raise exception '199 buy was allowed';
exception when others then
  if position('BAZAAR_TOTAL_LEVEL' in sqlerrm) = 0 then raise; end if;
  raise notice '199 buy refused: %', sqlerrm;
end $$;

\echo '--- 199 cannot insert a new order row directly ---'
do $$
begin
  insert into public.bazaar_orders
    (user_id, username, side, item_id, unit_price, quantity, slot, gold_escrow)
  values
    ('11111111-1111-1111-1111-111111111111', 'Low', 'sell', 'ITEM-0005', 10, 1, 1, 0);
  raise exception '199 direct insert was allowed';
exception when others then
  if position('BAZAAR_TOTAL_LEVEL' in sqlerrm) = 0 then raise; end if;
  raise notice '199 insert refused: %', sqlerrm;
end $$;

\echo '--- 200 can place a new SELL ---'
select public.bazaar_place_order(
  '22222222-2222-2222-2222-222222222222', 'High', 'sell', 'ITEM-0005', 30, 1,
  '{"saveVersion":7,"updatedAt":"2026-01-01T00:02:00.000Z","gold":100000,"inventory":[],"skills":[{"skillId":"SKL-0001","level":200,"xp":0}]}',
  '2026-01-01T00:00:00Z'
) -> 'order' -> 'status' as high_sell_status;

\echo '--- 200 buy fills the existing 199 sell ---'
select public.bazaar_place_order(
  '22222222-2222-2222-2222-222222222222', 'High', 'buy', 'ITEM-0100', 500, 10,
  '{"saveVersion":7,"updatedAt":"2026-01-01T00:03:00.000Z","gold":95000,"inventory":[],"skills":[{"skillId":"SKL-0001","level":200,"xp":0}]}',
  '2026-01-01T00:02:00Z'
) as high_buy_against_low;

\echo '--- existing 199 sell is part filled, not cancelled ---'
select side, item_id, quantity, filled, status
  from public.bazaar_orders
 where id = 'aaaaaaaa-0000-0000-0000-000000000001';

\echo '--- 199 owner can still collect ---'
select public.bazaar_settle_collect(
  '11111111-1111-1111-1111-111111111111',
  array(select id from public.bazaar_collect where user_id = '11111111-1111-1111-1111-111111111111'),
  '{"saveVersion":7,"updatedAt":"2026-01-01T00:04:00.000Z","gold":4950,"inventory":[{"itemId":"ITEM-0100","quantity":60}],"skills":[{"skillId":"SKL-0001","level":199,"xp":0}]}',
  '2026-01-01T00:00:00Z'
) as low_collected;

do $$
declare
  v_open integer;
  v_filled integer;
  v_box integer;
  v_orders integer;
begin
  select count(*) into v_open from public.bazaar_orders
   where user_id = '11111111-1111-1111-1111-111111111111' and status = 'open';
  if v_open <> 1 then
    raise exception 'grandfathered sell should still be open: %', v_open;
  end if;

  select filled into v_filled from public.bazaar_orders
   where id = 'aaaaaaaa-0000-0000-0000-000000000001';
  if v_filled <> 10 then
    raise exception 'grandfathered sell should have filled 10: %', v_filled;
  end if;

  select count(*) into v_box from public.bazaar_collect
   where user_id = '11111111-1111-1111-1111-111111111111';
  if v_box <> 0 then
    raise exception '199 collect left box rows: %', v_box;
  end if;

  select count(*) into v_orders from public.bazaar_orders
   where user_id = '11111111-1111-1111-1111-111111111111'
     and id <> 'aaaaaaaa-0000-0000-0000-000000000001';
  if v_orders <> 0 then
    raise exception '199 player placed a new order';
  end if;
end $$;
