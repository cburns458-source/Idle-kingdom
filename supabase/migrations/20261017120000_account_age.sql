-- ADM age gate for chat (Conor 2026-10-17).
--
-- Age answers control CHAT ONLY. Every account can play. Under 13 (or
-- unanswered) cannot send or receive global/local/DM/guild chat, the guild
-- message board, or friend requests. Report and block stay open.
--
-- account_age is server-only. Never put a birthday on profiles.

create table if not exists public.account_age (
  user_id uuid primary key references auth.users (id) on delete cascade,
  birth_year integer,
  birth_month integer,
  age_band text not null,
  source text not null,
  answered_at timestamptz not null default now(),
  refreshed_at timestamptz,
  constraint account_age_year_range check (
    birth_year is null or (birth_year >= 1900 and birth_year <= 2100)
  ),
  constraint account_age_month_range check (
    birth_month is null or (birth_month between 1 and 12)
  ),
  constraint account_age_source_check check (
    source in ('self', 'support', 'store_signal')
  ),
  constraint account_age_band_check check (
    age_band in ('0-12', '13-15', '16-17', '18+', 'unknown')
  ),
  constraint account_age_self_has_year check (
    source <> 'self' or birth_year is not null
  ),
  constraint account_age_store_has_band check (
    source <> 'store_signal' or age_band <> 'unknown'
  )
);

comment on table public.account_age is
  'Per-account birth year or store age band. Server-only; clients see chat_allowed.';

comment on column public.account_age.source is
  'self = in-game question, store_signal = Apple/Google declared range, support = staff override.';

alter table public.account_age enable row level security;

revoke all on table public.account_age from public, anon, authenticated;
grant all on table public.account_age to service_role;

-- Chat turns on at 13. Band is recomputed from birth year so players age up.
create or replace function public.account_chat_age_threshold()
returns integer
language sql
immutable
set search_path = ''
as $$
  select 13;
$$;

create or replace function public.account_age_years(
  p_birth_year integer,
  p_birth_month integer,
  p_as_of date default (timezone('utc', now()))::date
)
returns integer
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_month integer;
  v_day integer;
  v_birthday date;
begin
  if p_birth_year is null then
    return null;
  end if;
  -- Missing month: treat as 31 Dec so a year-only answer cannot unlock chat
  -- before we know they have turned 13.
  v_month := coalesce(p_birth_month, 12);
  v_day := case when p_birth_month is null then 31 else 1 end;
  begin
    v_birthday := make_date(p_birth_year, v_month, v_day);
  exception
    when others then
      v_birthday := make_date(p_birth_year, 12, 31);
  end;
  return (extract(year from age(p_as_of, v_birthday)))::integer;
end;
$$;

create or replace function public.account_age_band_from_years(p_years integer)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_years is null then 'unknown'
    when p_years < 13 then '0-12'
    when p_years < 16 then '13-15'
    when p_years < 18 then '16-17'
    else '18+'
  end;
$$;

