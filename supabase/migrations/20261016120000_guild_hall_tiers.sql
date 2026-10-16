-- SOC-01: guild hall tiers, running gold total, guild_may, bank, log.
--
-- Completing tiers, spending storehouse materials, gold chip-ins, and bank
-- withdrawals are decided in the game edge function. This migration stores the
-- shared hall, bank, permissions, and log, and writes the player save + hall
-- in one service-role RPC so gold and materials cannot double-spend under
-- concurrency. Clients lost execute on the old ledger-only hall RPCs in
-- 20261007045115; those stay revoked.

-- =============================================================================
-- Hall: running gold total, revision, bank jsonb
-- =============================================================================

alter table public.guild_halls
  add column if not exists gold_contributed numeric not null default 0,
  add column if not exists gold_contributed_by jsonb not null default '{}'::jsonb,
  add column if not exists hall_revision bigint not null default 0,
  add column if not exists bank_items jsonb not null default '[]'::jsonb;

comment on column public.guild_halls.gold_contributed is
  'Running gold total members have chipped in, capped at 1,000,000. Not a stored coffer.';
comment on column public.guild_halls.gold_contributed_by is
  'How much gold each member has chipped in, keyed by user id.';
comment on column public.guild_halls.hall_revision is
  'Compare-and-swap token. The game function refuses a hall write that names the wrong revision.';
comment on column public.guild_halls.bank_items is
  'Guild bank stacks: [{"id","itemId","quantity","enchantmentId","section"}]. section is main or up_for_grabs.';

-- Existing halls partway through the old 1M debt: paid gold becomes the running total.
update public.guild_halls
   set gold_contributed = greatest(
         0,
         least(
           1000000,
           1000000 - coalesce(debt_remaining, 1000000)
         )
       ),
       gold_contributed_by = coalesce(debt_paid_by, '{}'::jsonb)
 where gold_contributed = 0
   and coalesce(debt_remaining, 1000000) < 1000000;

comment on column public.guild_halls.completed_tiers is
  'Tier ids finished, in order: build_the_hall, hall_bank, hall_boxing_ring, hall_indoor_garden, hall_arcana_station, hall_monster_cage.';

-- =============================================================================
-- Per-rank permission table on the guild (leader-editable)
-- =============================================================================

alter table public.guilds
  add column if not exists permissions jsonb not null default jsonb_build_object(
    'deposit', jsonb_build_array('leader', 'officer', 'veteran', 'member', 'recruit'),
    'withdraw', jsonb_build_array('leader', 'officer'),
    'move_up_for_grabs', jsonb_build_array('leader', 'officer')
  );

comment on column public.guilds.permissions is
  'Per-rank hall/bank actions. Keys: deposit, withdraw, move_up_for_grabs. Leader always may.';

-- =============================================================================
-- Guild log
-- =============================================================================

create table if not exists public.guild_log_entries (
  id uuid primary key default gen_random_uuid(),
  guild_id uuid not null references public.guilds (id) on delete cascade,
  kind text not null check (kind in ('tier_complete', 'donation', 'join', 'leave', 'rank_change')),
  created_at timestamptz not null default now(),
  actor_user_id uuid,
  actor_username text not null default '',
  role text,
  target_user_id uuid,
  target_username text,
  tier_id text,
  message text not null default '',
  gold numeric not null default 0,
  items jsonb not null default '[]'::jsonb
);

create index if not exists guild_log_entries_guild_created_idx
  on public.guild_log_entries (guild_id, created_at desc);

comment on table public.guild_log_entries is
  'Newest-first guild log: tier finishes, donations, joins, leaves, rank changes.';

alter table public.guild_log_entries enable row level security;

drop policy if exists "guild log readable by members" on public.guild_log_entries;
create policy "guild log readable by members" on public.guild_log_entries
  for select using (
    public.guild_role_of(guild_id, (select auth.uid())) is not null
  );

revoke insert, update, delete on table public.guild_log_entries from anon, authenticated;
grant select on table public.guild_log_entries to authenticated;
grant all on table public.guild_log_entries to service_role;

-- =============================================================================
-- guild_may: one permission check
-- =============================================================================

