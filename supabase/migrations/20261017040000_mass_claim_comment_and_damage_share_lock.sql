-- SOC-04 QA: document claim-before-save, and share-lock the encounter
-- while recording damage so a settle cannot race the status check.
-- Do not edit 20261017010000, 20261017020000, or 20261017030000.

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

  -- Claim is written before the hosted save on purpose. A RETURN after this
  -- UPDATE with a failed player_saves write would keep payout_claimed and
  -- drop the loot. RAISE save_version_conflict aborts the function
  -- (Postgres function savepoint) and rolls this claim back so a retry can
  -- grant exactly once. Same pattern as bounty_turn_in_hosted.
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

create or replace function public.mass_record_damage(
  p_user_id uuid,
  p_encounter_id uuid,
  p_damage numeric,
  p_round_started_at text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_enc public.mass_encounters;
  v_part public.mass_participants;
  v_added numeric := 0;
  v_duplicate boolean := false;
begin
  if p_user_id is null or p_encounter_id is null then
    return jsonb_build_object('ok', false, 'reason', 'Unknown mass encounter.');
  end if;

  -- FOR SHARE with mass_settle's FOR UPDATE: concurrent ticks still share
  -- the encounter row, but a settle cannot flip status to settled between
  -- this check and the participant write.
  select * into v_enc
    from public.mass_encounters
   where id = p_encounter_id
   for share;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'Unknown mass encounter.');
  end if;
  if v_enc.status <> 'fighting' then
    return public.mass_encounter_snapshot(p_encounter_id, p_user_id)
      || jsonb_build_object('damageAdded', 0, 'duplicate', false);
  end if;

  select * into v_part
    from public.mass_participants
   where encounter_id = p_encounter_id
     and user_id = p_user_id
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'You are not in this fight.');
  end if;
  if not v_part.present then
    return jsonb_build_object(
      'ok', false,
      'reason', 'You left this fight.',
      'damageAdded', 0,
      'duplicate', false
    );
  end if;

  if v_part.last_round_started_at is not distinct from p_round_started_at
     and p_round_started_at is not null then
    v_duplicate := true;
  elsif v_part.locked_in and not v_part.late then
    v_added := greatest(0, coalesce(p_damage, 0));
    update public.mass_participants
       set damage_dealt = damage_dealt + v_added,
           last_round_started_at = p_round_started_at,
           last_tick_at = now()
     where encounter_id = p_encounter_id
       and user_id = p_user_id;
  else
    update public.mass_participants
       set last_round_started_at = coalesce(p_round_started_at, last_round_started_at),
           last_tick_at = now()
     where encounter_id = p_encounter_id
       and user_id = p_user_id;
  end if;

  return public.mass_encounter_snapshot(p_encounter_id, p_user_id)
    || jsonb_build_object('damageAdded', v_added, 'duplicate', v_duplicate);
end;
$$;
