-- SOC-04: mass payout claim and hosted save write in one transaction.
--
-- The 2-argument mass_claim_payout marked payout_claimed before the game
-- function wrote player_saves, so a failed save write dropped the loot.
-- RAISE on a version conflict rolls the claim back (function savepoint),
-- matching bounty_turn_in_hosted. Do not edit 20261017010000_mass_bosses.sql.

drop function if exists public.mass_claim_payout(uuid, uuid);

create or replace function public.mass_claim_payout(
  p_user_id uuid,
  p_encounter_id uuid,
  p_expected_version integer,
  p_payload jsonb,
  p_rng_state bigint,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_enc public.mass_encounters;
  v_part public.mass_participants;
  v_save public.player_saves;
  v_version integer;
  v_eligible boolean;
begin
  if p_user_id is null or p_encounter_id is null then
    return jsonb_build_object('ok', false, 'reason', 'Unknown mass encounter.');
  end if;
  if p_payload is null then
    return jsonb_build_object('ok', false, 'reason', 'Missing save.');
  end if;

  select * into v_enc
    from public.mass_encounters
   where id = p_encounter_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'Unknown mass encounter.');
  end if;
  if v_enc.status = 'closed' then
    return jsonb_build_object(
      'ok', false,
      'reason', 'A closed fight cannot be settled.',
      'closed', true,
      'eligible', false,
      'alreadyClaimed', false
    );
  end if;
  if v_enc.status <> 'settled' then
    return jsonb_build_object('ok', false, 'reason', 'This fight is not finished.');
  end if;

  select * into v_part
    from public.mass_participants
   where encounter_id = p_encounter_id
     and user_id = p_user_id
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'You are not in this fight.');
  end if;

  v_eligible := coalesce(
    v_part.payout_eligible,
    (v_part.locked_in and not v_part.late and v_part.damage_dealt >= v_enc.min_damage)
  );

  if v_part.payout_claimed then
    select * into v_save
      from public.player_saves
     where user_id = p_user_id;
    return jsonb_build_object(
      'ok', true,
      'eligible', v_eligible,
      'alreadyClaimed', true,
      'damageDealt', v_part.damage_dealt,
      'minDamage', v_enc.min_damage,
      'dropScale', v_enc.drop_scale,
      'late', v_part.late,
      'lockedIn', v_part.locked_in,
      'version', v_save.version,
      'payload', v_save.payload
    );
  end if;

  update public.mass_participants
     set payout_claimed = true,
         payout_eligible = v_eligible
   where encounter_id = p_encounter_id
     and user_id = p_user_id;

  update public.player_saves
     set payload = p_payload,
         version = p_expected_version + 1,
         advanced_to = p_now,
         rng_state = p_rng_state,
         updated_at = p_now
   where user_id = p_user_id
     and version = p_expected_version
  returning version into v_version;

  -- A normal RETURN after the claim UPDATE would commit with no save write.
  -- RAISE rolls the claim back (function-level savepoint) before the JSON.
  if v_version is null then
    raise exception 'save_version_conflict' using errcode = 'P0001';
  end if;

  return jsonb_build_object(
    'ok', true,
    'eligible', v_eligible,
    'alreadyClaimed', false,
    'damageDealt', v_part.damage_dealt,
    'minDamage', v_enc.min_damage,
    'dropScale', v_enc.drop_scale,
    'late', v_part.late,
    'lockedIn', v_part.locked_in,
    'version', v_version,
    'payload', p_payload
  );
exception
  when raise_exception then
    if SQLERRM = 'save_version_conflict' then
      return jsonb_build_object(
        'ok', false,
        'reason', 'Save version conflict. Sync and retry.',
        'conflict', true
      );
    end if;
    raise;
end;
$$;

revoke all on function public.mass_claim_payout(
  uuid, uuid, integer, jsonb, bigint, timestamptz
) from public, anon, authenticated;
grant execute on function public.mass_claim_payout(
  uuid, uuid, integer, jsonb, bigint, timestamptz
) to service_role;