create or replace function public.guild_may(p_actor uuid, p_guild uuid, p_action text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_leader uuid;
  v_table jsonb;
  v_role text;
  v_ranks jsonb;
begin
  if p_actor is null or p_guild is null or p_action is null then
    return false;
  end if;
  if p_action not in ('deposit', 'withdraw', 'move_up_for_grabs') then
    return false;
  end if;

  select g.leader_id, coalesce(g.permissions, '{}'::jsonb)
    into v_leader, v_table
    from public.guilds g
   where g.id = p_guild;
  if not found then
    return false;
  end if;
  if v_leader = p_actor then
    return true;
  end if;

  select m.role into v_role
    from public.guild_members m
   where m.guild_id = p_guild
     and m.user_id = p_actor;
  if v_role is null then
    return false;
  end if;

  if v_table ? p_action then
    v_ranks := v_table -> p_action;
    return exists (
      select 1
        from jsonb_array_elements_text(coalesce(v_ranks, '[]'::jsonb)) r
       where r = v_role
    );
  end if;

  if p_action = 'deposit' then
    return true;
  end if;
  return v_role = 'officer';
end;
$$;

revoke all on function public.guild_may(uuid, uuid, text) from public, anon;
grant execute on function public.guild_may(uuid, uuid, text) to authenticated, service_role;

-- =============================================================================
-- Leader-only permission table write
-- =============================================================================

create or replace function public.guild_set_permissions(p_guild_id uuid, p_permissions jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_guild public.guilds;
  v_next jsonb := '{}'::jsonb;
  v_action text;
  v_allowed text[];
  v_rank text;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'reason', 'Sign in first.');
  end if;
  select * into v_guild from public.guilds where id = p_guild_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'Guild not found.');
  end if;
  if v_guild.leader_id is distinct from auth.uid() then
    return jsonb_build_object('ok', false, 'reason', 'Only the leader can change permissions.');
  end if;

  foreach v_action in array array['deposit', 'withdraw', 'move_up_for_grabs']
  loop
    v_allowed := array[]::text[];
    if jsonb_typeof(p_permissions -> v_action) = 'array' then
      for v_rank in
        select value
          from jsonb_array_elements_text(p_permissions -> v_action)
      loop
        if v_rank in ('leader', 'officer', 'veteran', 'member', 'recruit')
           and not v_rank = any (v_allowed) then
          v_allowed := v_allowed || v_rank;
        end if;
      end loop;
    end if;
    if v_action = 'deposit' and cardinality(v_allowed) = 0 then
      v_allowed := array['leader', 'officer', 'veteran', 'member', 'recruit'];
    end if;
    if v_action <> 'deposit' and cardinality(v_allowed) = 0 then
      v_allowed := array['leader', 'officer'];
    end if;
    if not 'leader' = any (v_allowed) then
      v_allowed := array['leader'] || v_allowed;
    end if;
    v_next := v_next || jsonb_build_object(v_action, to_jsonb(v_allowed));
  end loop;

  update public.guilds
     set permissions = v_next
   where id = p_guild_id;

  return jsonb_build_object('ok', true, 'permissions', v_next);
end;
$$;

revoke all on function public.guild_set_permissions(uuid, jsonb) from public, anon;
grant execute on function public.guild_set_permissions(uuid, jsonb) to authenticated, service_role;

-- =============================================================================
-- Log append with consecutive donation merge
-- =============================================================================

