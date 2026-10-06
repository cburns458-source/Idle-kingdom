-- RLS hardening: close privilege-escalation holes, split public vs owner
-- profile fields, scope chat/presence/guild hall reads, and lock tables the
-- client must not touch.
--
-- Apply by pasting into the Supabase SQL editor (this project does not use
-- `supabase db push`; see .github/workflows/deploy.yml). Edge-function changes
-- in the same PR deploy from test-launch automatically.

-- =============================================================================
-- Helpers: search_path pins the advisor flagged
-- =============================================================================

create or replace function public.server_now_ms()
returns bigint
language sql
stable
set search_path = public
as $$
  select (extract(epoch from clock_timestamp()) * 1000)::bigint;
$$;

create or replace function public.player_saves_require_active_session()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  current_session uuid;
begin
  select active_play_session_id
    into current_session
    from public.profiles
   where user_id = auth.uid();

  if current_session is null then
    return new;
  end if;

  if new.play_session_id is distinct from current_session then
    raise exception 'Signed in on another device'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

-- =============================================================================
-- Save uploads: refuse a write that was not based on the latest server copy
-- =============================================================================

create or replace function public.player_saves_require_fresh_base()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- Refuse an upload stamped older than the row already on the server. Edge
  -- paths (Bazaar) lock the row and write a newer stamp after they read it.
  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    raise exception 'Cloud save is newer on the server'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists player_saves_require_fresh_base on public.player_saves;
create trigger player_saves_require_fresh_base
  before insert or update on public.player_saves
  for each row
  execute function public.player_saves_require_fresh_base();

-- =============================================================================
-- Profiles: owner-only base table + public view
-- =============================================================================

drop policy if exists "profiles are readable" on public.profiles;
create policy "profiles are owner readable" on public.profiles
  for select using (auth.uid() = user_id);

-- Public fields others (and anon leaderboard sites) may see. privacy_* that
-- other players must honour are included; session seat and rename cooldown are
-- not. Hidden gear blanks equipment_json. Skills are never private.
create or replace view public.public_profiles
with (security_invoker = false)
as
select
  p.user_id,
  p.username,
  p.appearance_json,
  p.guild_id,
  p.privacy_public_gear,
  case
    when coalesce(p.privacy_public_gear, true) then p.equipment_json
    else null
  end as equipment_json,
  p.privacy_direct_messages,
  p.privacy_local_chat,
  p.name_color,
  p.motto,
  p.pet_cosmetic_id,
  p.updated_at
from public.profiles p;

comment on view public.public_profiles is
  'Intentionally public profile fields. Base profiles stay owner-only.';

grant select on public.public_profiles to anon, authenticated;

-- Leaderboard view: join public_profiles so anon boards keep working after
-- profiles become owner-only.
create or replace view public.leaderboard_entries
with (security_invoker = true)
as
select
  ls.user_id,
  ls.board_key,
  ls.value,
  ls.value_secondary,
  ls.updated_at,
  jsonb_build_object(
    'username', coalesce(nullif(p.username, ''), 'Adventurer'),
    'appearance_json', case
      when p.appearance_json is null or p.appearance_json = '{}'::jsonb then
        jsonb_build_object(
          'skinTone', 'APR-0001',
          'hairstyle', 'APR-0004',
          'hairColor', 'APR-0007',
          'expression', 'APR-0011',
          'beard', 'APR-0014',
          'genderPresentation', 'APR-0017'
        )
      else p.appearance_json
    end,
    'guild_id', p.guild_id,
    'guilds', case
      when g.name is null then null
      else jsonb_build_object('name', g.name, 'tag', g.tag)
    end
  ) as profiles
from public.leaderboard_snapshots ls
left join public.public_profiles p on p.user_id = ls.user_id
left join public.guilds g on g.id = p.guild_id;

grant select on public.leaderboard_entries to anon, authenticated;

