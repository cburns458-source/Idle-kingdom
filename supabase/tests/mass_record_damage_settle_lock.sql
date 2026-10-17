-- SOC-04: mass_record_damage share-locks the encounter so settle cannot
-- race the fighting check. After settle, further ticks add no damage.

do $$
declare
  a uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1';
  enc uuid;
  snap jsonb;
  dmg jsonb;
  src text;
begin
  delete from public.mass_encounters where enemy_id = 'ENM-0006';
  snap := public.mass_join(a, 'ENM-0006', 'Alpha', 1000);
  enc := (snap->>'encounterId')::uuid;
  update public.mass_encounters
     set countdown_ends_at = now() - interval '1 second'
   where id = enc;
  snap := public.mass_lock_if_due(enc, 1000, null);
  assert snap->>'status' = 'fighting';

  dmg := public.mass_record_damage(a, enc, 100, 'pre-kill');
  assert (dmg->>'damageAdded')::numeric = 100, 'share-lock still allows damage while fighting';

  perform public.mass_record_damage(a, enc, (snap->>'totalHp')::numeric, 'kill');
  snap := public.mass_settle(enc);
  assert snap->>'status' = 'settled';

  dmg := public.mass_record_damage(a, enc, 25, 'post-settle');
  assert (dmg->>'damageAdded')::numeric = 0, 'settled fight records no further damage';
  assert (select status from public.mass_encounters where id = enc) = 'settled',
    'post-settle tick cannot un-settle';

  src := lower(pg_get_functiondef(
    'public.mass_record_damage(uuid, uuid, numeric, text)'::regprocedure
  ));
  assert position('for share' in src) > 0,
    'mass_record_damage must SELECT the encounter FOR SHARE';
  assert position('for update' in src) > 0,
    'mass_record_damage still row-locks the participant';

  delete from public.mass_encounters where enemy_id = 'ENM-0006';
  raise notice 'mass_record_damage settle lock SQL tests passed';
end $$;
