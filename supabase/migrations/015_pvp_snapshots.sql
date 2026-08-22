-- Public fighter snapshots so the arena can find other hosted players.
--
-- Cloud saves stay self-only. The arena used to read this device's local
-- saves, which is why Find match said "No other players to fight" on a live
-- backend. Each account publishes a redacted combat snapshot that any
-- signed-in player may read.

create table if not exists public.pvp_snapshots (
  user_id uuid primary key references auth.users (id) on delete cascade,
  username text not null,
  combat_level integer not null default 1,
  total_level integer not null default 1,
  appearance_json jsonb not null default '{}'::jsonb,
  payload jsonb not null,
  updated_at timestamptz not null default now()
);

create index if not exists pvp_snapshots_username_idx
  on public.pvp_snapshots (username);

alter table public.pvp_snapshots enable row level security;

drop policy if exists "pvp snapshots readable" on public.pvp_snapshots;
create policy "pvp snapshots readable" on public.pvp_snapshots
  for select using (auth.role() = 'authenticated');

drop policy if exists "pvp snapshots insert self" on public.pvp_snapshots;
create policy "pvp snapshots insert self" on public.pvp_snapshots
  for insert with check (auth.uid() = user_id);

drop policy if exists "pvp snapshots update self" on public.pvp_snapshots;
create policy "pvp snapshots update self" on public.pvp_snapshots
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

comment on table public.pvp_snapshots is
  'Equipment snapshot published by Save equipment. Search and ranked read this, not the live cloud save. Readable by any signed-in player; only the owner writes.';
