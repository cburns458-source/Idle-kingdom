-- SOC-04 mass bosses: shared HP, lobby lock-in, per-player damage rows.
--
-- Players SELECT only. All writes go through security-definer RPCs called by
-- the game function (service_role). Each fighter's damage lives on their
-- participant row so the encounter row is locked only for spawn, settle, and
-- close. Remaining HP = total_hp - sum(locked, not-late damage).
--
-- Health / drop formulas here must match massHpFor, massDropScale, and
-- massMinimumDamage in src/game/combat/boss.ts.

create table if not exists public.mass_encounters (
  id uuid primary key default gen_random_uuid(),
  enemy_id text not null
    check (enemy_id in ('ENM-0006', 'ENM-0023')),
  status text not null default 'lobby'
    check (status in ('lobby', 'fighting', 'settled', 'closed')),
  countdown_started_at timestamptz not null default now(),
  countdown_ends_at timestamptz not null,
  spawned_at timestamptz,
  locked_count integer not null default 0,
  solo_hp numeric not null default 0,
  health_multiplier numeric not null default 1,
  total_hp numeric not null default 0,
  drop_scale numeric not null default 1,
  min_damage numeric not null default 0,
  last_locked_tick_at timestamptz,
  settled_at timestamptz,
  closed_at timestamptz,
  close_reason text,
  created_at timestamptz not null default now()
);

comment on table public.mass_encounters is
  'One open Dragon or Mother squid mass fight at a time. Writes via RPCs only.';

create unique index if not exists mass_encounters_one_open_per_enemy
  on public.mass_encounters (enemy_id)
  where status in ('lobby', 'fighting');

create index if not exists mass_encounters_status_idx
  on public.mass_encounters (status, enemy_id);

create table if not exists public.mass_participants (
  encounter_id uuid not null references public.mass_encounters (id) on delete cascade,
  user_id uuid not null,
  username text not null default 'Adventurer',
  player_base_hp numeric not null default 0,
  joined_at timestamptz not null default now(),
  present boolean not null default true,
  locked_in boolean not null default false,
  late boolean not null default false,
  damage_dealt numeric not null default 0 check (damage_dealt >= 0),
  last_round_started_at text,
  last_tick_at timestamptz,
  payout_eligible boolean,
  payout_claimed boolean not null default false,
  primary key (encounter_id, user_id)
);

comment on table public.mass_participants is
  'Per-player mass-boss row. Damage writes never lock the encounter.';

create index if not exists mass_participants_user_idx
  on public.mass_participants (user_id);

create index if not exists mass_participants_locked_damage_idx
  on public.mass_participants (encounter_id)
  where locked_in and not late;

alter table public.mass_encounters enable row level security;
alter table public.mass_participants enable row level security;

drop policy if exists "mass encounters readable to participants" on public.mass_encounters;
create policy "mass encounters readable to participants"
  on public.mass_encounters
  for select
  to authenticated
  using (
    exists (
      select 1
        from public.mass_participants p
       where p.encounter_id = mass_encounters.id
         and p.user_id = (select auth.uid())
    )
  );

drop policy if exists "mass participants readable to encounter mates" on public.mass_participants;
create policy "mass participants readable to encounter mates"
  on public.mass_participants
  for select
  to authenticated
  using (
    exists (
      select 1
        from public.mass_participants me
       where me.encounter_id = mass_participants.encounter_id
         and me.user_id = (select auth.uid())
    )
  );

revoke all on table public.mass_encounters from public, anon, authenticated;
revoke all on table public.mass_participants from public, anon, authenticated;
grant select on table public.mass_encounters to authenticated;
grant select on table public.mass_participants to authenticated;
grant all on table public.mass_encounters to service_role;
grant all on table public.mass_participants to service_role;

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------

create or replace function public.mass_remaining_hp(p_encounter_id uuid)
returns numeric
language sql
stable
set search_path = ''
as $$
  select greatest(
    0,
    coalesce(e.total_hp, 0) - coalesce((
      select sum(p.damage_dealt)
        from public.mass_participants p
       where p.encounter_id = e.id
         and p.locked_in
         and not p.late
    ), 0)
  )
    from public.mass_encounters e
   where e.id = p_encounter_id;
$$;

