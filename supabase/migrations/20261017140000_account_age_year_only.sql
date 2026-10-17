-- Year-only age answers: treat the birthday as 1 January and stop
-- asking for a month. Chat still turns on at 13.

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
  v_birthday date;
begin
  if p_birth_year is null then
    return null;
  end if;
  -- Missing month: treat as 1 January so a year-only answer is enough.
  v_month := coalesce(p_birth_month, 1);
  begin
    v_birthday := make_date(p_birth_year, v_month, 1);
  exception
    when others then
      v_birthday := make_date(p_birth_year, 1, 1);
  end;
  return (extract(year from age(p_as_of, v_birthday)))::integer;
end;
$$;

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