-- =============================================================================
-- Presence: signed-in reads; friends-location flag as a real column
-- =============================================================================

alter table public.activity_presence
  add column if not exists share_location_with_friends boolean not null default true;

comment on column public.activity_presence.share_location_with_friends is
  'When false, friends lists omit this player''s world location. Nearby peers at the same spot still see them.';

drop policy if exists "presence readable" on public.activity_presence;
create policy "presence readable by signed in" on public.activity_presence
  for select using (auth.uid() is not null);

-- =============================================================================
-- Chat: signed-in, channel-scoped reads; no client inserts
-- =============================================================================

drop policy if exists "chat readable" on public.chat_messages;
create policy "chat readable by participants" on public.chat_messages
  for select using (
    auth.uid() is not null
    and (
      channel_key = 'global'
      or channel_key like 'local:%'
      or (
        channel_key like 'guild:%'
        and (
          public.guild_role_of(nullif(substr(channel_key, 7), '')::uuid, auth.uid()) is not null
          or exists (
            select 1 from public.guild_guests gg
             where gg.guild_id = nullif(substr(channel_key, 7), '')::uuid
               and gg.user_id = auth.uid()
          )
        )
      )
      or (
        channel_key like 'dm:%'
        and position(auth.uid()::text in substr(channel_key, 4)) > 0
      )
    )
  );

drop policy if exists "chat insert self" on public.chat_messages;

-- =============================================================================
-- Moderation tables: RLS on, no client policies (hosted sync is a follow-up)
-- =============================================================================

alter table public.chat_cooldowns enable row level security;
alter table public.player_blocks enable row level security;
alter table public.player_mutes enable row level security;
alter table public.chat_reports enable row level security;

revoke all on table public.chat_cooldowns from anon, authenticated;
revoke all on table public.player_blocks from anon, authenticated;
revoke all on table public.player_mutes from anon, authenticated;
revoke all on table public.chat_reports from anon, authenticated;

grant all on table public.chat_cooldowns to service_role;
grant all on table public.player_blocks to service_role;
grant all on table public.player_mutes to service_role;
grant all on table public.chat_reports to service_role;

-- =============================================================================
-- Bazaar message board: removed from product; lock the table
-- =============================================================================

drop policy if exists "bazaar posts readable" on public.bazaar_posts;
drop policy if exists "bazaar posts insert self" on public.bazaar_posts;
revoke all on table public.bazaar_posts from anon, authenticated;
grant all on table public.bazaar_posts to service_role;

-- =============================================================================
-- Public boards / guild browse: signed-in (leaderboards stay anon-readable)
-- =============================================================================

drop policy if exists "guilds readable" on public.guilds;
create policy "guilds readable by signed in" on public.guilds
  for select using (auth.uid() is not null);

drop policy if exists "guild members readable" on public.guild_members;
create policy "guild members readable by signed in" on public.guild_members
  for select using (auth.uid() is not null);

drop policy if exists "guild guests readable" on public.guild_guests;
create policy "guild guests readable by signed in" on public.guild_guests
  for select using (auth.uid() is not null);

drop policy if exists "guild projects readable" on public.guild_projects;
create policy "guild projects readable by signed in" on public.guild_projects
  for select using (auth.uid() is not null);

drop policy if exists "guild challenges readable" on public.guild_challenges;
create policy "guild challenges readable by signed in" on public.guild_challenges
  for select using (auth.uid() is not null);

do $$
begin
  if to_regclass('public.bounty_claims') is null then
    return;
  end if;
  execute 'drop policy if exists "bounty claims readable" on public.bounty_claims';
  execute $p$
    create policy "bounty claims readable by signed in" on public.bounty_claims
      for select using (auth.uid() is not null)
  $p$;
end $$;

-- Leaderboard snapshots stay public for third-party board sites.
-- (policy "leaderboards readable" using (true) remains)

-- =============================================================================
-- Guild hall: full row for members; public tier summary for signed-in browsers
-- =============================================================================

