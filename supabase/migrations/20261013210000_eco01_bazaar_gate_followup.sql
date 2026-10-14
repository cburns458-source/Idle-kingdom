-- ECO-01 leftovers: one SQL constant for the total-level gate, and a clear
-- error when a skill level is not numeric.
--
-- Does not edit 20261013180000. Replaces the helper bodies and the trigger
-- function so every layer reads 200 from bazaar_total_level_required().
--
-- Rollback (comments only; do not run unless reversing this change):
--   1. Reapply the bazaar_payload_total_level and
--      bazaar_orders_require_total_level bodies from
--      20261013180000_eco01_bazaar_total_level_gate.sql (CREATE OR REPLACE).
--      Those bodies use the literal 200 and do not call the helper below.
--   2. Then DROP FUNCTION IF EXISTS public.bazaar_total_level_required();
--      It does not exist in 20261013180000; this migration added it.
--      Drop it only after step 1, and only if no later migration calls it.

create or replace function public.bazaar_total_level_required()
returns integer
language sql
immutable
set search_path = public
as $$
  select 200;
$$;

comment on function public.bazaar_total_level_required() is
  'ECO-01: new Bazaar offers require this many total levels.';

create or replace function public.bazaar_payload_total_level(p_payload jsonb)
returns integer
language plpgsql
immutable
set search_path = public
as $$
declare
  v_skill jsonb;
  v_raw text;
  v_sum numeric := 0;
begin
  if jsonb_typeof(p_payload -> 'skills') is distinct from 'array' then
    return 0;
  end if;
  for v_skill in
    select value from jsonb_array_elements(p_payload -> 'skills')
  loop
    if jsonb_typeof(v_skill) is distinct from 'object' then
      continue;
    end if;
    if not (v_skill ? 'level') or v_skill ->> 'level' is null then
      continue;
    end if;
    v_raw := v_skill ->> 'level';
    if v_raw !~ '^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$' then
      raise exception 'BAZAAR_SKILL_LEVEL_INVALID skill level must be numeric, got %', v_raw;
    end if;
    v_sum := v_sum + floor(v_raw::numeric);
  end loop;
  return coalesce(v_sum, 0)::integer;
end;
$$;

comment on function public.bazaar_payload_total_level(jsonb) is
  'Floor of each skill level, then the sum. Non-numeric levels raise BAZAAR_SKILL_LEVEL_INVALID.';

create or replace function public.bazaar_orders_require_total_level()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total integer;
  v_required integer;
begin
  v_required := public.bazaar_total_level_required();
  v_total := coalesce(public.bazaar_user_total_level(new.user_id), 0);
  if v_total < v_required then
    raise exception 'BAZAAR_TOTAL_LEVEL required=% totalLevel=%', v_required, v_total;
  end if;
  return new;
end;
$$;

revoke all on function public.bazaar_total_level_required()
  from public, anon, authenticated;
grant execute on function public.bazaar_total_level_required() to service_role;

revoke all on function public.bazaar_payload_total_level(jsonb)
  from public, anon, authenticated;
grant execute on function public.bazaar_payload_total_level(jsonb) to service_role;
