-- Guilds move off the device and onto the server.
--
-- The tables were created in 001 and widened in 002, but nothing could be
-- written to them: guilds and guild_members had row-level security on with a
-- read policy and no write policy, and the applications table had no policy at
-- all. This file finishes the job — the columns the guild tab actually shows,
-- the guest roster, and a write policy for every guild table.

-- --- Columns the guild tab shows -------------------------------------------

alter table public.guilds
  add column if not exists rank_icon_theme text not null default 'stripes',
  add column if not exists guest_auto_accept boolean not null default false;

comment on column public.guilds.rank_icon_theme is
  'Which set of rank marks the roster draws: stripes or crowns.';
comment on column public.guilds.guest_auto_accept is
  'When true, a guest joins the chat without a leader deciding.';

-- The emblem was an emoji in a text column, then JSON in that same text column
-- after 002. It is a colour and a symbol, so it becomes jsonb here and both
-- older spellings survive the change.
do $$
begin
  if (
    select data_type from information_schema.columns
     where table_schema = 'public' and table_name = 'guilds' and column_name = 'emblem'
  ) <> 'jsonb' then
    alter table public.guilds
      alter column emblem drop default,
      alter column emblem type jsonb using
        case
          when emblem is null or btrim(emblem) = '' then '{}'::jsonb
          when btrim(emblem) like '{%' then btrim(emblem)::jsonb
          else json_build_object('color', '#5c4027', 'symbol', emblem)::jsonb
        end;
    alter table public.guilds alter column emblem set default '{}'::jsonb;
  end if;
end $$;

-- A roster row carries the name, look, and level it should be listed under.
-- PostgREST can embed a profile, but not one filtered leaderboard row per
-- member, and a roster is read far more often than it changes.
alter table public.guild_members
  add column if not exists username text not null default '',
  add column if not exists appearance_json jsonb not null default '{}'::jsonb,
  add column if not exists total_level numeric not null default 1;

comment on column public.guild_members.total_level is
  'The member total level the roster lists, refreshed by that member''s own client.';

-- An application is either to join the roster or only to sit in guild chat.
alter table public.guild_applications
  add column if not exists username text not null default '',
  add column if not exists guest boolean not null default false;

-- Asking to join and asking to visit are two different requests, so the pair
-- that has to be unique includes which one it is.
alter table public.guild_applications
  drop constraint if exists guild_applications_guild_id_user_id_key;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'guild_applications_one_per_kind'
  ) then
    alter table public.guild_applications
      add constraint guild_applications_one_per_kind unique (guild_id, user_id, guest);
  end if;
end $$;