create or replace function public.account_age_band_allows_chat(p_band text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_band in ('13-15', '16-17', '18+');
$$;

-- True only after an answer that computes to 13 or older as of now.
create or replace function public.chat_allowed(p_user uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row public.account_age%rowtype;
  v_years integer;
begin
  if p_user is null then
    return false;
  end if;
  select * into v_row from public.account_age a where a.user_id = p_user;
  if not found then
    return false;
  end if;
  if v_row.birth_year is not null then
    v_years := public.account_age_years(v_row.birth_year, v_row.birth_month);
    return coalesce(v_years, 0) >= public.account_chat_age_threshold();
  end if;
  return public.account_age_band_allows_chat(v_row.age_band);
end;
$$;

comment on function public.chat_allowed(uuid) is
  'Whether this account may send or receive chat, DMs, guild messages, and friend requests.';

revoke all on function public.chat_allowed(uuid) from public, anon;
grant execute on function public.chat_allowed(uuid) to authenticated, service_role;

create or replace function public.account_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := (select auth.uid());
  v_answered boolean;
begin
  if v_me is null then
    return jsonb_build_object(
      'ok', false,
      'reason', 'Sign in first.',
      'age_answered', false,
      'chat_allowed', false,
      'deletion_pending', false
    );
  end if;
  v_answered := exists (select 1 from public.account_age a where a.user_id = v_me);
  return jsonb_build_object(
    'ok', true,
    'age_answered', v_answered,
    'chat_allowed', public.chat_allowed(v_me),
    'deletion_pending', false
  );
end;
$$;

revoke all on function public.account_status() from public, anon;
grant execute on function public.account_status() to authenticated, service_role;

create or replace function public.set_account_age(
  p_birth_year integer default null,
  p_birth_month integer default null,
  p_source text default 'self',
  p_age_band text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := (select auth.uid());
  v_source text := lower(btrim(coalesce(p_source, 'self')));
  v_band text;
  v_years integer;
  v_as_of date := (timezone('utc', now()))::date;
  v_threshold integer := public.account_chat_age_threshold();
begin
  if v_me is null then
    return jsonb_build_object('ok', false, 'reason', 'Sign in first.');
  end if;
  if exists (select 1 from public.account_age a where a.user_id = v_me) then
    return jsonb_build_object('ok', false, 'reason', 'Age is already set for this account.');
  end if;
  if v_source not in ('self', 'store_signal') then
    return jsonb_build_object('ok', false, 'reason', 'Choose a valid age source.');
  end if;

  if v_source = 'store_signal' then
    v_band := btrim(coalesce(p_age_band, ''));
    if v_band not in ('0-12', '13-15', '16-17', '18+') then
      return jsonb_build_object('ok', false, 'reason', 'That store age signal could not be read.');
    end if;
    insert into public.account_age (user_id, birth_year, birth_month, age_band, source)
    values (v_me, null, null, v_band, 'store_signal');
    return jsonb_build_object(
      'ok', true,
      'age_answered', true,
      'chat_allowed', public.chat_allowed(v_me)
    );
  end if;

  if p_birth_year is null or p_birth_year < 1900 or p_birth_year > extract(year from v_as_of)::integer then
    return jsonb_build_object('ok', false, 'reason', 'Enter a valid birth year.');
  end if;
  if p_birth_month is not null and (p_birth_month < 1 or p_birth_month > 12) then
    return jsonb_build_object('ok', false, 'reason', 'Enter a valid birth month.');
  end if;

  v_years := public.account_age_years(p_birth_year, p_birth_month, v_as_of);
  -- Within a year of 13, the month is required so we do not guess.
  if p_birth_month is null
     and public.account_age_years(p_birth_year, 1, v_as_of) < v_threshold + 1
     and public.account_age_years(p_birth_year, 12, v_as_of) >= v_threshold - 1
  then
    return jsonb_build_object('ok', false, 'reason', 'Enter the month you were born.');
  end if;

  v_band := public.account_age_band_from_years(v_years);
  insert into public.account_age (user_id, birth_year, birth_month, age_band, source)
  values (v_me, p_birth_year, p_birth_month, v_band, 'self');

  return jsonb_build_object(
    'ok', true,
    'age_answered', true,
    'chat_allowed', public.chat_allowed(v_me)
  );
end;
$$;

revoke all on function public.set_account_age(integer, integer, text, text) from public, anon;
grant execute on function public.set_account_age(integer, integer, text, text) to authenticated, service_role;

-- Store signals may refresh so a 0-12 player can age into chat without support.
create or replace function public.refresh_store_age_signal(p_age_band text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := (select auth.uid());
  v_band text := btrim(coalesce(p_age_band, ''));
begin
  if v_me is null then
    return jsonb_build_object('ok', false, 'reason', 'Sign in first.');
  end if;
  if v_band not in ('0-12', '13-15', '16-17', '18+') then
    return jsonb_build_object('ok', false, 'reason', 'That store age signal could not be read.');
  end if;
  update public.account_age
     set age_band = v_band,
         refreshed_at = now()
   where user_id = v_me
     and source = 'store_signal';
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'No store age signal to refresh.');
  end if;
  return jsonb_build_object(
    'ok', true,
    'age_answered', true,
    'chat_allowed', public.chat_allowed(v_me)
  );
end;
$$;

revoke all on function public.refresh_store_age_signal(text) from public, anon;
grant execute on function public.refresh_store_age_signal(text) to authenticated, service_role;

create or replace function public.staff_set_account_age(
  p_target uuid,
  p_birth_year integer default null,
  p_birth_month integer default null,
  p_age_band text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := (select auth.uid());
  v_band text;
  v_years integer;
  v_before jsonb;
begin
  if v_me is null or not coalesce(public.is_developer(), false) then
    return jsonb_build_object('ok', false, 'reason', 'Not a developer account.');
  end if;
  if p_target is null then
    return jsonb_build_object('ok', false, 'reason', 'Missing player.');
  end if;

  select jsonb_build_object(
    'birth_year', a.birth_year,
    'birth_month', a.birth_month,
    'age_band', a.age_band,
    'source', a.source
  )
    into v_before
  from public.account_age a
  where a.user_id = p_target;

  if p_birth_year is not null then
    if p_birth_month is not null and (p_birth_month < 1 or p_birth_month > 12) then
      return jsonb_build_object('ok', false, 'reason', 'Enter a valid birth month.');
    end if;
    v_years := public.account_age_years(p_birth_year, p_birth_month);
    v_band := public.account_age_band_from_years(v_years);
    insert into public.account_age (user_id, birth_year, birth_month, age_band, source)
    values (p_target, p_birth_year, p_birth_month, v_band, 'support')
    on conflict (user_id) do update
      set birth_year = excluded.birth_year,
          birth_month = excluded.birth_month,
          age_band = excluded.age_band,
          source = 'support',
          refreshed_at = now();
  else
    v_band := btrim(coalesce(p_age_band, ''));
    if v_band not in ('0-12', '13-15', '16-17', '18+') then
      return jsonb_build_object('ok', false, 'reason', 'Enter a birth year or a store age band.');
    end if;
    insert into public.account_age (user_id, birth_year, birth_month, age_band, source)
    values (p_target, null, null, v_band, 'support')
    on conflict (user_id) do update
      set birth_year = null,
          birth_month = null,
          age_band = excluded.age_band,
          source = 'support',
          refreshed_at = now();
  end if;

  insert into public.developer_audit_log (user_id, command, args, ok, reason)
  values (
    v_me,
    'setage',
    jsonb_build_object(
      'target', p_target,
      'before', v_before,
      'birth_year', p_birth_year,
      'birth_month', p_birth_month,
      'age_band', v_band
    ),
    true,
    'Age updated.'
  );

  return jsonb_build_object(
    'ok', true,
    'chat_allowed', public.chat_allowed(p_target),
    'age_band', v_band
  );
end;
$$;

revoke all on function public.staff_set_account_age(uuid, integer, integer, text) from public, anon;
grant execute on function public.staff_set_account_age(uuid, integer, integer, text) to authenticated, service_role;

-- Chat reads require chat_allowed. Report and block RPCs are unchanged.
drop policy if exists "chat readable by participants" on public.chat_messages;
create policy "chat readable by participants" on public.chat_messages
  for select to authenticated
  using (
    public.chat_allowed((select auth.uid()))
    and (
      channel_key = 'global'
      or (
        channel_key like 'local:%'
        and exists (
          select 1
            from public.activity_presence ap
           where ap.user_id = (select auth.uid())
             and ap.location_id = substr(channel_key, 7)
             and ap.expires_at > now()
        )
      )
      or (
        channel_key like 'guild:%'
        and (
          public.guild_role_of(
            nullif(substr(channel_key, 7), '')::uuid,
            (select auth.uid())
          ) is not null
          or exists (
            select 1
              from public.guild_guests gg
             where gg.guild_id = nullif(substr(channel_key, 7), '')::uuid
               and gg.user_id = (select auth.uid())
          )
        )
      )
      or (
        channel_key like 'dm:%'
        and split_part(substr(channel_key, 4), ':', 3) = ''
        and (
          split_part(substr(channel_key, 4), ':', 1) = (select auth.uid())::text
          or split_part(substr(channel_key, 4), ':', 2) = (select auth.uid())::text
        )
      )
    )
  );

drop policy if exists "friend requests readable" on public.friend_requests;
drop policy if exists "friend requests insert self" on public.friend_requests;
drop policy if exists "friend requests delete parties" on public.friend_requests;
create policy "friend requests readable" on public.friend_requests
  for select to authenticated
  using (
    public.chat_allowed((select auth.uid()))
    and (
      (select auth.uid()) = from_user_id
      or (select auth.uid()) = to_user_id
    )
  );
create policy "friend requests insert self" on public.friend_requests
  for insert to authenticated
  with check (
    (select auth.uid()) = from_user_id
    and from_user_id <> to_user_id
    and public.chat_allowed((select auth.uid()))
    and public.chat_allowed(to_user_id)
  );
create policy "friend requests delete parties" on public.friend_requests
  for delete to authenticated
  using (
    (select auth.uid()) = from_user_id
    or (select auth.uid()) = to_user_id
  );

drop policy if exists "guild private message readable by members" on public.guild_private_messages;
create policy "guild private message readable by members"
  on public.guild_private_messages
  for select
  to authenticated
  using (
    public.chat_allowed((select auth.uid()))
    and exists (
      select 1
      from public.guild_members m
      where m.guild_id = guild_private_messages.guild_id
        and m.user_id = (select auth.uid())
    )
  );

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
  if not public.chat_allowed(v_me) then
    return jsonb_build_object(
      'ok', false,
      'reason', 'Chat is not available for this account.',
      'code', 'age_gate'
    );
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

notify pgrst, 'reload schema';
