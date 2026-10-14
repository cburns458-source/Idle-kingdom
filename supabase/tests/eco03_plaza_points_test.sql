-- ECO-03: ranked / bounty / shop payouts grant plaza points, never gold.
\pset pager off

create extension if not exists pgcrypto;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if;
end $$;

create schema if not exists auth;
create table if not exists auth.users (id uuid primary key);

create table if not exists public.player_saves (
  user_id uuid primary key references auth.users (id) on delete cascade,
  save_version int not null default 1,
  updated_at timestamptz not null default now(),
  payload jsonb not null
);

alter table public.player_saves add column if not exists version integer not null default 1;
alter table public.player_saves add column if not exists advanced_to timestamptz;
alter table public.player_saves add column if not exists rng_state bigint not null default 1;

create table if not exists public.bounty_claims (
  hour_key text not null,
  bounty_id text not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  username text not null,
  claimed_at timestamptz not null default now(),
  primary key (hour_key, bounty_id)
);

\i supabase/migrations/20261013120000_ranked_pvp_results_and_bounty_claims.sql
\i supabase/migrations/20261013200000_eco03_plaza_points_payouts.sql

truncate table public.ranked_pvp_results, public.bounty_claims;

insert into auth.users (id) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')
on conflict (id) do nothing;

insert into public.player_saves (user_id, save_version, payload, version)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 63,
   '{"gold": 40, "plazaPoints": 10, "rankedPvpDayKey": "2026-08-13", "rankedPvpFightsToday": 0}'::jsonb, 1),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 63,
   '{"gold": 99, "plazaPoints": 5}'::jsonb, 1)
on conflict (user_id) do update
   set payload = excluded.payload,
       version = excluded.version;

do $$
declare
  v_ranked jsonb;
  v_bounty jsonb;
  v_shop jsonb;
  v_gold text;
  v_points text;
begin
  -- (1) ranked win grants exactly 25 points and 0 gold, ignoring p_gold_paid
  v_ranked := public.ranked_pvp_record_hosted(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '11111111-1111-1111-1111-111111111111',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'win',
    1000,
    null,
    '[]'::jsonb,
    10, 10, 4, 1,
    '{"gold": 9999, "plazaPoints": 8888}'::jsonb,
    1,
    '2026-08-13T18:00:00Z'
  );
  if v_ranked ->> 'ok' <> 'true' then
    raise exception 'ranked win failed: %', v_ranked;
  end if;
  if (v_ranked ->> 'pointsGained')::int <> 25 then
    raise exception 'ranked win should pay 25 points, got %', v_ranked;
  end if;
  if coalesce(v_ranked ->> 'goldPaid', '0') <> '0' then
    raise exception 'ranked win paid gold: %', v_ranked;
  end if;
  select payload ->> 'gold', payload ->> 'plazaPoints'
    into v_gold, v_points
    from public.player_saves
   where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  if v_gold <> '40' then
    raise exception 'ranked win changed gold: %', v_gold;
  end if;
  if v_points <> '35' then
    raise exception 'ranked win points should be 10+25=35, got %', v_points;
  end if;

  -- (2) bounty points round down (catalog integers; floor of 40+25 is 65)
  if public.bounty_plaza_points('BNT-0001', true) <> 65 then
    raise exception 'first-place BNT-0001 should be 65';
  end if;
  if public.bounty_plaza_points('BNT-0001', false) <> 40 then
    raise exception 'later BNT-0001 should be 40';
  end if;

  v_bounty := public.bounty_turn_in_hosted(
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    '2026-08-13T18',
    'BNT-0001',
    'Hero',
    1,
    '{"gold": 5000, "plazaPoints": 999}'::jsonb,
    '{"gold": 4000, "plazaPoints": 111}'::jsonb,
    1,
    '2026-08-13T18:00:00Z'
  );
  if v_bounty ->> 'firstCompleter' <> 'true' then
    raise exception 'bounty should be first: %', v_bounty;
  end if;
  if (v_bounty ->> 'pointsGained')::int <> 65 then
    raise exception 'bounty should pay 65 points, got %', v_bounty;
  end if;
  select payload ->> 'gold', payload ->> 'plazaPoints'
    into v_gold, v_points
    from public.player_saves
   where user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  if v_gold <> '99' then
    raise exception 'bounty changed gold: %', v_gold;
  end if;
  if v_points <> '70' then
    raise exception 'bounty points should be 5+65=70, got %', v_points;
  end if;

  -- (3) shop purchase with insufficient points is refused and nothing deducted
  update public.player_saves
     set payload = '{"gold": 40, "plazaPoints": 209}'::jsonb,
         version = 2
   where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  v_shop := public.plaza_shop_purchase_hosted(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'ITEM-0428',
    2,
    '{"gold": 0, "plazaPoints": 0, "inventory": [{"itemId":"ITEM-0428","quantity":1}]}'::jsonb,
    1,
    '2026-08-13T18:00:00Z'
  );
  if v_shop ->> 'ok' <> 'false' or position('Not enough plaza points' in v_shop ->> 'reason') = 0 then
    raise exception 'short shop buy should refuse: %', v_shop;
  end if;
  select payload ->> 'plazaPoints', payload ->> 'gold', version
    into v_points, v_gold
    from public.player_saves
   where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  if v_points <> '209' or v_gold <> '40' then
    raise exception 'short shop buy deducted: points=% gold=%', v_points, v_gold;
  end if;

  -- (4) client-supplied amounts are ignored (payload gold/points overwritten)
  v_shop := public.plaza_shop_purchase_hosted(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'ITEM-0431',
    2,
    '{"gold": 1, "plazaPoints": 9999, "inventory": [{"itemId":"ITEM-0431","quantity":1}]}'::jsonb,
    1,
    '2026-08-13T18:00:00Z'
  );
  if v_shop ->> 'ok' <> 'true' then
    raise exception 'boot buy should succeed: %', v_shop;
  end if;
  if (v_shop ->> 'pointsSpent')::int <> 120 then
    raise exception 'boot should cost 120, got %', v_shop;
  end if;
  select payload ->> 'gold', payload ->> 'plazaPoints'
    into v_gold, v_points
    from public.player_saves
   where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  if v_gold <> '40' then
    raise exception 'shop buy changed gold from client payload: %', v_gold;
  end if;
  if v_points <> '89' then
    raise exception 'shop should leave 209-120=89, got %', v_points;
  end if;
end;
$$;
