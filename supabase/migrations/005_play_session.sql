-- One device may play an account at a time. A new sign-in replaces
-- active_play_session_id; the other device sees the change and signs out.
-- Save writes must carry the same id so a kicked client cannot overwrite.

alter table public.profiles
  add column if not exists active_play_session_id uuid;

alter table public.player_saves
  add column if not exists play_session_id uuid;

comment on column public.profiles.active_play_session_id is
  'The play session currently allowed to write this account. A new sign-in replaces it.';

comment on column public.player_saves.play_session_id is
  'Must match profiles.active_play_session_id when that column is set.';

create or replace function public.player_saves_require_active_session()
returns trigger
language plpgsql
as $$
declare
  current_session uuid;
begin
  select active_play_session_id
    into current_session
    from public.profiles
   where user_id = auth.uid();

  if current_session is null then
    return new;
  end if;

  if new.play_session_id is distinct from current_session then
    raise exception 'Signed in on another device'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists player_saves_require_active_session on public.player_saves;
create trigger player_saves_require_active_session
  before insert or update on public.player_saves
  for each row
  execute function public.player_saves_require_active_session();
