-- One hall per guild, shared by its members: the store house everyone donates
-- into, the tiers those donations have paid for, and the debt ledger.
--
-- The store house is the donation record. A finished tier spends the materials
-- it asked for, which is why nothing is ever taken back out.
--
-- The client still answers hall state from the device it is played on. This
-- table is what it reads and writes once guild rosters live here too: a hall row
-- needs a guild row to belong to, and guilds are still local.

create table if not exists public.guild_halls (
  guild_id uuid primary key references public.guilds (id) on delete cascade,
  debt_remaining numeric not null default 1000000,
  debt_paid_off boolean not null default false,
  debt_paid_by jsonb not null default '{}'::jsonb,
  storehouse jsonb not null default '[]'::jsonb,
  completed_tiers jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

comment on column public.guild_halls.storehouse is
  'Inventory stacks the guild has donated, as [{"itemId":"ITEM-0015","quantity":40}].';
comment on column public.guild_halls.completed_tiers is
  'Tier ids finished, in order: ["build_the_hall", "hall_bank", "hall_boxing_ring"].';
comment on column public.guild_halls.debt_paid_by is
  'How much gold each member has put toward the debt, keyed by user id.';

alter table public.guild_halls enable row level security;

-- A hall is guild business: anyone signed in can look one up, and only the
-- guild's own members can change it.
drop policy if exists "guild halls readable" on public.guild_halls;
create policy "guild halls readable" on public.guild_halls
  for select using (true);

drop policy if exists "guild halls writable by members" on public.guild_halls;
create policy "guild halls writable by members" on public.guild_halls
  for all
  using (
    exists (
      select 1
        from public.guild_members
       where guild_members.guild_id = guild_halls.guild_id
         and guild_members.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
        from public.guild_members
       where guild_members.guild_id = guild_halls.guild_id
         and guild_members.user_id = auth.uid()
    )
  );
