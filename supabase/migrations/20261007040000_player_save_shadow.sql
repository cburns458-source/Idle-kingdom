-- Wave G phase 1: the server keeps a shadow copy of each save and logs
-- diffs against client uploads. Clients cannot read or write these tables.
-- player_saves stays client-writable until phase 2.

create table if not exists public.player_save_shadows (
  user_id uuid primary key references auth.users (id) on delete cascade,
  last_client_payload jsonb not null,
  own_payload jsonb not null,
  advanced_to timestamptz not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.player_save_shadow_diffs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  initialized boolean not null default false,
  skipped boolean not null default false,
  matched boolean not null,
  own_matched boolean not null default true,
  diff_count int not null default 0,
  diffs jsonb not null default '{}'::jsonb,
  advance_ms double precision,
  unattended_ms double precision,
  effective_elapsed_ms bigint
);

create index if not exists player_save_shadow_diffs_user_created_idx
  on public.player_save_shadow_diffs (user_id, created_at desc);

comment on table public.player_save_shadows is
  'Server-owned save copies for Wave G shadow mode. Written only by the game function.';
comment on table public.player_save_shadow_diffs is
  'Logged diffs between a client upload and the TS-advanced previous upload.';

alter table public.player_save_shadows enable row level security;
alter table public.player_save_shadow_diffs enable row level security;

revoke all on table public.player_save_shadows from anon, authenticated;
revoke all on table public.player_save_shadow_diffs from anon, authenticated;

grant all on table public.player_save_shadows to service_role;
grant all on table public.player_save_shadow_diffs to service_role;