drop policy if exists "guild halls readable" on public.guild_halls;
create policy "guild halls readable by members" on public.guild_halls
  for select using (public.guild_role_of(guild_id, auth.uid()) is not null);

create or replace view public.guild_hall_tiers
with (security_invoker = false)
as
select
  h.guild_id,
  h.completed_tiers,
  h.debt_paid_off
from public.guild_halls h;

comment on view public.guild_hall_tiers is
  'Public hall progress: tiers and whether the debt is cleared. Storehouse and debt ledger stay members-only.';

grant select on public.guild_hall_tiers to authenticated;

-- =============================================================================
-- Guild members: stop self-escalation of role / guild_id
-- =============================================================================

create or replace function public.guild_members_guard_sensitive_columns()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  actor uuid := auth.uid();
  sensitive_changed boolean;
  is_leader boolean;
begin
  sensitive_changed :=
    new.role is distinct from old.role
    or new.guild_id is distinct from old.guild_id
    or new.joined_at is distinct from old.joined_at;

  if not sensitive_changed then
    return new;
  end if;

  -- Edge/admin paths use the service role (no JWT sub) and may rewrite ranks.
  if actor is null and current_user in ('service_role', 'supabase_admin', 'postgres') then
    return new;
  end if;

  select exists (
    select 1 from public.guilds g
     where g.id = old.guild_id and g.leader_id = actor
  ) into is_leader;

  if is_leader then
    return new;
  end if;

  if new.role is distinct from old.role then
    raise exception 'Only the guild leader can change roles';
  end if;
  if new.guild_id is distinct from old.guild_id then
    raise exception 'Cannot change guild association this way';
  end if;
  if new.joined_at is distinct from old.joined_at then
    raise exception 'Cannot change joined_at';
  end if;

  return new;
end;
$$;

drop trigger if exists guild_members_guard_sensitive_columns on public.guild_members;
create trigger guild_members_guard_sensitive_columns
  before update on public.guild_members
  for each row
  execute function public.guild_members_guard_sensitive_columns();

-- Keep self/leader update+delete (019), with the trigger above freezing
-- role / guild_id / joined_at for non-leaders.
drop policy if exists "guild members update" on public.guild_members;
create policy "guild members update" on public.guild_members
  for update
  using (
    auth.uid() = user_id
    or auth.uid() = (select leader_id from public.guilds where id = guild_id)
  )
  with check (
    auth.uid() = user_id
    or auth.uid() = (select leader_id from public.guilds where id = guild_id)
  );

drop policy if exists "guild members delete" on public.guild_members;
create policy "guild members delete" on public.guild_members
  for delete using (
    auth.uid() = user_id
    or auth.uid() = (select leader_id from public.guilds where id = guild_id)
  );

-- Self-insert only as recruit into an open guild, or as founding leader.
-- Managers may still seat accepted applicants.
drop policy if exists "guild members insert" on public.guild_members;
create policy "guild members insert" on public.guild_members
  for insert with check (
    public.is_guild_manager(guild_id)
    or (
      auth.uid() = user_id
      and role = 'recruit'
      and exists (
        select 1 from public.guilds g
         where g.id = guild_id and g.join_policy = 'open'
      )
      and not exists (
        select 1 from public.guild_members m where m.user_id = auth.uid()
      )
    )
    or (
      auth.uid() = user_id
      and role = 'leader'
      and exists (
        select 1 from public.guilds g
         where g.id = guild_id and g.leader_id = auth.uid()
      )
    )
  );

-- Guest self-insert only when the guild auto-accepts guests.
drop policy if exists "guild guests insert" on public.guild_guests;
create policy "guild guests insert" on public.guild_guests
  for insert with check (
    public.is_guild_manager(guild_id)
    or (
      auth.uid() = user_id
      and exists (
        select 1 from public.guilds g
         where g.id = guild_id and g.guest_auto_accept
      )
      and not exists (
        select 1 from public.guild_guests gg where gg.user_id = auth.uid()
      )
    )
  );

