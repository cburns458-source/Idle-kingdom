-- Wave A follow-up: PostgREST upsert fires BEFORE INSERT first. The first
-- guard raised on a stamped payload and the rename UPDATE never ran.

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
  -- Edge/admin paths use the service role (no JWT sub) and may rewrite rows.
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
    -- PostgREST upsert is INSERT … ON CONFLICT DO UPDATE. BEFORE INSERT
    -- runs first on the payload; raising here aborts the UPDATE that
    -- would have stamped a public rename. Strip a client stamp instead.
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

  -- First public name after the pending_ stand-in does not start the week.
  if old_name like pending_prefix || '%' then
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

comment on function public.profiles_guard_sensitive_columns() is
  'Guild tag must match guild_members. Weekly rename cooldown is server-stamped.';

notify pgrst, 'reload schema';
