-- Smoke checks for migration 026 against the stand-in project.
\pset pager off

\i supabase/tests/00_project_stand_in.sql

-- Minimal tables 026 assumes beyond the bazaar stand-in.
create table if not exists public.guilds (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  tag text not null unique,
  description text not null default '',
  emblem jsonb not null default '{}'::jsonb,
  leader_id uuid not null references auth.users (id),
  join_policy text not null default 'open',
  guest_auto_accept boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.guild_members (
  guild_id uuid not null references public.guilds (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null,
  username text not null default '',
  appearance_json jsonb not null default '{}'::jsonb,
  total_level numeric not null default 1,
  joined_at timestamptz not null default now(),
  primary key (guild_id, user_id)
);

create table if not exists public.guild_guests (
  guild_id uuid not null references public.guilds (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  username text not null default '',
  appearance_json jsonb not null default '{}'::jsonb,
  joined_at timestamptz not null default now(),
  primary key (guild_id, user_id)
);

create table if not exists public.guild_projects (
  id uuid primary key default gen_random_uuid(),
  guild_id uuid not null references public.guilds (id) on delete cascade,
  name text not null,
  description text not null default '',
  goal_amount numeric not null,
  contributed numeric not null default 0,
  reward_label text not null default ''
);

create table if not exists public.guild_challenges (
  id uuid primary key default gen_random_uuid(),
  guild_id uuid not null references public.guilds (id) on delete cascade,
  name text not null,
  board_key text not null,
  goal_value numeric not null,
  current_value numeric not null default 0
);

create table if not exists public.guild_halls (
  guild_id uuid primary key references public.guilds (id) on delete cascade,
  debt_remaining numeric not null default 1000000,
  debt_paid_off boolean not null default false,
  debt_paid_by jsonb not null default '{}'::jsonb,
  storehouse jsonb not null default '[]'::jsonb,
  completed_tiers jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  channel_key text not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  username text not null,
  body text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.chat_cooldowns (
  user_id uuid not null references auth.users (id) on delete cascade,
  channel_key text not null,
  last_sent_at timestamptz not null default now(),
  primary key (user_id, channel_key)
);

create table if not exists public.player_blocks (
  user_id uuid not null references auth.users (id) on delete cascade,
  blocked_user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, blocked_user_id)
);

create table if not exists public.player_mutes (
  user_id uuid not null references auth.users (id) on delete cascade,
  muted_user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, muted_user_id)
);

create table if not exists public.chat_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users (id) on delete cascade,
  target_user_id uuid not null references auth.users (id) on delete cascade,
  reason text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.bazaar_posts (
  id uuid primary key default gen_random_uuid(),
  kind text not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  username text not null,
  body text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.leaderboard_snapshots (
  user_id uuid not null references auth.users (id) on delete cascade,
  board_key text not null,
  value numeric not null default 0,
  value_secondary numeric,
  updated_at timestamptz not null default now(),
  primary key (user_id, board_key)
);

alter table public.profiles
  add column if not exists username text,
  add column if not exists appearance_json jsonb not null default '{}'::jsonb,
  add column if not exists guild_id uuid,
  add column if not exists privacy_public_gear boolean not null default true,
  add column if not exists equipment_json jsonb,
  add column if not exists privacy_direct_messages text not null default 'public',
  add column if not exists privacy_local_chat text not null default 'public',
  add column if not exists name_color text,
  add column if not exists motto text,
  add column if not exists pet_cosmetic_id text,
  add column if not exists username_renamed_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

create table if not exists public.activity_presence (
  user_id uuid primary key references auth.users (id) on delete cascade,
  username text not null,
  appearance_json jsonb not null default '{}'::jsonb,
  location_id text not null,
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null
);

-- Helper functions 008 would have created.
create or replace function public.guild_role_of(p_guild uuid, p_user uuid)
returns text language sql stable security definer set search_path = public as $$
  select role from public.guild_members where guild_id = p_guild and user_id = p_user limit 1;
$$;

create or replace function public.is_guild_manager(p_guild uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.guild_role_of(p_guild, auth.uid()) in ('leader', 'officer'), false);
$$;

alter table public.profiles enable row level security;
alter table public.guilds enable row level security;
alter table public.guild_members enable row level security;
alter table public.guild_halls enable row level security;
alter table public.chat_messages enable row level security;
alter table public.activity_presence enable row level security;
alter table public.bazaar_posts enable row level security;

-- Stand-in for Supabase's default table grants to API roles.
grant select, insert, update, delete on all tables in schema public to authenticated;
grant select on all tables in schema public to anon;
grant usage on schema public to anon, authenticated;

\i supabase/migrations/026_rls_hardening.sql

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222');

insert into public.profiles (user_id, username, privacy_public_gear, equipment_json, active_play_session_id)
values
  ('11111111-1111-1111-1111-111111111111', 'Hero', false, '[{"itemId":"ITEM-0001"}]'::jsonb, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  ('22222222-2222-2222-2222-222222222222', 'Rival', true, '[{"itemId":"ITEM-0002"}]'::jsonb, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

\echo '--- public_profiles blanks hidden gear ---'
select username, equipment_json is null as gear_hidden
  from public.public_profiles
 where user_id = '11111111-1111-1111-1111-111111111111';

\echo '--- authenticated cannot read another profile row ---'
set request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222"}';
set role authenticated;
select count(*) as other_profiles_visible
  from public.profiles
 where user_id = '11111111-1111-1111-1111-111111111111';
reset role;
reset request.jwt.claims;

\echo '--- member cannot self-promote ---'
insert into public.guilds (id, name, tag, leader_id)
values ('33333333-3333-3333-3333-333333333333', 'Testers', 'TEST', '11111111-1111-1111-1111-111111111111');
insert into public.guild_members (guild_id, user_id, role, username)
values
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 'leader', 'Hero'),
  ('33333333-3333-3333-3333-333333333333', '22222222-2222-2222-2222-222222222222', 'recruit', 'Rival');

set request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222"}';
set role authenticated;
do $$ begin
  update public.guild_members
     set role = 'leader'
   where user_id = '22222222-2222-2222-2222-222222222222';
  raise exception 'self-promote was allowed';
exception when others then
  if sqlerrm like '%Only the guild leader%' then
    raise notice 'denied self-promote: %', sqlerrm;
  else
    raise;
  end if;
end $$;
select role as rival_role_after_failed_promote
  from public.guild_members
 where user_id = '22222222-2222-2222-2222-222222222222';
reset role;
reset request.jwt.claims;

\echo '--- contribute project is additive ---'
insert into public.guild_projects (id, guild_id, name, goal_amount, contributed)
values ('44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333', 'Store', 1000, 10);

set request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222"}';
set role authenticated;
select contributed from public.guild_contribute_project('44444444-4444-4444-4444-444444444444', 5);
reset role;
reset request.jwt.claims;

\echo '--- hall tiers view vs member hall ---'
insert into public.guild_halls (guild_id, storehouse, completed_tiers)
values (
  '33333333-3333-3333-3333-333333333333',
  '[{"itemId":"ITEM-0001","quantity":9}]'::jsonb,
  '["build_the_hall"]'::jsonb
);

set request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222"}';
set role authenticated;
select completed_tiers from public.guild_hall_tiers
 where guild_id = '33333333-3333-3333-3333-333333333333';
select storehouse from public.guild_halls
 where guild_id = '33333333-3333-3333-3333-333333333333';
reset role;
reset request.jwt.claims;

\echo '--- chat_cooldowns revoked from authenticated ---'
set role authenticated;
do $$ begin
  perform 1 from public.chat_cooldowns;
  raise exception 'authenticated could read chat_cooldowns';
exception when insufficient_privilege then
  raise notice 'denied chat_cooldowns: %', sqlerrm;
end $$;
reset role;