create or replace function public.mass_encounter_snapshot(
  p_encounter_id uuid,
  p_user_id uuid
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_enc public.mass_encounters;
  v_you public.mass_participants;
  v_remaining numeric;
begin
  select * into v_enc
    from public.mass_encounters
   where id = p_encounter_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'Unknown mass encounter.');
  end if;

  v_remaining := case
    when v_enc.status in ('lobby', 'closed') then v_enc.total_hp
    else public.mass_remaining_hp(p_encounter_id)
  end;

  select * into v_you
    from public.mass_participants
   where encounter_id = p_encounter_id
     and user_id = p_user_id;

  return jsonb_build_object(
    'ok', true,
    'encounterId', v_enc.id,
    'enemyId', v_enc.enemy_id,
    'status', v_enc.status,
    'countdownEndsAt', v_enc.countdown_ends_at,
    'spawnedAt', v_enc.spawned_at,
    'lockedCount', v_enc.locked_count,
    'soloHp', v_enc.solo_hp,
    'healthMultiplier', v_enc.health_multiplier,
    'totalHp', v_enc.total_hp,
    'remainingHp', v_remaining,
    'dropScale', v_enc.drop_scale,
    'minDamage', v_enc.min_damage,
    'lastLockedTickAt', v_enc.last_locked_tick_at,
    'closeReason', v_enc.close_reason,
    'participants', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'userId', p.user_id,
          'username', p.username,
          'late', p.late,
          'lockedIn', p.locked_in,
          'present', p.present,
          'damageDealt', p.damage_dealt
        )
        order by p.joined_at
      )
        from public.mass_participants p
       where p.encounter_id = p_encounter_id
    ), '[]'::jsonb),
    'you', case
      when v_you.user_id is null then null
      else jsonb_build_object(
        'late', v_you.late,
        'lockedIn', v_you.locked_in,
        'present', v_you.present,
        'damageDealt', v_you.damage_dealt,
        'payoutEligible', v_you.payout_eligible,
        'payoutClaimed', v_you.payout_claimed,
        'lastRoundStartedAt', v_you.last_round_started_at
      )
    end
  );
end;
$$;

