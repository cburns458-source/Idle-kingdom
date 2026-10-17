-- QA #400: clients may only submit an in-game birth year; chat and
-- bazaar claims freeze during the deletion grace; expired reports drop
-- even if one side is still present.

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
  if public.account_is_frozen(p_user) then
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
  'Whether this account may send or receive chat, DMs, guild messages, and friend requests. False while a deletion grace is pending.';

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
begin
  if v_me is null then
    return jsonb_build_object('ok', false, 'reason', 'Sign in first.');
  end if;
  if exists (select 1 from public.account_age a where a.user_id = v_me) then
    return jsonb_build_object('ok', false, 'reason', 'Age is already set for this account.');
  end if;
  if v_source <> 'self' then
    return jsonb_build_object(
      'ok', false,
      'reason', 'Store age signals are not accepted. Enter the year you were born.'
    );
  end if;

  if p_birth_year is null or p_birth_year < 1900 or p_birth_year > extract(year from v_as_of)::integer then
    return jsonb_build_object('ok', false, 'reason', 'Enter a valid birth year.');
  end if;
  if p_birth_month is not null and (p_birth_month < 1 or p_birth_month > 12) then
    return jsonb_build_object('ok', false, 'reason', 'Enter a valid birth month.');
  end if;

  v_years := public.account_age_years(p_birth_year, p_birth_month, v_as_of);
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

create or replace function public.refresh_store_age_signal(p_age_band text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  return jsonb_build_object(
    'ok', false,
    'reason', 'Store age signals are not accepted. Enter the year you were born.'
  );
end;
$$;

revoke all on function public.refresh_store_age_signal(text) from public, anon, authenticated;
grant execute on function public.refresh_store_age_signal(text) to service_role;

create or replace function public.account_drop_expired_reports()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from public.chat_reports
   where retained_until is not null
     and retained_until <= timezone('utc', now());
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

comment on function public.account_drop_expired_reports() is
  'Deletes every chat_report whose 1-year retention date has passed, regardless of which side deleted.';

create or replace function public.bazaar_settle_collect(
  p_user_id uuid,
  p_ids uuid[],
  p_payload jsonb,
  p_expected_updated_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stored timestamptz;
  v_wanted int := coalesce(array_length(p_ids, 1), 0);
  v_taken int;
  v_next timestamptz;
begin
  if public.account_is_frozen(p_user_id) then
    raise exception 'This account is scheduled for deletion.'
      using errcode = 'P0001';
  end if;
  if v_wanted = 0 then
    raise exception 'BAZAAR_NOTHING';
  end if;

  select updated_at into v_stored
    from public.player_saves
   where user_id = p_user_id
     for update;
  if not found then
    raise exception 'BAZAAR_NO_SAVE';
  end if;
  if v_stored is distinct from p_expected_updated_at then
    raise exception 'BAZAAR_STALE';
  end if;

  with gone as (
    delete from public.bazaar_collect
     where user_id = p_user_id and id = any (p_ids)
    returning id
  )
  select count(*) into v_taken from gone;
  if v_taken <> v_wanted then
    raise exception 'BAZAAR_STALE';
  end if;

  v_next := coalesce((p_payload ->> 'updatedAt')::timestamptz, now());
  update public.player_saves
     set payload = p_payload,
         save_version = coalesce((p_payload ->> 'saveVersion')::int, save_version),
         updated_at = v_next
   where user_id = p_user_id;

  return jsonb_build_object('collected', v_taken, 'updatedAt', v_next);
end;
$$;

revoke all on function public.bazaar_settle_collect(uuid, uuid[], jsonb, timestamptz)
  from public, anon, authenticated;
grant execute on function public.bazaar_settle_collect(uuid, uuid[], jsonb, timestamptz)
  to service_role;

comment on function public.account_handoff_or_disband_guild(uuid) is
  'Transfers guild leadership (or disbands a solo guild) only when the account is purged, not when the 14-day grace starts.';

notify pgrst, 'reload schema';
