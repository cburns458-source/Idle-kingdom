-- Wave G phase 3: the game function is the only writer of ranking rows,
-- PvP snapshots, and public profile equipment. Clients may still read them.

drop policy if exists "leaderboards self insert" on public.leaderboard_snapshots;
drop policy if exists "leaderboards self update" on public.leaderboard_snapshots;
drop policy if exists "leaderboards self delete" on public.leaderboard_snapshots;

drop policy if exists "pvp snapshots insert self" on public.pvp_snapshots;
drop policy if exists "pvp snapshots update self" on public.pvp_snapshots;

revoke insert, update, delete on table public.leaderboard_snapshots from anon, authenticated;
revoke insert, update, delete on table public.pvp_snapshots from anon, authenticated;

grant select on table public.leaderboard_snapshots to anon, authenticated;
grant select on table public.pvp_snapshots to authenticated;
grant all on table public.leaderboard_snapshots to service_role;
grant all on table public.pvp_snapshots to service_role;

create or replace function public.profiles_protect_equipment_json()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  actor text := current_setting('role', true);
begin
  if actor in ('service_role', 'postgres', 'supabase_admin') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.equipment_json is not null and new.equipment_json is distinct from '[]'::jsonb then
      raise exception 'equipment_json is server-written' using errcode = '42501';
    end if;
    return new;
  end if;
  if new.equipment_json is distinct from old.equipment_json then
    raise exception 'equipment_json is server-written' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_protect_equipment_json on public.profiles;
create trigger profiles_protect_equipment_json
  before insert or update on public.profiles
  for each row
  execute function public.profiles_protect_equipment_json();

comment on function public.profiles_protect_equipment_json() is
  'Public gear is written by the game function from the hosted save.';
