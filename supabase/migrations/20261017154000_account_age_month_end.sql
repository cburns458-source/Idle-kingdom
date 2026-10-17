-- Known birth months use the last day of that month (same safe rule as
-- year-only = 31 December). TEST only; never apply to live from this PR.

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
  v_as_of_year integer;
  v_anniversary date;
  v_years integer;
begin
  if p_birth_year is null then
    return null;
  end if;
  v_month := coalesce(p_birth_month, 12);
  if v_month < 1 or v_month > 12 then
    v_month := 12;
  end if;
  v_as_of_year := extract(year from p_as_of)::integer;
  -- Last day of the birth month in the as-of year.
  v_anniversary := (make_date(v_as_of_year, v_month, 1) + interval '1 month' - interval '1 day')::date;
  v_years := v_as_of_year - p_birth_year;
  if p_as_of < v_anniversary then
    v_years := v_years - 1;
  end if;
  return v_years;
end;
$$;

notify pgrst, 'reload schema';