-- =============================================================================
-- Guild projects / challenges / halls: no raw client rewrites
-- =============================================================================

drop policy if exists "guild projects writable by members" on public.guild_projects;
drop policy if exists "guild challenges writable by members" on public.guild_challenges;
drop policy if exists "guild halls writable by members" on public.guild_halls;

-- Founders still seed the first project/challenge/hall through these narrow inserts.
create policy "guild projects insert by managers" on public.guild_projects
  for insert with check (public.is_guild_manager(guild_id));

create policy "guild challenges insert by managers" on public.guild_challenges
  for insert with check (public.is_guild_manager(guild_id));

create policy "guild halls insert by managers" on public.guild_halls
  for insert with check (public.is_guild_manager(guild_id));

-- Additive project contributions (any member).
create or replace function public.guild_contribute_project(
  p_project_id uuid,
  p_amount numeric
)
returns public.guild_projects
language plpgsql
security definer
set search_path = public
as $$
declare
  v_project public.guild_projects;
begin
  if auth.uid() is null then
    raise exception 'Sign in first.';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Contribute a positive amount.';
  end if;

  select * into v_project
    from public.guild_projects
   where id = p_project_id
   for update;
  if not found then
    raise exception 'Project not found.';
  end if;
  if public.guild_role_of(v_project.guild_id, auth.uid()) is null then
    raise exception 'Join a guild first.';
  end if;

  update public.guild_projects
     set contributed = contributed + p_amount
   where id = p_project_id
  returning * into v_project;

  return v_project;
end;
$$;

revoke all on function public.guild_contribute_project(uuid, numeric) from public, anon;
grant execute on function public.guild_contribute_project(uuid, numeric) to authenticated;

-- Additive hall debt payment. Gold leaves the player save on a later server-run
-- economy pass; this RPC only updates the shared ledger.
create or replace function public.guild_pay_hall_debt(p_amount numeric)
returns public.guild_halls
language plpgsql
security definer
set search_path = public
as $$
declare
  v_membership public.guild_members;
  v_hall public.guild_halls;
  v_pay numeric;
  v_paid_by jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in first.';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Pay a positive amount.';
  end if;

  select * into v_membership
    from public.guild_members
   where user_id = auth.uid()
   limit 1;
  if not found then
    raise exception 'Join a guild first.';
  end if;
  if v_membership.role = 'recruit' then
    raise exception 'Recruits cannot pay the hall debt.';
  end if;

  select * into v_hall
    from public.guild_halls
   where guild_id = v_membership.guild_id
   for update;
  if not found then
    raise exception 'Guild hall not found.';
  end if;
  if v_hall.debt_paid_off or v_hall.debt_remaining <= 0 then
    raise exception 'Hall debt is already cleared.';
  end if;

  v_pay := least(p_amount, v_hall.debt_remaining);
  v_paid_by := coalesce(v_hall.debt_paid_by, '{}'::jsonb);
  v_paid_by := jsonb_set(
    v_paid_by,
    array[auth.uid()::text],
    to_jsonb(coalesce((v_paid_by ->> auth.uid()::text)::numeric, 0) + v_pay),
    true
  );

  update public.guild_halls
     set debt_remaining = debt_remaining - v_pay,
         debt_paid_by = v_paid_by,
         debt_paid_off = (debt_remaining - v_pay) <= 0,
         updated_at = now()
   where guild_id = v_membership.guild_id
  returning * into v_hall;

  return v_hall;
end;
$$;

revoke all on function public.guild_pay_hall_debt(numeric) from public, anon;
grant execute on function public.guild_pay_hall_debt(numeric) to authenticated;

