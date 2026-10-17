-- SOC-04 100-player load gate. Same asserts as tools/mass_boss_load_test.mjs:
-- summed recorded damage equals expected total, settle exactly once,
-- locked_count is 100. Sequential in one session; the node script is the
-- concurrent HTTP version.

create or replace function pg_temp.mass_qa_load_test()
returns jsonb
language plpgsql
as $$
declare
  i integer;
  enc uuid;
  snap jsonb;
  dmg jsonb;
  settle jsonb;
  added numeric := 0;
  recorded numeric;
  first_settles integer := 0;
  already integer := 0;
  uid uuid;
  remaining numeric;
  total numeric;
  locked integer;
begin
  delete from public.mass_encounters where enemy_id = 'ENM-0006';
  for i in 1..100 loop
    uid := ('00000000-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid;
    snap := public.mass_join(uid, 'ENM-0006', 'Load' || i, 1000);
  end loop;
  enc := (snap->>'encounterId')::uuid;
  update public.mass_encounters
     set countdown_ends_at = now() - interval '1 second'
   where id = enc;
  snap := public.mass_lock_if_due(enc, 1000, null);
  locked := (snap->>'lockedCount')::int;
  if snap->>'status' <> 'fighting' or locked <> 100 then
    raise exception 'locked_count is not 100: %', snap;
  end if;
  total := (snap->>'totalHp')::numeric;
  for i in 1..100 loop
    uid := ('00000000-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid;
    dmg := public.mass_record_damage(uid, enc, 1, 'round-' || i);
    added := added + coalesce((dmg->>'damageAdded')::numeric, 0);
  end loop;
  select coalesce(sum(damage_dealt), 0) into recorded
    from public.mass_participants
   where encounter_id = enc;
  if added <> 100 or recorded <> 100 then
    raise exception 'summed recorded damage % (rpc %) != 100', recorded, added;
  end if;
  remaining := public.mass_remaining_hp(enc);
  if remaining > 0 then
    uid := '00000000-0000-4000-8000-000000000001'::uuid;
    perform public.mass_record_damage(uid, enc, remaining, 'kill');
  end if;
  for i in 1..100 loop
    settle := public.mass_settle(enc);
    if coalesce(settle->>'alreadySettled', '') = 'false' then
      first_settles := first_settles + 1;
    elsif coalesce(settle->>'alreadySettled', '') = 'true' then
      already := already + 1;
    end if;
  end loop;
  if first_settles <> 1 then
    raise exception 'boss did not settle exactly once (first=%)', first_settles;
  end if;
  if (select status from public.mass_encounters where id = enc) <> 'settled' then
    raise exception 'encounter status is not settled';
  end if;
  if (select locked_count from public.mass_encounters where id = enc) <> 100 then
    raise exception 'locked_count is not 100 after settle';
  end if;
  delete from public.mass_encounters where id = enc;
  return jsonb_build_object(
    'ok', true,
    'players', 100,
    'lockedCount', locked,
    'expectedDamage', 100,
    'damageAdded', added,
    'recordedSum', recorded,
    'totalHp', total,
    'remainingAfterWave', remaining,
    'firstSettles', first_settles,
    'alreadySettled', already
  );
end;
$$;

select pg_temp.mass_qa_load_test() as report;
