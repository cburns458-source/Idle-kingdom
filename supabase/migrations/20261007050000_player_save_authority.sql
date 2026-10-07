-- Wave G phase 2: the game function is the only writer of player_saves.
-- Clients may still read their own row. Bazaar security-definer routines keep
-- writing, and a version trigger bumps those writes so the next command CAS fails
-- cleanly instead of overwriting them.

alter table public.player_saves
  add column if not exists version integer not null default 1,
  add column if not exists advanced_to timestamptz,
  add column if not exists rng_state bigint not null default 1;

comment on column public.player_saves.version is
  'Compare-and-swap token. The game function refuses a write that names the wrong version.';
comment on column public.player_saves.advanced_to is
  'Server time the hosted simulation has reached.';
comment on column public.player_saves.rng_state is
  'Mulberry32 state for server-owned loot and travel rolls.';

update public.player_saves
   set advanced_to = coalesce(advanced_to, updated_at),
       rng_state = case
         when rng_state = 1 then (('x' || substr(md5(user_id::text), 1, 8))::bit(32)::int)
         else rng_state
       end
 where advanced_to is null or rng_state = 1;

create or replace function public.player_saves_bump_version()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and new.version is not distinct from old.version then
    new.version := old.version + 1;
  end if;
  return new;
end;
$$;

drop trigger if exists player_saves_bump_version on public.player_saves;
create trigger player_saves_bump_version
  before update on public.player_saves
  for each row
  execute function public.player_saves_bump_version();

drop policy if exists "saves are self only" on public.player_saves;
drop policy if exists "saves are self readable" on public.player_saves;
create policy "saves are self readable" on public.player_saves
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

revoke insert, update, delete on table public.player_saves from anon, authenticated;
grant select on table public.player_saves to authenticated;
grant all on table public.player_saves to service_role;

-- Hall donate / pay debt now debit the hosted save in the game function.
-- The old RPCs only credited the ledger.
revoke all on function public.guild_pay_hall_debt(numeric) from public, anon, authenticated;
revoke all on function public.guild_donate_hall_item(text, numeric) from public, anon, authenticated;
