-- Ignore (player_blocks), reports, and username checks for signed-in clients.
-- Tables stay locked to service_role. These functions are the only client path.
-- player_mutes is unchanged and unused.

create index if not exists chat_reports_reporter_created_idx
  on public.chat_reports (reporter_id, created_at desc);

-- Empty names and the Adventurer stand-in are still unclaimed, same as pending_.
create or replace function public.profiles_guard_sensitive_columns()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  actor uuid := auth.uid();
  remaining_ms numeric;
  remaining_hours int;
  remaining_days int;
  old_name text;
  new_name text;
  pending_prefix constant text := 'pending_';
  cooldown constant interval := interval '7 days';
begin
  if actor is null and current_user in ('service_role', 'supabase_admin', 'postgres') then
    return new;
  end if;

  if new.guild_id is not null
     and not exists (
       select 1
         from public.guild_members m
        where m.user_id = new.user_id
          and m.guild_id = new.guild_id
     ) then
    raise exception 'Guild tag must match your membership.';
  end if;

  if tg_op = 'INSERT' then
    new.username_renamed_at := null;
    return new;
  end if;

  old_name := coalesce(old.username, '');
  new_name := coalesce(new.username, '');

  if new_name is not distinct from old_name then
    if new.username_renamed_at is distinct from old.username_renamed_at then
      raise exception 'Cannot change username_renamed_at.';
    end if;
    return new;
  end if;

  if old_name = ''
     or old_name like pending_prefix || '%'
     or lower(old_name) = 'adventurer' then
    new.username_renamed_at := old.username_renamed_at;
    return new;
  end if;

  if old.username_renamed_at is not null
     and old.username_renamed_at + cooldown > now() then
    remaining_ms := extract(epoch from (old.username_renamed_at + cooldown - now())) * 1000;
    if remaining_ms < 86400000 then
      remaining_hours := case
        when remaining_ms <= 3600000 then 1
        else ceil(remaining_ms / 3600000.0)::int
      end;
      if remaining_hours = 1 then
        raise exception 'You can rename again in 1 hour.';
      end if;
      raise exception 'You can rename again in % hours.', remaining_hours;
    end if;
    remaining_days := ceil(remaining_ms / 86400000.0)::int;
    if remaining_days = 1 then
      raise exception 'You can rename again in 1 day.';
    end if;
    raise exception 'You can rename again in % days.', remaining_days;
  end if;

  new.username_renamed_at := now();
  return new;
end;
$$;

create or replace function public.block_player(p_target uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'Sign in first.';
  end if;
  if p_target is null or p_target = v_me then
    return jsonb_build_object('ok', false, 'reason', 'You cannot ignore yourself.');
  end if;
  if not exists (select 1 from public.profiles where user_id = p_target) then
    return jsonb_build_object('ok', false, 'reason', 'That player was not found.');
  end if;
  insert into public.player_blocks (user_id, blocked_user_id)
  values (v_me, p_target)
  on conflict do nothing;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.unblock_player(p_target uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'Sign in first.';
  end if;
  if p_target is null then
    return jsonb_build_object('ok', false, 'reason', 'That player was not found.');
  end if;
  delete from public.player_blocks
   where user_id = v_me
     and blocked_user_id = p_target;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.list_my_blocks()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'Sign in first.';
  end if;
  return jsonb_build_object(
    'blocked_user_ids',
    coalesce(
      (
        select jsonb_agg(blocked_user_id order by created_at)
          from public.player_blocks
         where user_id = v_me
      ),
      '[]'::jsonb
    )
  );
end;
$$;

create or replace function public.report_player(p_target uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_reason text := btrim(coalesce(p_reason, ''));
  v_recent int;
begin
  if v_me is null then
    raise exception 'Sign in first.';
  end if;
  if p_target is null or p_target = v_me then
    return jsonb_build_object('ok', false, 'reason', 'You cannot report yourself.');
  end if;
  if not exists (select 1 from public.profiles where user_id = p_target) then
    return jsonb_build_object('ok', false, 'reason', 'That player was not found.');
  end if;
  if v_reason in ('Spam', 'Harassment', 'Inappropriate name', 'Other') then
    null;
  elsif left(v_reason, 6) = 'Other:' and char_length(v_reason) <= 280 then
    null;
  else
    return jsonb_build_object('ok', false, 'reason', 'Choose a reason.');
  end if;

  select count(*)
    into v_recent
    from public.chat_reports
   where reporter_id = v_me
     and created_at > now() - interval '1 day';
  if v_recent >= 10 then
    return jsonb_build_object('ok', false, 'reason', 'You have sent enough reports today.');
  end if;

  insert into public.chat_reports (reporter_id, target_user_id, reason)
  values (v_me, p_target, v_reason);
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.username_available(p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := btrim(coalesce(p_name, ''));
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'Sign in first.';
  end if;
  if char_length(v_name) < 2 then
    return jsonb_build_object('value', false);
  end if;
  if char_length(v_name) > 24 then
    v_name := left(v_name, 24);
  end if;
  return jsonb_build_object(
    'value',
    not exists (
      select 1
        from public.profiles
       where lower(username) = lower(v_name)
         and user_id is distinct from v_me
    )
  );
end;
$$;

create or replace function public.rename_username(p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_name text := btrim(coalesce(p_name, ''));
  v_profile public.profiles;
begin
  if v_me is null then
    raise exception 'Sign in first.';
  end if;
  if char_length(v_name) < 2 then
    return jsonb_build_object('ok', false, 'reason', 'Enter a name to continue.');
  end if;
  if char_length(v_name) > 24 then
    v_name := left(v_name, 24);
  end if;

  select *
    into v_profile
    from public.profiles
   where user_id = v_me
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'Sign in required.');
  end if;
  if lower(v_profile.username) = lower(v_name) then
    return jsonb_build_object('ok', true);
  end if;
  if exists (
    select 1
      from public.profiles
     where lower(username) = lower(v_name)
       and user_id <> v_me
  ) then
    return jsonb_build_object('ok', false, 'reason', 'That name is taken.');
  end if;

  update public.profiles
     set username = v_name
   where user_id = v_me;
  return jsonb_build_object('ok', true);
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'reason', 'That name is taken.');
end;
$$;

revoke all on function public.block_player(uuid) from public, anon;
revoke all on function public.unblock_player(uuid) from public, anon;
revoke all on function public.list_my_blocks() from public, anon;
revoke all on function public.report_player(uuid, text) from public, anon;
revoke all on function public.username_available(text) from public, anon;
revoke all on function public.rename_username(text) from public, anon;

grant execute on function public.block_player(uuid) to authenticated;
grant execute on function public.unblock_player(uuid) to authenticated;
grant execute on function public.list_my_blocks() to authenticated;
grant execute on function public.report_player(uuid, text) to authenticated;
grant execute on function public.username_available(text) to authenticated;
grant execute on function public.rename_username(text) to authenticated;

notify pgrst, 'reload schema';
