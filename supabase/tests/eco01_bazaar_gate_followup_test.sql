-- ECO-01 leftovers: one SQL constant, clear error for a non-numeric skill level.
\set ON_ERROR_STOP on
\pset pager off

truncate table public.bazaar_collect, public.bazaar_fills, public.bazaar_orders, public.bazaar_prices;
delete from public.player_saves;
delete from public.profiles;
delete from auth.users;

\i supabase/migrations/20261013180000_eco01_bazaar_total_level_gate.sql
\i supabase/migrations/20261013210000_eco01_bazaar_gate_followup.sql

do $$
begin
  if public.bazaar_total_level_required() <> 200 then
    raise exception 'bazaar_total_level_required must be 200';
  end if;
  if public.bazaar_payload_total_level('{"skills":[{"level":100},{"level":100}]}'::jsonb) <> 200 then
    raise exception '200 sum was wrong';
  end if;
end $$;

do $$
begin
  perform public.bazaar_payload_total_level('{"skills":[{"level":"abc"}]}'::jsonb);
  raise exception 'non-numeric skill level should have failed';
exception when others then
  if position('BAZAAR_SKILL_LEVEL_INVALID' in sqlerrm) = 0 then
    raise exception 'expected BAZAAR_SKILL_LEVEL_INVALID, got %', sqlerrm;
  end if;
  raise notice 'non-numeric skill level refused: %', sqlerrm;
end $$;
