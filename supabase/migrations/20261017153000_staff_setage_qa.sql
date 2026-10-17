-- Staff /setage: reject future years, and write an audit row for failed
-- attempts as well as successes. Year-only ages stay 31 December
-- (see 20261017152000). TEST only; never apply to live from this PR.

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
  v_as_of date := (timezone('utc', now()))::date;
  v_ok boolean := false;
  v_reason text;
begin
  if v_me is null or not coalesce(public.is_developer(), false) then
    return jsonb_build_object('ok', false, 'reason', 'Not a developer account.');
  end if;

  if p_target is not null then
    select jsonb_build_object(
      'birth_year', a.birth_year,
      'birth_month', a.birth_month,
      'age_band', a.age_band,
      'source', a.source
    )
      into v_before
    from public.account_age a
    where a.user_id = p_target;
  end if;

  if p_target is null then
    v_reason := 'Missing player.';
  elsif p_birth_year is not null then
    if p_birth_year < 1900 or p_birth_year > extract(year from v_as_of)::integer then
      v_reason := 'Enter a valid birth year.';
    elsif p_birth_month is not null and (p_birth_month < 1 or p_birth_month > 12) then
      v_reason := 'Enter a valid birth month.';
    else
      v_years := public.account_age_years(p_birth_year, p_birth_month, v_as_of);
      v_band := public.account_age_band_from_years(v_years);
      insert into public.account_age (user_id, birth_year, birth_month, age_band, source)
      values (p_target, p_birth_year, p_birth_month, v_band, 'support')
      on conflict (user_id) do update
        set birth_year = excluded.birth_year,
            birth_month = excluded.birth_month,
            age_band = excluded.age_band,
            source = 'support',
            refreshed_at = now();
      v_ok := true;
      v_reason := 'Age updated.';
    end if;
  else
    v_band := btrim(coalesce(p_age_band, ''));
    if v_band not in ('0-12', '13-15', '16-17', '18+') then
      v_reason := 'Enter a birth year or a store age band.';
    else
      insert into public.account_age (user_id, birth_year, birth_month, age_band, source)
      values (p_target, null, null, v_band, 'support')
      on conflict (user_id) do update
        set birth_year = null,
            birth_month = null,
            age_band = excluded.age_band,
            source = 'support',
            refreshed_at = now();
      v_ok := true;
      v_reason := 'Age updated.';
    end if;
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
    v_ok,
    v_reason
  );

  if not v_ok then
    return jsonb_build_object('ok', false, 'reason', v_reason);
  end if;
  return jsonb_build_object(
    'ok', true,
    'chat_allowed', public.chat_allowed(p_target),
    'age_band', v_band
  );
end;
$$;

revoke all on function public.staff_set_account_age(uuid, integer, integer, text) from public, anon;
grant execute on function public.staff_set_account_age(uuid, integer, integer, text) to authenticated, service_role;

notify pgrst, 'reload schema';