create or replace function public.mass_close_internal(
  p_encounter_id uuid,
  p_reason text
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  update public.mass_encounters
     set status = 'closed',
         closed_at = now(),
         close_reason = p_reason
   where id = p_encounter_id
     and status in ('lobby', 'fighting');
end;
$$;

-- Empty = no present locked-in fighters (late joiners cannot keep it open).
-- Lobby empty = no present players. Idle = no locked tick for 60s.
create or replace function public.mass_close_if_empty_or_idle(p_encounter_id uuid)
returns boolean
language plpgsql
set search_path = ''
as $$
declare
  v_enc public.mass_encounters;
  v_present_locked integer;
  v_present integer;
  v_last_tick timestamptz;
  v_idle_from timestamptz;
begin
  select * into v_enc
    from public.mass_encounters
   where id = p_encounter_id
   for update;
  if not found then
    return false;
  end if;
  if v_enc.status in ('settled', 'closed') then
    return false;
  end if;

  select count(*) filter (where present and locked_in and not late),
         count(*) filter (where present)
    into v_present_locked, v_present
    from public.mass_participants
   where encounter_id = p_encounter_id;

  if v_enc.status = 'lobby' and v_present = 0 then
    perform public.mass_close_internal(p_encounter_id, 'empty');
    return true;
  end if;

  if v_enc.status = 'fighting' and v_present_locked = 0 then
    perform public.mass_close_internal(p_encounter_id, 'empty');
    return true;
  end if;

  if v_enc.status = 'fighting' then
    select max(last_tick_at) into v_last_tick
      from public.mass_participants
     where encounter_id = p_encounter_id
       and locked_in
       and not late;
    v_idle_from := coalesce(v_last_tick, v_enc.last_locked_tick_at);
    if v_idle_from is not null
       and v_idle_from <= now() - interval '60 seconds' then
      perform public.mass_close_internal(p_encounter_id, 'idle');
      return true;
    end if;
  end if;

  return false;
end;
$$;

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

  if p_player_base_hp_scale is not null then
    select avg(greatest(0, player_base_hp)) into v_avg
      from public.mass_participants
     where encounter_id = p_encounter_id
       and locked_in
       and not late;
    v_solo := greatest(1, floor(coalesce(v_avg, 0) * p_player_base_hp_scale));
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

-- -----------------------------------------------------------------------------
-- Join / leave / status
-- -----------------------------------------------------------------------------

create or replace function public.mass_join(
  p_user_id uuid,
  p_enemy_id text,
  p_username text,
  p_player_base_hp numeric
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_enc public.mass_encounters;
  v_present integer;
  v_late boolean;
  v_locked boolean;
  v_open boolean := false;
begin
  if p_user_id is null then
    return jsonb_build_object('ok', false, 'reason', 'Sign in to fight.');
  end if;
  if p_enemy_id is null or p_enemy_id not in ('ENM-0006', 'ENM-0023') then
    return jsonb_build_object('ok', false, 'reason', 'That is not a mass boss.');
  end if;

  perform pg_advisory_xact_lock(hashtext('mass:' || p_enemy_id));

  select * into v_enc
    from public.mass_encounters
   where enemy_id = p_enemy_id
     and status in ('lobby', 'fighting')
   for update;
  v_open := found;

  if v_open then
    if public.mass_close_if_empty_or_idle(v_enc.id) then
      v_open := false;
    else
      select * into v_enc
        from public.mass_encounters
       where id = v_enc.id;
      v_open := v_enc.status in ('lobby', 'fighting');
    end if;
  end if;

  if not v_open then
    insert into public.mass_encounters (
      enemy_id, status, countdown_started_at, countdown_ends_at
    ) values (
      p_enemy_id, 'lobby', now(), now() + interval '60 seconds'
    )
    returning * into v_enc;
  end if;

  if exists (
    select 1
      from public.mass_participants
     where encounter_id = v_enc.id
       and user_id = p_user_id
  ) then
    update public.mass_participants
       set present = true,
           username = coalesce(nullif(p_username, ''), username),
           player_base_hp = case
             when v_enc.status = 'lobby' then greatest(0, coalesce(p_player_base_hp, 0))
             else player_base_hp
           end
     where encounter_id = v_enc.id
       and user_id = p_user_id;
    return public.mass_encounter_snapshot(v_enc.id, p_user_id);
  end if;

  if v_enc.status = 'lobby' then
    select count(*) into v_present
      from public.mass_participants
     where encounter_id = v_enc.id
       and present;
    if v_present >= 100 then
      return jsonb_build_object('ok', false, 'reason', 'This fight is full.');
    end if;
    v_late := false;
    v_locked := false;
  else
    v_late := true;
    v_locked := false;
  end if;

  insert into public.mass_participants (
    encounter_id, user_id, username, player_base_hp, present, locked_in, late
  ) values (
    v_enc.id,
    p_user_id,
    coalesce(nullif(p_username, ''), 'Adventurer'),
    greatest(0, coalesce(p_player_base_hp, 0)),
    true,
    v_locked,
    v_late
  );

  return public.mass_encounter_snapshot(v_enc.id, p_user_id);
end;
$$;

create or replace function public.mass_leave(
  p_user_id uuid,
  p_encounter_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_enc public.mass_encounters;
begin
  if p_user_id is null or p_encounter_id is null then
    return jsonb_build_object('ok', false, 'reason', 'Unknown mass encounter.');
  end if;

  select * into v_enc
    from public.mass_encounters
   where id = p_encounter_id
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'Unknown mass encounter.');
  end if;

  update public.mass_participants
     set present = false
   where encounter_id = p_encounter_id
     and user_id = p_user_id;

  perform public.mass_close_if_empty_or_idle(p_encounter_id);
  return public.mass_encounter_snapshot(p_encounter_id, p_user_id);
end;
$$;

create or replace function public.mass_status(
  p_user_id uuid,
  p_encounter_id uuid,
  p_solo_hp numeric default null,
  p_player_base_hp_scale numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_enc public.mass_encounters;
begin
  if p_encounter_id is null then
    return jsonb_build_object('ok', false, 'reason', 'Unknown mass encounter.');
  end if;

  select * into v_enc
    from public.mass_encounters
   where id = p_encounter_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'Unknown mass encounter.');
  end if;

  if v_enc.status = 'lobby' then
    perform public.mass_lock_if_due(p_encounter_id, p_solo_hp, p_player_base_hp_scale);
  end if;
  perform public.mass_close_if_empty_or_idle(p_encounter_id);
  return public.mass_encounter_snapshot(p_encounter_id, p_user_id);
end;
$$;

-- -----------------------------------------------------------------------------
-- Damage / settle / claim
-- -----------------------------------------------------------------------------

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

create or replace function public.mass_settle(p_encounter_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_enc public.mass_encounters;
  v_remaining numeric;
begin
  if p_encounter_id is null then
    return jsonb_build_object('ok', false, 'reason', 'Unknown mass encounter.');
  end if;

  select * into v_enc
    from public.mass_encounters
   where id = p_encounter_id
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'Unknown mass encounter.');
  end if;
  if v_enc.status = 'closed' then
    return jsonb_build_object('ok', false, 'reason', 'A closed fight cannot be settled.', 'closed', true);
  end if;
  if v_enc.status = 'settled' then
    return public.mass_encounter_snapshot(p_encounter_id, null)
      || jsonb_build_object('alreadySettled', true);
  end if;
  if v_enc.status <> 'fighting' then
    return jsonb_build_object('ok', false, 'reason', 'This fight has not started.');
  end if;

  v_remaining := public.mass_remaining_hp(p_encounter_id);
  if v_remaining > 0 then
    return public.mass_encounter_snapshot(p_encounter_id, null)
      || jsonb_build_object('ok', true, 'alive', true, 'remainingHp', v_remaining);
  end if;

  update public.mass_encounters
     set status = 'settled',
         settled_at = now()
   where id = p_encounter_id
     and status = 'fighting';

  update public.mass_participants
     set payout_eligible = (locked_in and not late and damage_dealt >= v_enc.min_damage)
   where encounter_id = p_encounter_id
     and payout_eligible is null;

  return public.mass_encounter_snapshot(p_encounter_id, null)
    || jsonb_build_object('alreadySettled', false);
end;
$$;

create or replace function public.mass_claim_payout(
  p_user_id uuid,
  p_encounter_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_enc public.mass_encounters;
  v_part public.mass_participants;
  v_claimed boolean := false;
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

  if not v_part.payout_claimed then
    update public.mass_participants
       set payout_claimed = true,
           payout_eligible = coalesce(
             payout_eligible,
             (locked_in and not late and damage_dealt >= v_enc.min_damage)
           )
     where encounter_id = p_encounter_id
       and user_id = p_user_id
    returning * into v_part;
    v_claimed := true;
  end if;

  return jsonb_build_object(
    'ok', true,
    'eligible', coalesce(v_part.payout_eligible, false),
    'alreadyClaimed', not v_claimed,
    'damageDealt', v_part.damage_dealt,
    'minDamage', v_enc.min_damage,
    'dropScale', v_enc.drop_scale,
    'late', v_part.late,
    'lockedIn', v_part.locked_in
  );
end;
$$;

revoke all on function public.mass_remaining_hp(uuid) from public, anon, authenticated;
revoke all on function public.mass_encounter_snapshot(uuid, uuid) from public, anon, authenticated;
revoke all on function public.mass_close_internal(uuid, text) from public, anon, authenticated;
revoke all on function public.mass_close_if_empty_or_idle(uuid) from public, anon, authenticated;
revoke all on function public.mass_lock_if_due(uuid, numeric, numeric) from public, anon, authenticated;
revoke all on function public.mass_join(uuid, text, text, numeric) from public, anon, authenticated;
revoke all on function public.mass_leave(uuid, uuid) from public, anon, authenticated;
revoke all on function public.mass_status(uuid, uuid, numeric, numeric) from public, anon, authenticated;
revoke all on function public.mass_record_damage(uuid, uuid, numeric, text) from public, anon, authenticated;
revoke all on function public.mass_settle(uuid) from public, anon, authenticated;
revoke all on function public.mass_claim_payout(uuid, uuid) from public, anon, authenticated;

grant execute on function public.mass_remaining_hp(uuid) to service_role;
grant execute on function public.mass_encounter_snapshot(uuid, uuid) to service_role;
grant execute on function public.mass_close_internal(uuid, text) to service_role;
grant execute on function public.mass_close_if_empty_or_idle(uuid) to service_role;
grant execute on function public.mass_lock_if_due(uuid, numeric, numeric) to service_role;
grant execute on function public.mass_join(uuid, text, text, numeric) to service_role;
grant execute on function public.mass_leave(uuid, uuid) to service_role;
grant execute on function public.mass_status(uuid, uuid, numeric, numeric) to service_role;
grant execute on function public.mass_record_damage(uuid, uuid, numeric, text) to service_role;
grant execute on function public.mass_settle(uuid) to service_role;
grant execute on function public.mass_claim_payout(uuid, uuid) to service_role;
