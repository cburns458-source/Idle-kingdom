-- BUG-04: a save version conflict must roll back the claim / fight insert.
--
-- The functions return JSON, so a plain RETURN after INSERT would commit the
-- side table and leave the player unpaid. RAISE inside the function rolls the
-- insert back (function-level savepoint) before that JSON is returned.
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

insert into auth.users (id) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')
on conflict (id) do nothing;

insert into public.player_saves (user_id, save_version, payload, version)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 1, '{"gold": 10}'::jsonb, 3),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 1, '{"gold": 10}'::jsonb, 1)
on conflict (user_id) do update
   set payload = excluded.payload,
       version = excluded.version;

do $$
declare
  v_bounty jsonb;
  v_ranked jsonb;
  v_count integer;
  v_gold text;
  v_version integer;
begin
  v_bounty := public.bounty_turn_in_hosted(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '2026-08-12T21',
    'BNT-0001',
    'Hero',
    1,
    '{"gold": 75}'::jsonb,
    '{"gold": 50}'::jsonb,
    1,
    '2026-08-12T21:00:00Z'
  );
  if coalesce(v_bounty ->> 'conflict', '') <> 'true' then
    raise exception 'bounty conflict should be true, got %', v_bounty;
  end if;
  select count(*) into v_count from public.bounty_claims;
  if v_count <> 0 then
    raise exception 'bounty claim survived a save version conflict';
  end if;
  select payload ->> 'gold', version
    into v_gold, v_version
    from public.player_saves
   where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  if v_gold <> '10' or v_version <> 3 then
    raise exception 'bounty save changed on conflict: gold=% version=%', v_gold, v_version;
  end if;

  v_bounty := public.bounty_turn_in_hosted(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '2026-08-12T21',
    'BNT-0001',
    'Hero',
    3,
    '{"gold": 75}'::jsonb,
    '{"gold": 50}'::jsonb,
    1,
    '2026-08-12T21:00:00Z'
  );
  if v_bounty ->> 'firstCompleter' <> 'true' then
    raise exception 'bounty retry should take first place, got %', v_bounty;
  end if;
  select count(*) into v_count from public.bounty_claims;
  if v_count <> 1 then
    raise exception 'bounty retry did not record the claim';
  end if;

  v_ranked := public.ranked_pvp_record_hosted(
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    '11111111-1111-1111-1111-111111111111',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'win',
    1000,
    null,
    '[]'::jsonb,
    10,
    10,
    4,
    9,
    '{"gold": 1010}'::jsonb,
    1,
    '2026-08-13T18:00:00Z'
  );
  if coalesce(v_ranked ->> 'conflict', '') <> 'true' then
    raise exception 'ranked conflict should be true, got %', v_ranked;
  end if;
  select count(*) into v_count from public.ranked_pvp_results;
  if v_count <> 0 then
    raise exception 'fight row survived a save version conflict';
  end if;
  select payload ->> 'gold', version
    into v_gold, v_version
    from public.player_saves
   where user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  if v_gold <> '10' or v_version <> 1 then
    raise exception 'ranked save changed on conflict: gold=% version=%', v_gold, v_version;
  end if;

  v_ranked := public.ranked_pvp_record_hosted(
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    '11111111-1111-1111-1111-111111111111',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'win',
    1000,
    null,
    '[]'::jsonb,
    10,
    10,
    4,
    1,
    '{"gold": 1010}'::jsonb,
    1,
    '2026-08-13T18:00:00Z'
  );
  if v_ranked ->> 'alreadyPaid' <> 'false' then
    raise exception 'ranked retry should pay, got %', v_ranked;
  end if;
  select count(*) into v_count from public.ranked_pvp_results;
  if v_count <> 1 then
    raise exception 'ranked retry did not record the fight';
  end if;
end;
$$;
