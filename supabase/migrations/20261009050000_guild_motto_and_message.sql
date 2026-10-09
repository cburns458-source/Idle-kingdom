-- Guild motto (public description) and private member announcement.
--
-- Motto reuses public.guilds.description (already browsable). Leaders and
-- officers edit it through guild_set_motto, because the table itself is still
-- leader-only for direct updates.
--
-- The private message lives on its own table so non-members cannot read it
-- through the signed-in guild SELECT policy.

create table if not exists public.guild_private_messages (
  guild_id uuid primary key references public.guilds (id) on delete cascade,
  body text not null default '',
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null
);

comment on table public.guild_private_messages is
  'Single private announcement for guild members. Not a chat history.';

alter table public.guild_private_messages enable row level security;

drop policy if exists "guild private message readable by members" on public.guild_private_messages;
create policy "guild private message readable by members"
  on public.guild_private_messages
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.guild_members m
      where m.guild_id = guild_private_messages.guild_id
        and m.user_id = (select auth.uid())
    )
  );

-- No client insert/update/delete: only the SECURITY DEFINER RPCs write.

revoke all on table public.guild_private_messages from anon;
grant select on table public.guild_private_messages to authenticated;
revoke insert, update, delete on table public.guild_private_messages from authenticated;
grant all on table public.guild_private_messages to service_role;

-- Seed an empty row for every existing guild.
insert into public.guild_private_messages (guild_id, body)
select g.id, ''
from public.guilds g
on conflict (guild_id) do nothing;

-- Keep a private-message row when a guild is founded later.
create or replace function public.guild_private_message_seed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.guild_private_messages (guild_id, body)
  values (new.id, '')
  on conflict (guild_id) do nothing;
  return new;
end;
$$;

drop trigger if exists guild_private_message_seed on public.guilds;
create trigger guild_private_message_seed
  after insert on public.guilds
  for each row
  execute function public.guild_private_message_seed();

create or replace function public.guild_set_motto(p_guild uuid, p_motto text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_clean text := left(btrim(coalesce(p_motto, '')), 160);
begin
  if v_me is null then
    return jsonb_build_object('ok', false, 'reason', 'Sign in first.');
  end if;
  if p_guild is null then
    return jsonb_build_object('ok', false, 'reason', 'Missing guild.');
  end if;
  if not coalesce(public.is_guild_manager(p_guild), false) then
    return jsonb_build_object('ok', false, 'reason', 'Only the guild leader or an officer can edit the motto.');
  end if;
  update public.guilds
  set description = v_clean
  where id = p_guild;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'That guild could not be found.');
  end if;
  return jsonb_build_object('ok', true, 'motto', v_clean);
end;
$$;

revoke all on function public.guild_set_motto(uuid, text) from public, anon;
grant execute on function public.guild_set_motto(uuid, text) to authenticated, service_role;

create or replace function public.guild_set_message(p_guild uuid, p_body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_clean text := left(btrim(coalesce(p_body, '')), 500);
begin
  if v_me is null then
    return jsonb_build_object('ok', false, 'reason', 'Sign in first.');
  end if;
  if p_guild is null then
    return jsonb_build_object('ok', false, 'reason', 'Missing guild.');
  end if;
  if not coalesce(public.is_guild_manager(p_guild), false) then
    return jsonb_build_object('ok', false, 'reason', 'Only the guild leader or an officer can edit the guild message.');
  end if;
  if not exists (
    select 1 from public.guild_members m
    where m.guild_id = p_guild and m.user_id = v_me
  ) then
    return jsonb_build_object('ok', false, 'reason', 'Join the guild to edit its message.');
  end if;
  insert into public.guild_private_messages (guild_id, body, updated_at, updated_by)
  values (p_guild, v_clean, now(), v_me)
  on conflict (guild_id) do update
    set body = excluded.body,
        updated_at = excluded.updated_at,
        updated_by = excluded.updated_by;
  return jsonb_build_object('ok', true, 'body', v_clean);
end;
$$;

revoke all on function public.guild_set_message(uuid, text) from public, anon;
grant execute on function public.guild_set_message(uuid, text) to authenticated, service_role;

notify pgrst, 'reload schema';
