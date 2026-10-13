-- BUG-04: server-owned ranked fight ids and bounty turn-ins.
--
-- Ranked PvP results are keyed on (user_id, fight_id) so the same fight cannot
-- be paid twice. Clients cannot insert. The game function writes through the
-- service role, in one transaction with the hosted save.
--
-- bounty_claims stays readable so the Plaza board can name who was first.
-- Clients lose INSERT (policy and grant). The game function inserts the first
-- completer in the same transaction as the save update.

create table if not exists public.ranked_pvp_results (
  user_id uuid not null references auth.users (id) on delete cascade,
  fight_id uuid not null,
  opponent_id uuid,
  outcome text not null check (outcome in ('win', 'loss')),
  gold_paid bigint not null default 0,
  code text,
  rounds jsonb not null default '[]'::jsonb,
  you_max_hp numeric not null default 0,
  them_max_hp numeric not null default 0,
  wins_remaining integer not null default 0,
  created_at timestamptz not null default now(),
  primary key (user_id, fight_id)
);

comment on table public.ranked_pvp_results is
  'Server-issued ranked fights. Primary key prevents a fight from being paid twice.';

create index if not exists ranked_pvp_results_created_idx
  on public.ranked_pvp_results (user_id, created_at desc);

alter table public.ranked_pvp_results enable row level security;

drop policy if exists "ranked pvp results readable self" on public.ranked_pvp_results;
create policy "ranked pvp results readable self" on public.ranked_pvp_results
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.ranked_pvp_results from public, anon, authenticated;
grant select on table public.ranked_pvp_results to authenticated;
grant all on table public.ranked_pvp_results to service_role;

drop policy if exists "bounty claims insert self" on public.bounty_claims;
revoke insert on table public.bounty_claims from public, anon, authenticated;
grant select on table public.bounty_claims to authenticated;
grant all on table public.bounty_claims to service_role;

-- =============================================================================
-- bounty_turn_in_hosted: first-place insert + save write in one transaction
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
begin
  if p_user_id is null then
    return jsonb_build_object('ok', false, 'reason', 'Sign in to claim bounties.');
  end if;
  if p_hour_key is null or p_bounty_id is null then
    return jsonb_build_object('ok', false, 'reason', 'Missing bounty.');
  end if;

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
    return jsonb_build_object('ok', false, 'reason', 'Save version conflict. Sync and retry.', 'conflict', true);
  end if;

  return jsonb_build_object(
    'ok', true,
    'firstCompleter', v_first,
    'version', v_version,
    'claim', jsonb_build_object(
      'hourKey', v_claim.hour_key,
      'bountyId', v_claim.bounty_id,
      'userId', v_claim.user_id,
      'username', v_claim.username,
      'claimedAt', v_claim.claimed_at
    )
  );
end;
$$;

revoke all on function public.bounty_turn_in_hosted(
  uuid, text, text, text, integer, jsonb, jsonb, bigint, timestamptz
) from public, anon, authenticated;
grant execute on function public.bounty_turn_in_hosted(
  uuid, text, text, text, integer, jsonb, jsonb, bigint, timestamptz
) to service_role;

-- =============================================================================
-- ranked_pvp_record_hosted: fight row + save write in one transaction
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
begin
  if p_user_id is null or p_fight_id is null then
    return jsonb_build_object('ok', false, 'reason', 'Unknown ranked fight.');
  end if;
  if p_outcome is null or p_outcome not in ('win', 'loss') then
    return jsonb_build_object('ok', false, 'reason', 'The server resolves ranked fights.');
  end if;

  insert into public.ranked_pvp_results (
    user_id, fight_id, opponent_id, outcome, gold_paid, code, rounds,
    you_max_hp, them_max_hp, wins_remaining, created_at
  ) values (
    p_user_id, p_fight_id, p_opponent_id, p_outcome, coalesce(p_gold_paid, 0), p_code,
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
      'goldPaid', v_existing.gold_paid,
      'code', v_existing.code,
      'rounds', v_existing.rounds,
      'youMaxHp', v_existing.you_max_hp,
      'themMaxHp', v_existing.them_max_hp,
      'winsRemaining', v_existing.wins_remaining
    );
  end if;

  update public.player_saves
     set payload = p_payload,
         version = p_expected_version + 1,
         advanced_to = p_now,
         rng_state = p_rng_state,
         updated_at = p_now
   where user_id = p_user_id
     and version = p_expected_version
  returning version into v_version;

  if v_version is null then
    return jsonb_build_object('ok', false, 'reason', 'Save version conflict. Sync and retry.', 'conflict', true);
  end if;

  return jsonb_build_object(
    'ok', true,
    'alreadyPaid', false,
    'version', v_version,
    'fightId', p_fight_id,
    'outcome', p_outcome,
    'goldPaid', coalesce(p_gold_paid, 0),
    'code', p_code,
    'winsRemaining', coalesce(p_wins_remaining, 0)
  );
end;
$$;

revoke all on function public.ranked_pvp_record_hosted(
  uuid, uuid, uuid, text, bigint, text, jsonb, numeric, numeric, integer, integer, jsonb, bigint, timestamptz
) from public, anon, authenticated;
grant execute on function public.ranked_pvp_record_hosted(
  uuid, uuid, uuid, text, bigint, text, jsonb, numeric, numeric, integer, integer, jsonb, bigint, timestamptz
) to service_role;
