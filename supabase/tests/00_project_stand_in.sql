-- The parts of a Supabase project the Bazaar migration leans on, on a plain
-- Postgres. Enough to apply 024 and 005 against and mean something: the roles a
-- grant names, the auth schema a foreign key points at, `auth.uid()` as the real
-- one is written, and the two tables the exchange reads.
--
-- Not a substitute for the project. What it does check is the part that has to
-- be right the first time, because the alternative is finding out on a live
-- economy: that the arithmetic is what was intended, that a stale write is
-- refused, and that none of it is reachable by a signed-in client.
create extension if not exists pgcrypto;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if;
end $$;

create schema if not exists auth;
create table if not exists auth.users (id uuid primary key);

create table if not exists public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  username text,
  active_play_session_id uuid
);

create table if not exists public.player_saves (
  user_id uuid primary key references auth.users (id) on delete cascade,
  save_version int not null,
  updated_at timestamptz not null default now(),
  payload jsonb not null,
  play_session_id uuid
);

-- Reads the JWT PostgREST leaves in a GUC, the way the hosted one does. A
-- service key carries no `sub`, so a call the edge function makes has no
-- `auth.uid()`, which is what the play-session trigger sees.
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '')::uuid;
$$;

grant usage on schema public to anon, authenticated, service_role;