create or replace function public.guild_append_log(p_guild_id uuid, p_entry jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text := coalesce(p_entry ->> 'kind', '');
  v_actor uuid := nullif(p_entry ->> 'actor_user_id', '')::uuid;
  v_last public.guild_log_entries;
  v_items jsonb;
  v_existing jsonb;
  v_added jsonb;
  v_row jsonb;
  v_found boolean;
  v_next jsonb;
begin
  if v_kind not in ('tier_complete', 'donation', 'join', 'leave', 'rank_change') then
    return;
  end if;

  if v_kind = 'donation' and v_actor is not null then
    select * into v_last
      from public.guild_log_entries
     where guild_id = p_guild_id
     order by created_at desc, id desc
     limit 1;
    if found and v_last.kind = 'donation' and v_last.actor_user_id is not distinct from v_actor then
      v_existing := coalesce(v_last.items, '[]'::jsonb);
      v_added := coalesce(p_entry -> 'items', '[]'::jsonb);
      v_next := '[]'::jsonb;
      for v_row in select * from jsonb_array_elements(v_existing)
      loop
        v_next := v_next || jsonb_build_array(v_row);
      end loop;
      for v_row in select * from jsonb_array_elements(v_added)
      loop
        v_found := false;
        v_items := '[]'::jsonb;
        for v_existing in select * from jsonb_array_elements(v_next)
        loop
          if not v_found and (v_existing ->> 'itemId') = (v_row ->> 'itemId') then
            v_items := v_items || jsonb_build_array(
              jsonb_build_object(
                'itemId', v_row ->> 'itemId',
                'quantity', coalesce((v_existing ->> 'quantity')::numeric, 0)
                            + coalesce((v_row ->> 'quantity')::numeric, 0)
              )
            );
            v_found := true;
          else
            v_items := v_items || jsonb_build_array(v_existing);
          end if;
        end loop;
        if not v_found then
          v_items := v_items || jsonb_build_array(v_row);
        end if;
        v_next := v_items;
      end loop;
      update public.guild_log_entries
         set gold = v_last.gold + coalesce((p_entry ->> 'gold')::numeric, 0),
             items = v_next,
             message = coalesce(nullif(p_entry ->> 'message', ''), v_last.message)
       where id = v_last.id;
      return;
    end if;
  end if;

  insert into public.guild_log_entries (
    guild_id, kind, actor_user_id, actor_username, role,
    target_user_id, target_username, tier_id, message, gold, items
  ) values (
    p_guild_id,
    v_kind,
    v_actor,
    coalesce(p_entry ->> 'actor_username', ''),
    nullif(p_entry ->> 'role', ''),
    nullif(p_entry ->> 'target_user_id', '')::uuid,
    nullif(p_entry ->> 'target_username', ''),
    nullif(p_entry ->> 'tier_id', ''),
    coalesce(p_entry ->> 'message', ''),
    coalesce((p_entry ->> 'gold')::numeric, 0),
    coalesce(p_entry -> 'items', '[]'::jsonb)
  );
end;
$$;

revoke all on function public.guild_append_log(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.guild_append_log(uuid, jsonb) to service_role;

-- Join / leave / rank-change lines. Lock the hall so a donation merge in the
-- same guild cannot race a roster event sitting between two chip-ins.
create or replace function public.guild_log_member_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_guild uuid;
begin
  v_guild := coalesce(new.guild_id, old.guild_id);
  perform 1 from public.guild_halls where guild_id = v_guild for update;
  if tg_op = 'INSERT' then
    perform public.guild_append_log(
      new.guild_id,
      jsonb_build_object(
        'kind', 'join',
        'actor_user_id', new.user_id,
        'actor_username', coalesce(new.username, 'Adventurer'),
        'role', new.role,
        'message', coalesce(new.username, 'Adventurer') || ' joined the guild.'
      )
    );
    return new;
  end if;
  if tg_op = 'DELETE' then
    perform public.guild_append_log(
      old.guild_id,
      jsonb_build_object(
        'kind', 'leave',
        'actor_user_id', old.user_id,
        'actor_username', coalesce(old.username, 'Adventurer'),
        'role', old.role,
        'message', coalesce(old.username, 'Adventurer') || ' left the guild.'
      )
    );
    return old;
  end if;
  if tg_op = 'UPDATE' and new.role is distinct from old.role then
    perform public.guild_append_log(
      new.guild_id,
      jsonb_build_object(
        'kind', 'rank_change',
        'actor_user_id', new.user_id,
        'actor_username', coalesce(new.username, 'Adventurer'),
        'role', new.role,
        'target_user_id', new.user_id,
        'target_username', coalesce(new.username, 'Adventurer'),
        'message', coalesce(new.username, 'Adventurer') || ' is now ' || coalesce(new.role, 'member') || '.'
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists guild_log_member_change on public.guild_members;
create trigger guild_log_member_change
  after insert or update of role or delete on public.guild_members
  for each row
  execute function public.guild_log_member_change();

-- =============================================================================
-- Atomic save + hall write (service role; called by the game function)
-- =============================================================================

create or replace function public.guild_commit_hall(
  p_user_id uuid,
  p_expected_save_version integer,
  p_expected_hall_revision bigint,
  p_payload jsonb,
  p_rng_state bigint,
  p_now timestamptz,
  p_hall jsonb,
  p_log jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member public.guild_members;
  v_hall public.guild_halls;
  v_version integer;
  v_gold numeric;
  v_entry jsonb;
begin
  if p_user_id is null then
    return jsonb_build_object('ok', false, 'reason', 'Sign in first.');
  end if;

  select * into v_member
    from public.guild_members
   where user_id = p_user_id
   limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'Join a guild first.');
  end if;

  select * into v_hall
    from public.guild_halls
   where guild_id = v_member.guild_id
   for update;
  if not found then
    insert into public.guild_halls (guild_id) values (v_member.guild_id)
    on conflict (guild_id) do nothing;
    select * into v_hall
      from public.guild_halls
     where guild_id = v_member.guild_id
     for update;
  end if;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'Guild hall not found.');
  end if;

  if coalesce(p_expected_hall_revision, 0) is distinct from coalesce(v_hall.hall_revision, 0) then
    return jsonb_build_object('ok', false, 'conflict', 'hall', 'reason', 'Hall changed. Sync and retry.');
  end if;

  v_gold := least(
    1000000,
    greatest(0, coalesce((p_hall ->> 'gold_contributed')::numeric, v_hall.gold_contributed, 0))
  );

  update public.player_saves
     set payload = p_payload,
         version = p_expected_save_version + 1,
         advanced_to = p_now,
         rng_state = p_rng_state,
         updated_at = p_now
   where user_id = p_user_id
     and version = p_expected_save_version
  returning version into v_version;

  if v_version is null then
    return jsonb_build_object('ok', false, 'conflict', 'save', 'reason', 'Save version conflict. Sync and retry.');
  end if;

  update public.guild_halls
     set gold_contributed = v_gold,
         gold_contributed_by = coalesce(p_hall -> 'gold_contributed_by', gold_contributed_by),
         debt_remaining = greatest(0, 1000000 - v_gold),
         debt_paid_off = v_gold >= 1000000,
         debt_paid_by = coalesce(p_hall -> 'gold_contributed_by', gold_contributed_by),
         storehouse = coalesce(p_hall -> 'storehouse', storehouse),
         completed_tiers = coalesce(p_hall -> 'completed_tiers', completed_tiers),
         bank_items = coalesce(p_hall -> 'bank_items', bank_items),
         hall_revision = coalesce(hall_revision, 0) + 1,
         updated_at = p_now
   where guild_id = v_member.guild_id
  returning * into v_hall;

  if jsonb_typeof(p_log) = 'array' then
    for v_entry in select * from jsonb_array_elements(p_log)
    loop
      perform public.guild_append_log(v_member.guild_id, v_entry);
    end loop;
  end if;

  return jsonb_build_object(
    'ok', true,
    'version', v_version,
    'hall_revision', v_hall.hall_revision
  );
end;
$$;

revoke all on function public.guild_commit_hall(uuid, integer, bigint, jsonb, bigint, timestamptz, jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function public.guild_commit_hall(uuid, integer, bigint, jsonb, bigint, timestamptz, jsonb, jsonb)
  to service_role;

-- Keep the old ledger-only RPCs unusable from clients.
revoke all on function public.guild_pay_hall_debt(numeric) from public, anon, authenticated;
revoke all on function public.guild_donate_hall_item(text, numeric) from public, anon, authenticated;

-- Public progress: tiers plus the running gold total (not the storehouse or bank).
-- Drop first: CREATE OR REPLACE cannot insert gold_contributed ahead of debt_paid_off.
drop view if exists public.guild_hall_tiers;
create view public.guild_hall_tiers
with (security_invoker = false)
as
select
  h.guild_id,
  h.completed_tiers,
  h.gold_contributed,
  h.debt_paid_off
from public.guild_halls h;

comment on view public.guild_hall_tiers is
  'Public hall progress: finished tiers and running gold total. Storehouse, bank, and chip-in ledger stay members-only.';

grant select on public.guild_hall_tiers to authenticated;

notify pgrst, 'reload schema';
