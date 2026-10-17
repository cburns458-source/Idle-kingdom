-- SOC-04 QA: refuse damage from players who left, and clamp the squid
-- health-scale RPC argument. Do not edit 20261017010000 or 20261017020000.

create or replace function public.mass_lock_if_due(
  p_encounter_id uuid,
  p_solo_hp numeric,
  p_player_base_hp_scale numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_enc public.mass_encounters;
  v_n integer;
  v_solo numeric;
  v_avg numeric;
  v_mult numeric;
  v_total numeric;
  v_drop numeric;
  v_min numeric;
  v_scale numeric;
begin
  select * into v_enc
    from public.mass_encounters
   where id = p_encounter_id
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'Unknown mass encounter.');
  end if;
  if v_enc.status <> 'lobby' then
    return public.mass_encounter_snapshot(p_encounter_id, null);
  end if;
  if now() < v_enc.countdown_ends_at then
    return public.mass_encounter_snapshot(p_encounter_id, null);
  end if;

  with ranked as (
    select user_id,
           row_number() over (order by joined_at, user_id) as rn
      from public.mass_participants
     where encounter_id = p_encounter_id
       and present
  )
  update public.mass_participants p
     set locked_in = (r.rn <= 100),
         late = (r.rn > 100)
    from ranked r
   where p.encounter_id = p_encounter_id
     and p.user_id = r.user_id;

  update public.mass_participants
     set locked_in = false
   where encounter_id = p_encounter_id
     and not present;

  select count(*) into v_n
    from public.mass_participants
   where encounter_id = p_encounter_id
     and locked_in
     and not late;

  if v_n < 1 then
    perform public.mass_close_internal(p_encounter_id, 'empty');
    return public.mass_encounter_snapshot(p_encounter_id, null);
  end if;

  -- Caller-supplied squid health scale. Mother squid (ENM-0023) Notes include
  -- player_base_hp_scale:2.2. The game edge copies that from content into
  -- p_player_base_hp_scale so lock can set
  -- solo_hp = floor(avg(locked player_base_hp) * scale). Dragon passes null
  -- and uses p_solo_hp (sheet HP) instead. This is not a Flutter field, but
  -- the RPC argument is still caller-supplied, so a non-positive or non-finite
  -- value is ignored and a finite value is clamped to [0.1, 10].
  if p_player_base_hp_scale is not null and p_player_base_hp_scale > 0 then
    v_scale := least(10::numeric, greatest(0.1::numeric, p_player_base_hp_scale));
    select avg(greatest(0, player_base_hp)) into v_avg
      from public.mass_participants
     where encounter_id = p_encounter_id
       and locked_in
       and not late;
    v_solo := greatest(1, floor(coalesce(v_avg, 0) * v_scale));
  else
    v_solo := greatest(1, floor(coalesce(p_solo_hp, 0)));
  end if;

  v_mult := 1 + 0.5 * (v_n - 1);
  v_total := greatest(1, floor(v_solo * v_mult));
  v_drop := case when v_n <= 1 then 1 else (0.9 * v_mult) / v_n end;
  v_min := v_total * least(0.03, 0.25 / v_n);

  update public.mass_encounters
     set status = 'fighting',
         spawned_at = now(),
         locked_count = v_n,
         solo_hp = v_solo,
         health_multiplier = v_mult,
         total_hp = v_total,
         drop_scale = v_drop,
         min_damage = v_min,
         last_locked_tick_at = now()
   where id = p_encounter_id;

  return public.mass_encounter_snapshot(p_encounter_id, null);
end;
$$;

comment on function public.mass_lock_if_due(uuid, numeric, numeric) is
  'Lock a due lobby. p_player_base_hp_scale is the Mother squid Notes player_base_hp_scale (2.2), supplied by the game edge from content and clamped to [0.1, 10]. Null uses p_solo_hp (Dragon sheet HP).';

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

  select * into v_enc
    from public.mass_encounters
   where id = p_encounter_id;
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