-- Additive storehouse donation (merge one stack). Withdrawal is a follow-up
-- once rank permissions exist.
create or replace function public.guild_donate_hall_item(
  p_item_id text,
  p_quantity numeric
)
returns public.guild_halls
language plpgsql
security definer
set search_path = public
as $$
declare
  v_membership public.guild_members;
  v_hall public.guild_halls;
  v_store jsonb;
  v_found boolean := false;
  v_elem jsonb;
  v_idx int := 0;
  v_next jsonb := '[]'::jsonb;
  v_qty numeric;
begin
  if auth.uid() is null then
    raise exception 'Sign in first.';
  end if;
  if p_item_id is null or btrim(p_item_id) = '' then
    raise exception 'Missing item.';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Donate a positive quantity.';
  end if;

  select * into v_membership
    from public.guild_members
   where user_id = auth.uid()
   limit 1;
  if not found then
    raise exception 'Join a guild first.';
  end if;

  select * into v_hall
    from public.guild_halls
   where guild_id = v_membership.guild_id
   for update;
  if not found then
    raise exception 'Guild hall not found.';
  end if;

  v_store := coalesce(v_hall.storehouse, '[]'::jsonb);
  for v_elem in select * from jsonb_array_elements(v_store)
  loop
    if not v_found and (v_elem ->> 'itemId') = p_item_id then
      v_qty := coalesce((v_elem ->> 'quantity')::numeric, 0) + p_quantity;
      v_next := v_next || jsonb_build_array(
        jsonb_build_object('itemId', p_item_id, 'quantity', v_qty)
      );
      v_found := true;
    else
      v_next := v_next || jsonb_build_array(v_elem);
    end if;
    v_idx := v_idx + 1;
  end loop;
  if not v_found then
    v_next := v_next || jsonb_build_array(
      jsonb_build_object('itemId', p_item_id, 'quantity', p_quantity)
    );
  end if;

  update public.guild_halls
     set storehouse = v_next,
         updated_at = now()
   where guild_id = v_membership.guild_id
  returning * into v_hall;

  return v_hall;
end;
$$;

revoke all on function public.guild_donate_hall_item(text, numeric) from public, anon;
grant execute on function public.guild_donate_hall_item(text, numeric) to authenticated;

-- Leader-only role changes (also covers the old self-update hole).
create or replace function public.guild_set_member_role(
  p_guild_id uuid,
  p_target_user_id uuid,
  p_role text
)
returns public.guild_members
language plpgsql
security definer
set search_path = public
as $$
declare
  v_guild public.guilds;
  v_member public.guild_members;
begin
  if auth.uid() is null then
    raise exception 'Sign in first.';
  end if;
  if p_role not in ('officer', 'veteran', 'member', 'recruit') then
    raise exception 'Invalid role.';
  end if;

  select * into v_guild from public.guilds where id = p_guild_id;
  if not found then
    raise exception 'Guild not found.';
  end if;
  if v_guild.leader_id is distinct from auth.uid() then
    raise exception 'Only the leader can change roles.';
  end if;
  if p_target_user_id = v_guild.leader_id then
    raise exception 'Cannot change the leader''s role.';
  end if;

  update public.guild_members
     set role = p_role
   where guild_id = p_guild_id
     and user_id = p_target_user_id
  returning * into v_member;
  if not found then
    raise exception 'Member not found.';
  end if;
  return v_member;
end;
$$;

revoke all on function public.guild_set_member_role(uuid, uuid, text) from public, anon;
grant execute on function public.guild_set_member_role(uuid, uuid, text) to authenticated;

-- =============================================================================
-- SECURITY DEFINER helpers: intentional exposure, but pin grants
-- =============================================================================

revoke all on function public.guild_role_of(uuid, uuid) from public;
grant execute on function public.guild_role_of(uuid, uuid) to authenticated, service_role;

revoke all on function public.is_guild_manager(uuid) from public;
grant execute on function public.is_guild_manager(uuid) to authenticated, service_role;

notify pgrst, 'reload schema';
