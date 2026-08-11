-- Idle Kingdoms multiplayer scaffold (Supabase / Postgres)
-- Apply in a Supabase project; local demo mode does not require this file.

create extension if not exists "pgcrypto";

create table if not exists public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique,
  appearance_json jsonb not null default '{}'::jsonb,
  guild_id uuid null,
  privacy_public_skills boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.player_saves (
  user_id uuid primary key references auth.users (id) on delete cascade,
  save_version int not null,
  updated_at timestamptz not null default now(),
  payload jsonb not null
);

create table if not exists public.leaderboard_snapshots (
  user_id uuid not null references auth.users (id) on delete cascade,
  board_key text not null,
  value numeric not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, board_key)
);

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  channel_key text not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  username text not null,
  body text not null,
  created_at timestamptz not null default now()
);

create index if not exists chat_messages_channel_created_idx
  on public.chat_messages (channel_key, created_at desc);

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

create table if not exists public.guilds (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text not null default '',
  emblem text not null default '',
  leader_id uuid not null references auth.users (id),
  created_at timestamptz not null default now()
);

alter table public.profiles
  drop constraint if exists profiles_guild_id_fkey;
alter table public.profiles
  add constraint profiles_guild_id_fkey
  foreign key (guild_id) references public.guilds (id) on delete set null;

create table if not exists public.guild_members (
  guild_id uuid not null references public.guilds (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('leader', 'officer', 'member')),
  joined_at timestamptz not null default now(),
  primary key (guild_id, user_id)
);

create table if not exists public.guild_applications (
  id uuid primary key default gen_random_uuid(),
  guild_id uuid not null references public.guilds (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  message text not null default '',
  created_at timestamptz not null default now(),
  unique (guild_id, user_id)
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

create table if not exists public.activity_presence (
  user_id uuid primary key references auth.users (id) on delete cascade,
  username text not null,
  appearance_json jsonb not null default '{}'::jsonb,
  guild_name text null,
  location_id text not null,
  current_activity_id text null,
  skill_id text null,
  skill_level int null,
  outfit_cosmetic_id text null,
  mount_cosmetic_id text null,
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create index if not exists activity_presence_location_idx
  on public.activity_presence (location_id, current_activity_id);

alter table public.profiles enable row level security;
alter table public.player_saves enable row level security;
alter table public.leaderboard_snapshots enable row level security;
alter table public.chat_messages enable row level security;
alter table public.guilds enable row level security;
alter table public.guild_members enable row level security;
alter table public.activity_presence enable row level security;

create policy "profiles are readable" on public.profiles for select using (true);
create policy "profiles are self-writable" on public.profiles
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "saves are self only" on public.player_saves
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "leaderboards readable" on public.leaderboard_snapshots for select using (true);
create policy "leaderboards self upsert" on public.leaderboard_snapshots
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "chat readable" on public.chat_messages for select using (true);
create policy "chat insert self" on public.chat_messages
  for insert with check (auth.uid() = user_id);

create policy "guilds readable" on public.guilds for select using (true);
create policy "guild members readable" on public.guild_members for select using (true);
create policy "presence readable" on public.activity_presence for select using (true);
create policy "presence self write" on public.activity_presence
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
