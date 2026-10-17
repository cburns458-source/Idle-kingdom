-- SOC-04: a failed hosted save write must not keep payout_claimed, and a
-- retry with the matching version must grant exactly once.

do $$
declare
  a uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1';
  enc uuid;
  snap jsonb;
  claim jsonb;
  v_gold text;
  v_version integer;
  v_claimed boolean;
begin
  insert into auth.users (id) values (a)
  on conflict (id) do nothing;

  delete from public.mass_encounters where enemy_id = 'ENM-0006';
  delete from public.player_saves where user_id = a;

  insert into public.player_saves (user_id, save_version, payload, version, rng_state)
  values (a, 68, '{"gold": 10, "massEncounterId": "pending"}'::jsonb, 3, 1);

  snap := public.mass_join(a, 'ENM-0006', 'Alpha', 1000);
  enc := (snap->>'encounterId')::uuid;
  update public.mass_encounters
     set countdown_ends_at = now() - interval '1 second'
   where id = enc;
  snap := public.mass_lock_if_due(enc, 1000, null);
  perform public.mass_record_damage(a, enc, (snap->>'totalHp')::numeric, 'kill');
  snap := public.mass_settle(enc);
  assert snap->>'status' = 'settled', 'solo kill settles';

  claim := public.mass_claim_payout(
    a,
    enc,
    1,
    '{"gold": 75, "massEncounterId": null}'::jsonb,
    1,
    now()
  );
  assert coalesce(claim->>'conflict', '') = 'true', 'wrong save version is a conflict';
  select payout_claimed into v_claimed
    from public.mass_participants
   where encounter_id = enc and user_id = a;
  assert v_claimed = false, 'failed save write must not keep the claim';
  select payload->>'gold', version into v_gold, v_version
    from public.player_saves
   where user_id = a;
  assert v_gold = '10' and v_version = 3, 'conflict must leave the save untouched';

  claim := public.mass_claim_payout(
    a,
    enc,
    3,
    '{"gold": 75, "massEncounterId": null}'::jsonb,
    1,
    now()
  );
  assert claim->>'ok' = 'true', 'retry with matching version succeeds';
  assert claim->>'alreadyClaimed' = 'false', 'retry is the first successful claim';
  assert (claim->>'version')::int = 4, 'retry bumps the hosted version';
  select payout_claimed into v_claimed
    from public.mass_participants
   where encounter_id = enc and user_id = a;
  assert v_claimed = true, 'successful write marks the claim';
  select payload->>'gold', version into v_gold, v_version
    from public.player_saves
   where user_id = a;
  assert v_gold = '75' and v_version = 4, 'retry writes the payout once';

  claim := public.mass_claim_payout(
    a,
    enc,
    4,
    '{"gold": 999, "massEncounterId": null}'::jsonb,
    1,
    now()
  );
  assert claim->>'alreadyClaimed' = 'true', 'second success is a no-op';
  select payload->>'gold', version into v_gold, v_version
    from public.player_saves
   where user_id = a;
  assert v_gold = '75' and v_version = 4, 'exactly-once: later claims do not rewrite gold';

  delete from public.mass_encounters where enemy_id = 'ENM-0006';
  delete from public.player_saves where user_id = a;
  raise notice 'mass_claim_payout retry SQL tests passed';
end $$;
