-- SOC-04 SQL scenarios. Run on the TEST project after the mass_bosses migration.
-- Covers lock-at-spawn, alt accounts, late join, leave HP, empty close, idle close,
-- duplicate ticks, and settle-once. Closed fights cannot be settled.

do $$
declare
  a uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1';
  b uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2';
  c uuid := 'cccccccc-cccc-cccc-cccc-ccccccccccc3';
  enc uuid;
  snap jsonb;
  hp1 numeric;
  hp2 numeric;
  dmg jsonb;
begin
  delete from public.mass_encounters where enemy_id = 'ENM-0006';

  snap := public.mass_join(a, 'ENM-0006', 'Alpha', 1000);
  enc := (snap->>'encounterId')::uuid;
  assert snap->>'status' = 'lobby', 'first join opens a lobby';

  snap := public.mass_join(b, 'ENM-0006', 'Bravo', 1000);
  assert (snap->>'encounterId')::uuid = enc, 'second account joins the same lobby';
  assert jsonb_array_length(snap->'participants') = 2, 'alt accounts both listed';

  update public.mass_encounters
     set countdown_ends_at = now() - interval '1 second'
   where id = enc;

  snap := public.mass_lock_if_due(enc, 1000, null);
  assert snap->>'status' = 'fighting', 'list locks at spawn';
  assert (snap->>'lockedCount')::int = 2, 'both alts lock in';
  assert (snap->>'totalHp')::numeric = 1500, 'two players → 1.5× HP';

  hp1 := public.mass_remaining_hp(enc);
  snap := public.mass_join(c, 'ENM-0006', 'Late', 1000);
  assert snap->'you'->>'late' = 'true', 'late joiner is marked late';
  assert (snap->>'lockedCount')::int = 2, 'late join does not change n';
  assert public.mass_remaining_hp(enc) = hp1, 'late join does not change HP';

  dmg := public.mass_record_damage(a, enc, 100, 'round-1');
  assert (dmg->>'damageAdded')::numeric = 100, 'first tick records damage';
  hp2 := public.mass_remaining_hp(enc);
  assert hp2 = hp1 - 100, 'HP falls by recorded damage';

  dmg := public.mass_record_damage(a, enc, 100, 'round-1');
  assert dmg->>'duplicate' = 'true', 'repeated round clock adds no damage';
  assert (dmg->>'damageAdded')::numeric = 0, 'duplicate damage is zero';
  assert public.mass_remaining_hp(enc) = hp2, 'HP unchanged on duplicate';

  dmg := public.mass_record_damage(c, enc, 500, 'late-round');
  assert (dmg->>'damageAdded')::numeric = 0, 'late joiner adds no shared damage';
  assert public.mass_remaining_hp(enc) = hp2, 'late damage ignored';

  perform public.mass_leave(b, enc);
  assert public.mass_remaining_hp(enc) = hp2, 'leaving does not lower HP';
  assert (select status from public.mass_encounters where id = enc) = 'fighting',
    'one locked player still present keeps the fight open';

  -- Both accounts leave mid-fight. The old fight never pays; a return is fresh.
  perform public.mass_leave(a, enc);
  assert (select status from public.mass_encounters where id = enc) = 'closed',
    'last leave closes with no payout';
  snap := public.mass_settle(enc);
  assert snap->>'closed' = 'true' or snap->>'ok' = 'false', 'closed fight cannot be settled';

  snap := public.mass_join(a, 'ENM-0006', 'Alpha', 1000);
  assert snap->>'status' = 'lobby', 'returner gets a fresh boss';
  assert (snap->>'encounterId')::uuid <> enc, 'old encounter is not reused';
  assert (select status from public.mass_encounters where id = enc) = 'closed',
    'abandoned fight stays closed';
  assert (public.mass_settle(enc)->>'ok') = 'false', 'abandoned fight never pays out';

  -- Idle close: lock a solo fight, rewind last tick, status closes it.
  enc := (snap->>'encounterId')::uuid;
  update public.mass_encounters set countdown_ends_at = now() - interval '1 second' where id = enc;
  snap := public.mass_lock_if_due(enc, 1000, null);
  assert snap->>'status' = 'fighting';
  update public.mass_encounters
     set last_locked_tick_at = now() - interval '61 seconds'
   where id = enc;
  snap := public.mass_status(a, enc, 1000, null);
  assert snap->>'status' = 'closed', '60s idle close';
  snap := public.mass_settle(enc);
  assert snap->>'ok' = 'false', 'idle-closed fight never pays out';

  -- Late joiner is ineligible when the boss dies.
  delete from public.mass_encounters where enemy_id = 'ENM-0006';
  snap := public.mass_join(a, 'ENM-0006', 'Alpha', 1000);
  enc := (snap->>'encounterId')::uuid;
  perform public.mass_join(b, 'ENM-0006', 'Bravo', 1000);
  update public.mass_encounters set countdown_ends_at = now() - interval '1 second' where id = enc;
  snap := public.mass_lock_if_due(enc, 1000, null);
  assert (snap->>'totalHp')::numeric = 1500;
  perform public.mass_join(c, 'ENM-0006', 'Late', 1000);
  perform public.mass_record_damage(a, enc, 1500, 'kill');
  snap := public.mass_settle(enc);
  assert snap->>'status' = 'settled', 'kill settles once';
  assert (select payout_eligible from public.mass_participants where encounter_id = enc and user_id = a) = true;
  assert (select payout_eligible from public.mass_participants where encounter_id = enc and user_id = c) = false,
    'late joiner gets no drop';
  snap := public.mass_settle(enc);
  assert snap->>'alreadySettled' = 'true', 'settle is once only';
  dmg := public.mass_record_damage(a, enc, 50, 'after-settle');
  assert (dmg->>'damageAdded')::numeric = 0, 'damage after settle is ignored';
  assert position(
    'for share' in lower(pg_get_functiondef(
      'public.mass_record_damage(uuid, uuid, numeric, text)'::regprocedure
    ))
  ) > 0, 'mass_record_damage must share-lock the encounter while reading status';

  -- Mother squid uses average locked player base HP.
  delete from public.mass_encounters where enemy_id = 'ENM-0023';
  snap := public.mass_join(a, 'ENM-0023', 'Alpha', 1000);
  enc := (snap->>'encounterId')::uuid;
  perform public.mass_join(b, 'ENM-0023', 'Bravo', 3000);
  update public.mass_encounters set countdown_ends_at = now() - interval '1 second' where id = enc;
  snap := public.mass_lock_if_due(enc, 0, 2.2);
  assert (snap->>'soloHp')::numeric = floor(((1000 + 3000) / 2.0) * 2.2);
  assert (snap->>'totalHp')::numeric = floor((snap->>'soloHp')::numeric * 1.5);

  -- Caller-supplied squid scale is clamped to [0.1, 10].
  delete from public.mass_encounters where enemy_id = 'ENM-0023';
  snap := public.mass_join(a, 'ENM-0023', 'Alpha', 1000);
  enc := (snap->>'encounterId')::uuid;
  update public.mass_encounters set countdown_ends_at = now() - interval '1 second' where id = enc;
  snap := public.mass_lock_if_due(enc, 0, 999);
  assert (snap->>'soloHp')::numeric = floor(1000 * 10), 'scale 999 clamps to 10';

  -- Players who left cannot record damage.
  delete from public.mass_encounters where enemy_id = 'ENM-0006';
  snap := public.mass_join(a, 'ENM-0006', 'Alpha', 1000);
  enc := (snap->>'encounterId')::uuid;
  perform public.mass_join(b, 'ENM-0006', 'Bravo', 1000);
  update public.mass_encounters set countdown_ends_at = now() - interval '1 second' where id = enc;
  perform public.mass_lock_if_due(enc, 1000, null);
  perform public.mass_leave(b, enc);
  dmg := public.mass_record_damage(b, enc, 50, 'left-round');
  assert dmg->>'ok' = 'false', 'left player is rejected';
  assert dmg->>'reason' = 'You left this fight.', 'left-player copy';
  assert (dmg->>'damageAdded')::numeric = 0 or dmg->>'damageAdded' is null,
    'left player adds no damage';
  assert public.mass_remaining_hp(enc) = 1500, 'HP unchanged after left-player tick';

  delete from public.mass_encounters where enemy_id in ('ENM-0006', 'ENM-0023');
  raise notice 'mass_bosses SQL tests passed';
end $$;