create table if not exists public.guild_guests (
  guild_id uuid not null references public.guilds (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  username text not null default '',
  appearance_json jsonb not null default '{}'::jsonb,
  joined_at timestamptz not null default now(),
  primary key (guild_id, user_id)
);

comment on table public.guild_guests is
  'Players in a guild''s chat who are not on its roster.';

-- --- Who may change what ----------------------------------------------------

-- Security definer, because a policy on guild_members that reads guild_members
-- would recurse. It answers one question and takes no input from the row.
create or replace function public.guild_role_of(p_guild uuid, p_user uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role
    from public.guild_members
   where guild_id = p_guild
     and user_id = p_user
   limit 1;
$$;

comment on function public.guild_role_of(uuid, uuid) is
  'The rank a player holds in a guild, or null when they are not a member.';

create or replace function public.is_guild_manager(p_guild uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.guild_role_of(p_guild, auth.uid()) in ('leader', 'officer'), false);
$$;

comment on function public.is_guild_manager(uuid) is
  'True when the caller may act on a guild: its leader or one of its officers.';

alter table public.guild_applications enable row level security;
alter table public.guild_guests enable row level security;
alter table public.guild_projects enable row level security;
alter table public.guild_challenges enable row level security;

-- A guild is public to read. Its founder creates it, its leader and officers
-- edit it, and only the leader can disband it.
drop policy if exists "guilds readable" on public.guilds;
create policy "guilds readable" on public.guilds for select using (true);

drop policy if exists "guilds insert own" on public.guilds;
create policy "guilds insert own" on public.guilds
  for insert with check (auth.uid() = leader_id);

drop policy if exists "guilds update by managers" on public.guilds;
create policy "guilds update by managers" on public.guilds
  for update using (public.is_guild_manager(id)) with check (public.is_guild_manager(id));

drop policy if exists "guilds delete by leader" on public.guilds;
create policy "guilds delete by leader" on public.guilds
  for delete using (auth.uid() = leader_id);

-- A roster is public to read. You add and remove yourself; a leader or officer
-- can also add someone they accepted, change a rank, or remove a member.
drop policy if exists "guild members readable" on public.guild_members;
create policy "guild members readable" on public.guild_members for select using (true);

drop policy if exists "guild members insert" on public.guild_members;
create policy "guild members insert" on public.guild_members
  for insert with check (auth.uid() = user_id or public.is_guild_manager(guild_id));

drop policy if exists "guild members update" on public.guild_members;
create policy "guild members update" on public.guild_members
  for update
  using (auth.uid() = user_id or public.is_guild_manager(guild_id))
  with check (auth.uid() = user_id or public.is_guild_manager(guild_id));

drop policy if exists "guild members delete" on public.guild_members;
create policy "guild members delete" on public.guild_members
  for delete using (auth.uid() = user_id or public.is_guild_manager(guild_id));

-- An application is between one player and the guild's officers.
drop policy if exists "guild applications readable" on public.guild_applications;
create policy "guild applications readable" on public.guild_applications
  for select using (auth.uid() = user_id or public.is_guild_manager(guild_id));

drop policy if exists "guild applications insert self" on public.guild_applications;
create policy "guild applications insert self" on public.guild_applications
  for insert with check (auth.uid() = user_id);

drop policy if exists "guild applications delete" on public.guild_applications;
create policy "guild applications delete" on public.guild_applications
  for delete using (auth.uid() = user_id or public.is_guild_manager(guild_id));

-- A guest list is public to read, so a browser can say you are already in one.
drop policy if exists "guild guests readable" on public.guild_guests;
create policy "guild guests readable" on public.guild_guests for select using (true);

drop policy if exists "guild guests insert" on public.guild_guests;
create policy "guild guests insert" on public.guild_guests
  for insert with check (auth.uid() = user_id or public.is_guild_manager(guild_id));

drop policy if exists "guild guests delete" on public.guild_guests;
create policy "guild guests delete" on public.guild_guests
  for delete using (auth.uid() = user_id or public.is_guild_manager(guild_id));

-- Projects and challenges are guild business, readable by anyone.
drop policy if exists "guild projects readable" on public.guild_projects;
create policy "guild projects readable" on public.guild_projects for select using (true);

drop policy if exists "guild projects writable by members" on public.guild_projects;
create policy "guild projects writable by members" on public.guild_projects
  for all
  using (public.guild_role_of(guild_id, auth.uid()) is not null)
  with check (public.guild_role_of(guild_id, auth.uid()) is not null);

drop policy if exists "guild challenges readable" on public.guild_challenges;
create policy "guild challenges readable" on public.guild_challenges for select using (true);

drop policy if exists "guild challenges writable by members" on public.guild_challenges;
create policy "guild challenges writable by members" on public.guild_challenges
  for all
  using (public.guild_role_of(guild_id, auth.uid()) is not null)
  with check (public.guild_role_of(guild_id, auth.uid()) is not null);

-- The hall came in with 007 keyed to a guild that only existed on a device.
-- Now that a guild row is real, so is its hall.
comment on table public.guild_halls is
  'One hall per guild, shared by its members: the store house, the tiers its donations paid for, and the debt ledger.';

-- Names and tags are already unique: name from 001, tag from 002. That is what
-- lets the client hand a race for a name to the database and report the loser.

-- One guild each, and one guild being visited each, as a rule of the table
-- rather than a rule the client remembers. Skipped rather than failed if a row
-- written before this file says otherwise, so the migration always applies.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'guild_members_one_guild')
     and not exists (
       select 1 from public.guild_members group by user_id having count(*) > 1
     ) then
    alter table public.guild_members add constraint guild_members_one_guild unique (user_id);
  end if;

  if not exists (select 1 from pg_constraint where conname = 'guild_guests_one_guild')
     and not exists (
       select 1 from public.guild_guests group by user_id having count(*) > 1
     ) then
    alter table public.guild_guests add constraint guild_guests_one_guild unique (user_id);
  end if;
end $$;

create index if not exists guild_guests_guild_idx on public.guild_guests (guild_id);
create index if not exists guild_applications_guild_idx on public.guild_applications (guild_id);
