-- ECO-03: plaza points replace gold on ranked PvP and bounty payouts.
--
-- Rewrites the BUG-04 (#333) hosted functions so a win grants 25 plaza points
-- and bounties grant floored catalog points. Gold on the stored save is never
-- raised by these RPCs. Client-supplied gold / point amounts are ignored.
--
-- Also revokes leftover table rights on player_saves (QA): only authenticated
-- SELECT (owner RLS) and service_role writes remain.
--
-- Re-run safe: CREATE OR REPLACE / ADD COLUMN IF NOT EXISTS.

alter table public.ranked_pvp_results
  add column if not exists points_paid integer not null default 0;

comment on column public.ranked_pvp_results.points_paid is
  'Plaza points granted for this fight. gold_paid stays 0 after ECO-03.';

revoke all on table public.player_saves from public, anon, authenticated;
grant select on table public.player_saves to authenticated;
grant all on table public.player_saves to service_role;

create or replace function public.ranked_pvp_win_points()
returns integer
language sql
immutable
set search_path = ''
as $$
  select 25;
$$;

create or replace function public.ranked_pvp_daily_cap()
returns integer
language sql
immutable
set search_path = ''
as $$
  select 5;
$$;

create or replace function public.bounty_plaza_points(p_bounty_id text, p_first boolean)
returns integer
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_base numeric;
  v_bonus numeric;
begin
  v_base := case p_bounty_id
    when 'BNT-0001' then 40
    when 'BNT-0002' then 40
    when 'BNT-0003' then 55
    when 'BNT-0004' then 45
    when 'BNT-0005' then 50
    when 'BNT-0006' then 70
    when 'BNT-0007' then 80
    when 'BNT-0008' then 60
    when 'BNT-0009' then 65
    when 'BNT-0010' then 70
    when 'BNT-0011' then 50
    else 0
  end;
  v_bonus := case when p_first then
    case p_bounty_id
      when 'BNT-0001' then 25
      when 'BNT-0002' then 25
      when 'BNT-0003' then 30
      when 'BNT-0004' then 25
      when 'BNT-0005' then 30
      when 'BNT-0006' then 40
      when 'BNT-0007' then 45
      when 'BNT-0008' then 35
      when 'BNT-0009' then 35
      when 'BNT-0010' then 40
      when 'BNT-0011' then 30
      else 0
    end
  else 0 end;
  return floor(v_base + v_bonus)::integer;
end;
$$;

create or replace function public.plaza_shop_item_price(p_item_id text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case p_item_id
    when 'ITEM-0428' then 210
    when 'ITEM-0429' then 170
    when 'ITEM-0427' then 150
    when 'ITEM-0430' then 120
    when 'ITEM-0431' then 120
    else null
  end;
$$;

-- =============================================================================
-- bounty_turn_in_hosted: first-place insert + save write; points not gold
-- =============================================================================

create or replace function public.bounty_turn_in_hosted(
  p_user_id uuid,
  p_hour_key text,
  p_bounty_id text,
  p_username text,
  p_expected_version integer,
  p_payload_first jsonb,
  p_payload_base jsonb,
  p_rng_state bigint,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inserted_user uuid;
  v_claim public.bounty_claims;
  v_first boolean;
  v_payload jsonb;
  v_version integer;
  v_old public.player_saves;
  v_old_gold numeric;
  v_old_points integer;
  v_points integer;
begin
  if p_user_id is null then
    return jsonb_build_object('ok', false, 'reason', 'Sign in to claim bounties.');
  end if;
  if p_hour_key is null or p_bounty_id is null then
    return jsonb_build_object('ok', false, 'reason', 'Missing bounty.');
  end if;

  select * into v_old from public.player_saves where user_id = p_user_id;
  v_old_gold := coalesce((v_old.payload ->> 'gold')::numeric, 0);
  v_old_points := greatest(0, floor(coalesce((v_old.payload ->> 'plazaPoints')::numeric, 0)))::integer;

  insert into public.bounty_claims (hour_key, bounty_id, user_id, username, claimed_at)
  values (p_hour_key, p_bounty_id, p_user_id, coalesce(nullif(p_username, ''), 'Adventurer'), p_now)
  on conflict (hour_key, bounty_id) do nothing
  returning user_id into v_inserted_user;

  if v_inserted_user is not null then
    v_first := true;
    v_payload := p_payload_first;
    select * into v_claim
      from public.bounty_claims
     where hour_key = p_hour_key and bounty_id = p_bounty_id;
  else
    select * into v_claim
      from public.bounty_claims
     where hour_key = p_hour_key and bounty_id = p_bounty_id;
    if not found then
      return jsonb_build_object('ok', false, 'reason', 'Could not record the bounty claim.');
    end if;
    if v_claim.user_id = p_user_id then
      return jsonb_build_object('ok', false, 'reason', 'You already claimed this bounty.');
    end if;
    v_first := false;
    v_payload := p_payload_base;
  end if;

  v_points := public.bounty_plaza_points(p_bounty_id, v_first);
  v_payload := coalesce(v_payload, '{}'::jsonb) || jsonb_build_object(
    'gold', v_old_gold,
    'plazaPoints', v_old_points + v_points
  );

  update public.player_saves
     set payload = v_payload,
         version = p_expected_version + 1,
         advanced_to = p_now,
         rng_state = p_rng_state,
         updated_at = p_now
   where user_id = p_user_id
     and version = p_expected_version
  returning version into v_version;

  if v_version is null then
    raise exception 'save_version_conflict' using errcode = 'P0001';
  end if;

  return jsonb_build_object(
    'ok', true,
    'firstCompleter', v_first,
    'version', v_version,
    'pointsGained', v_points,
    'plazaPoints', v_old_points + v_points,
    'claim', jsonb_build_object(
      'hourKey', v_claim.hour_key,
      'bountyId', v_claim.bounty_id,
      'userId', v_claim.user_id,
      'username', v_claim.username,
      'claimedAt', v_claim.claimed_at
    )
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

revoke all on function public.bounty_turn_in_hosted(
  uuid, text, text, text, integer, jsonb, jsonb, bigint, timestamptz
) from public, anon, authenticated;
grant execute on function public.bounty_turn_in_hosted(
  uuid, text, text, text, integer, jsonb, jsonb, bigint, timestamptz
) to service_role;

-- =============================================================================
-- ranked_pvp_record_hosted: fight row + save write; 25 points, never gold
-- =============================================================================

create or replace function public.ranked_pvp_record_hosted(
  p_user_id uuid,
  p_fight_id uuid,
  p_opponent_id uuid,
  p_outcome text,
  p_gold_paid bigint,
  p_code text,
  p_rounds jsonb,
  p_you_max_hp numeric,
  p_them_max_hp numeric,
  p_wins_remaining integer,
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
  v_inserted uuid;
  v_existing public.ranked_pvp_results;
  v_version integer;
  v_old public.player_saves;
  v_old_gold numeric;
  v_old_points integer;
  v_used integer;
  v_day text;
  v_points integer;
  v_payload jsonb;
begin
  if p_user_id is null or p_fight_id is null then
    return jsonb_build_object('ok', false, 'reason', 'Unknown ranked fight.');
  end if;
  if p_outcome is null or p_outcome not in ('win', 'loss') then
    return jsonb_build_object('ok', false, 'reason', 'The server resolves ranked fights.');
  end if;

  select * into v_old from public.player_saves where user_id = p_user_id;
  v_old_gold := coalesce((v_old.payload ->> 'gold')::numeric, 0);
  v_old_points := greatest(0, floor(coalesce((v_old.payload ->> 'plazaPoints')::numeric, 0)))::integer;
  v_day := to_char(p_now at time zone 'utc', 'YYYY-MM-DD');
  if coalesce(v_old.payload ->> 'rankedPvpDayKey', '') = v_day then
    v_used := greatest(0, floor(coalesce((v_old.payload ->> 'rankedPvpFightsToday')::numeric, 0)))::integer;
  else
    v_used := 0;
  end if;
  v_points := case
    when p_outcome = 'win' and v_used < public.ranked_pvp_daily_cap()
      then public.ranked_pvp_win_points()
    else 0
  end;

  insert into public.ranked_pvp_results (
    user_id, fight_id, opponent_id, outcome, gold_paid, points_paid, code, rounds,
    you_max_hp, them_max_hp, wins_remaining, created_at
  ) values (
    p_user_id, p_fight_id, p_opponent_id, p_outcome, 0, v_points, p_code,
    coalesce(p_rounds, '[]'::jsonb), coalesce(p_you_max_hp, 0), coalesce(p_them_max_hp, 0),
    coalesce(p_wins_remaining, 0), p_now
  )
  on conflict (user_id, fight_id) do nothing
  returning fight_id into v_inserted;

  if v_inserted is null then
    select * into v_existing
      from public.ranked_pvp_results
     where user_id = p_user_id and fight_id = p_fight_id;
    return jsonb_build_object(
      'ok', true,
      'alreadyPaid', true,
      'version', p_expected_version,
      'fightId', v_existing.fight_id,
      'outcome', v_existing.outcome,
      'goldPaid', 0,
      'pointsGained', coalesce(v_existing.points_paid, 0),
      'plazaPoints', v_old_points,
      'code', v_existing.code,
      'rounds', v_existing.rounds,
      'youMaxHp', v_existing.you_max_hp,
      'themMaxHp', v_existing.them_max_hp,
      'winsRemaining', v_existing.wins_remaining
    );
  end if;

  v_payload := coalesce(p_payload, '{}'::jsonb) || jsonb_build_object(
    'gold', v_old_gold,
    'plazaPoints', v_old_points + v_points
  );

  update public.player_saves
     set payload = v_payload,
         version = p_expected_version + 1,
         advanced_to = p_now,
         rng_state = p_rng_state,
         updated_at = p_now
   where user_id = p_user_id
     and version = p_expected_version
  returning version into v_version;

  if v_version is null then
    raise exception 'save_version_conflict' using errcode = 'P0001';
  end if;

  return jsonb_build_object(
    'ok', true,
    'alreadyPaid', false,
    'version', v_version,
    'fightId', p_fight_id,
    'outcome', p_outcome,
    'goldPaid', 0,
    'pointsGained', v_points,
    'plazaPoints', v_old_points + v_points,
    'code', p_code,
    'winsRemaining', coalesce(p_wins_remaining, 0)
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

revoke all on function public.ranked_pvp_record_hosted(
  uuid, uuid, uuid, text, bigint, text, jsonb, numeric, numeric, integer, integer, jsonb, bigint, timestamptz
) from public, anon, authenticated;
grant execute on function public.ranked_pvp_record_hosted(
  uuid, uuid, uuid, text, bigint, text, jsonb, numeric, numeric, integer, integer, jsonb, bigint, timestamptz
) to service_role;

-- =============================================================================
-- plaza_shop_purchase_hosted: catalog price, refuse if short, nothing deducted
-- =============================================================================

create or replace function public.plaza_shop_purchase_hosted(
  p_user_id uuid,
  p_item_id text,
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
  v_price integer;
  v_old public.player_saves;
  v_old_gold numeric;
  v_old_points integer;
  v_payload jsonb;
  v_version integer;
begin
  if p_user_id is null or p_item_id is null then
    return jsonb_build_object('ok', false, 'reason', 'Missing item.');
  end if;
  v_price := public.plaza_shop_item_price(p_item_id);
  if v_price is null then
    return jsonb_build_object('ok', false, 'reason', 'The plaza shop does not sell that item.');
  end if;

  select * into v_old from public.player_saves where user_id = p_user_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'No cloud save.');
  end if;
  v_old_gold := coalesce((v_old.payload ->> 'gold')::numeric, 0);
  v_old_points := greatest(0, floor(coalesce((v_old.payload ->> 'plazaPoints')::numeric, 0)))::integer;
  if v_old_points < v_price then
    return jsonb_build_object('ok', false, 'reason', 'Not enough plaza points.');
  end if;

  v_payload := coalesce(p_payload, '{}'::jsonb) || jsonb_build_object(
    'gold', v_old_gold,
    'plazaPoints', v_old_points - v_price
  );

  update public.player_saves
     set payload = v_payload,
         version = p_expected_version + 1,
         advanced_to = p_now,
         rng_state = p_rng_state,
         updated_at = p_now
   where user_id = p_user_id
     and version = p_expected_version
  returning version into v_version;

  if v_version is null then
    return jsonb_build_object(
      'ok', false,
      'reason', 'Save version conflict. Sync and retry.',
      'conflict', true
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'version', v_version,
    'pointsSpent', v_price,
    'plazaPoints', v_old_points - v_price,
    'payload', v_payload
  );
end;
$$;

revoke all on function public.plaza_shop_purchase_hosted(
  uuid, text, integer, jsonb, bigint, timestamptz
) from public, anon, authenticated;
grant execute on function public.plaza_shop_purchase_hosted(
  uuid, text, integer, jsonb, bigint, timestamptz
) to service_role;
