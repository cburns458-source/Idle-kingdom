-- Wave E: guild create, join, accept, leave, and kick as single transactions.
--
-- Each of these used to be several client writes (guild, roster, profile tag,
-- hall, starter goals, request cleanup). A dropped connection between them
-- left a guild with no hall, a member with no tag, or a roster past the cap.
-- Every function here locks the guild row first, so two joins or two accepts
-- cannot both see room for the last seat.
--
-- Refusals come back as {ok: false, reason} rather than raised errors so the
-- client can show the sentence as written.
--
-- guild_create_hosted is service-role only: the game edge function charges
-- the founding gold in the same request, so a client must not be able to
-- found a guild without going through it. With these in place the direct
-- insert policies on guilds, guild_members, and guild_guests are dropped.

-- Matches packages/ik_net guildMaxMembers.
create or replace function public.guild_max_members()
returns int
language sql
immutable
set search_path = ''
as $$ select 25 $$;

revoke all on function public.guild_max_members() from public, anon;
grant execute on function public.guild_max_members() to authenticated, service_role;

-- A roster row's name, look, and level, read from what the player published.
create or replace function public.guild_member_facts(p_user uuid, p_fallback_name text default null)
returns table (username text, appearance_json jsonb, total_level numeric)
language sql
stable
security definer
set search_path = ''
as $$
  select
    coalesce(nullif(p.username, ''), nullif(p_fallback_name, ''), 'Adventurer'),
    coalesce(p.appearance_json, '{}'::jsonb),
    coalesce(
      (select l.value from public.leaderboard_snapshots l
        where l.user_id = p_user and l.board_key = 'total_level'),
      1
    )
  from (select 1) one
  left join public.profiles p on p.user_id = p_user;
$$;

revoke all on function public.guild_member_facts(uuid, text) from public, anon, authenticated;
grant execute on function public.guild_member_facts(uuid, text) to service_role;

-- =============================================================================
-- Create (service role, called by the game function after the gold check)
-- =============================================================================

create or replace function public.guild_create_hosted(p_user_id uuid, p_guild jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_guild public.guilds;
  v_name text := btrim(coalesce(p_guild ->> 'name', ''));
  v_tag text := upper(btrim(coalesce(p_guild ->> 'tag', '')));
  v_policy text := coalesce(nullif(p_guild ->> 'join_policy', ''), 'open');
  v_facts record;
begin
  if p_user_id is null then
    return jsonb_build_object('ok', false, 'reason', 'Sign in to create a guild.');
  end if;
  if v_name = '' or v_tag = '' then
    return jsonb_build_object('ok', false, 'reason', 'Enter a guild name and tag.');
  end if;
  if v_policy not in ('open', 'closed') then
    v_policy := 'open';
  end if;
  if exists (select 1 from public.guild_members m where m.user_id = p_user_id) then
    return jsonb_build_object('ok', false, 'reason', 'Leave your current guild before creating another.');
  end if;

  begin
    insert into public.guilds (
      name, tag, description, emblem, leader_id, join_policy,
      rank_labels, rank_icon_theme, guest_auto_accept, skill_milestone_settings
    ) values (
      v_name,
      v_tag,
      left(coalesce(p_guild ->> 'description', ''), 500),
      coalesce(p_guild -> 'emblem', '{}'::jsonb),
      p_user_id,
      v_policy,
      coalesce(
        p_guild -> 'rank_labels',
        '{"leader": "Leader", "officer": "Officer", "veteran": "Veteran", "member": "Member", "recruit": "Recruit"}'::jsonb
      ),
      coalesce(nullif(p_guild ->> 'rank_icon_theme', ''), 'stripes'),
      coalesce((p_guild ->> 'guest_auto_accept')::boolean, false),
      coalesce(
        p_guild -> 'skill_milestone_settings',
        '{"enabled": true, "levelStep": 10, "levelStart": 50, "xpStepMillion": 25, "xpStartMillion": 125}'::jsonb
      )
    )
    returning * into v_guild;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'reason', 'That guild name or tag is taken.');
  end;

  select * into v_facts from public.guild_member_facts(p_user_id);
  insert into public.guild_members (guild_id, user_id, role, username, appearance_json, total_level)
  values (v_guild.id, p_user_id, 'leader', v_facts.username, v_facts.appearance_json, v_facts.total_level);

  update public.profiles set guild_id = v_guild.id, updated_at = now() where user_id = p_user_id;
  delete from public.guild_applications where user_id = p_user_id;
  delete from public.guild_guests where user_id = p_user_id;

  insert into public.guild_halls (guild_id) values (v_guild.id) on conflict (guild_id) do nothing;
  -- Matches packages/ik_net guildStorehouseProject* and guildMonsterChallenge*.
  insert into public.guild_projects (guild_id, name, description, goal_amount, reward_label)
  values (
    v_guild.id,
    'Guild Storehouse',
    'Pool resources for cosmetic recognition.',
    1000,
    'Guild banner cosmetic (recognition)'
  );
  insert into public.guild_challenges (guild_id, name, board_key, goal_value)
  values (v_guild.id, 'Weekly Monster Hunt', 'monsters_killed', 100);

  return jsonb_build_object('ok', true, 'guild', to_jsonb(v_guild));
end;
$$;

revoke all on function public.guild_create_hosted(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.guild_create_hosted(uuid, jsonb) to service_role;

-- =============================================================================
-- Join an open guild
-- =============================================================================

create or replace function public.guild_join_open(p_guild_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_guild public.guilds;
  v_facts record;
begin
  if v_me is null then
    return jsonb_build_object('ok', false, 'reason', 'Sign in to join a guild.');
  end if;
  select * into v_guild from public.guilds where id = p_guild_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'Guild not found.');
  end if;
  if exists (select 1 from public.guild_members m where m.user_id = v_me) then
    return jsonb_build_object('ok', false, 'reason', 'Already in a guild.');
  end if;
  if (select count(*) from public.guild_members m where m.guild_id = p_guild_id)
     >= public.guild_max_members() then
    return jsonb_build_object(
      'ok', false,
      'reason', format('That guild is full (%s members).', public.guild_max_members())
    );
  end if;
  if v_guild.join_policy <> 'open' then
    return jsonb_build_object('ok', false, 'reason', 'That guild takes applications.');
  end if;

  select * into v_facts from public.guild_member_facts(v_me);
  insert into public.guild_members (guild_id, user_id, role, username, appearance_json, total_level)
  values (p_guild_id, v_me, 'recruit', v_facts.username, v_facts.appearance_json, v_facts.total_level);
  delete from public.guild_applications where user_id = v_me and guild_id = p_guild_id;
  delete from public.guild_guests where user_id = v_me and guild_id = p_guild_id;
  update public.profiles set guild_id = p_guild_id, updated_at = now() where user_id = v_me;
  return jsonb_build_object('ok', true, 'joined', true);
end;
$$;

revoke all on function public.guild_join_open(uuid) from public, anon;
grant execute on function public.guild_join_open(uuid) to authenticated;

-- =============================================================================
-- Visit a guild that takes guests without asking
-- =============================================================================

create or replace function public.guild_join_guest(p_guild_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_guild public.guilds;
  v_guest_of uuid;
  v_facts record;
begin
  if v_me is null then
    return jsonb_build_object('ok', false, 'reason', 'Sign in to visit a guild.');
  end if;
  select * into v_guild from public.guilds where id = p_guild_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'Guild not found.');
  end if;
  if exists (select 1 from public.guild_members m where m.user_id = v_me and m.guild_id = p_guild_id) then
    return jsonb_build_object('ok', false, 'reason', 'Already a member of that guild.');
  end if;
  select g.guild_id into v_guest_of from public.guild_guests g where g.user_id = v_me;
  if v_guest_of is not null then
    return jsonb_build_object(
      'ok', false,
      'reason', case when v_guest_of = p_guild_id
        then 'Already a guest of that guild.'
        else 'Leave your current guest guild first.' end
    );
  end if;
  if not v_guild.guest_auto_accept then
    return jsonb_build_object('ok', false, 'reason', 'That guild asks guests to request a visit.');
  end if;

  select * into v_facts from public.guild_member_facts(v_me);
  insert into public.guild_guests (guild_id, user_id, username, appearance_json)
  values (p_guild_id, v_me, v_facts.username, v_facts.appearance_json);
  delete from public.guild_applications
   where user_id = v_me and guild_id = p_guild_id and guest;
  return jsonb_build_object('ok', true, 'joined', true);
end;
$$;

revoke all on function public.guild_join_guest(uuid) from public, anon;
grant execute on function public.guild_join_guest(uuid) to authenticated;

-- =============================================================================
-- Accept or decline an application
-- =============================================================================

create or replace function public.guild_decide_application(p_application_id uuid, p_accept boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_app public.guild_applications;
  v_guild public.guilds;
  v_role text;
  v_member_of uuid;
  v_facts record;
begin
  if v_me is null then
    return jsonb_build_object('ok', false, 'reason', 'Sign in first.');
  end if;
  select * into v_app from public.guild_applications where id = p_application_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'Application not found.');
  end if;
  select * into v_guild from public.guilds where id = v_app.guild_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'Guild not found.');
  end if;
  -- Re-read under the guild lock: another officer may have just decided it.
  perform 1 from public.guild_applications where id = p_application_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'Application not found.');
  end if;
  v_role := public.guild_role_of(v_guild.id, v_me);
  if v_guild.leader_id <> v_me and coalesce(v_role, '') not in ('leader', 'officer') then
    return jsonb_build_object(
      'ok', false,
      'reason', 'Only the guild leader or an officer can decide applications.'
    );
  end if;

  delete from public.guild_applications where id = p_application_id;
  if not p_accept then
    return jsonb_build_object('ok', true);
  end if;

  select m.guild_id into v_member_of from public.guild_members m where m.user_id = v_app.user_id;
  select * into v_facts from public.guild_member_facts(v_app.user_id, v_app.username);

  if v_app.guest then
    if exists (select 1 from public.guild_guests g where g.user_id = v_app.user_id) then
      return jsonb_build_object('ok', false, 'reason', 'Applicant is already a guest elsewhere.');
    end if;
    if v_member_of = v_guild.id then
      return jsonb_build_object('ok', false, 'reason', 'Applicant already joined that guild.');
    end if;
    insert into public.guild_guests (guild_id, user_id, username, appearance_json)
    values (v_guild.id, v_app.user_id, v_facts.username, v_facts.appearance_json);
    return jsonb_build_object('ok', true);
  end if;

  if v_member_of is not null then
    return jsonb_build_object('ok', false, 'reason', 'Applicant already joined another guild.');
  end if;
  if (select count(*) from public.guild_members m where m.guild_id = v_guild.id)
     >= public.guild_max_members() then
    return jsonb_build_object(
      'ok', false,
      'reason', format('Guild is full (%s members).', public.guild_max_members())
    );
  end if;
  insert into public.guild_members (guild_id, user_id, role, username, appearance_json, total_level)
  values (v_guild.id, v_app.user_id, 'recruit', v_facts.username, v_facts.appearance_json, v_facts.total_level);
  delete from public.guild_guests where guild_id = v_guild.id and user_id = v_app.user_id;
  update public.profiles set guild_id = v_guild.id, updated_at = now() where user_id = v_app.user_id;
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.guild_decide_application(uuid, boolean) from public, anon;
grant execute on function public.guild_decide_application(uuid, boolean) to authenticated;

-- =============================================================================
-- Leave, or disband as the last member
-- =============================================================================

create or replace function public.guild_leave()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_guild_id uuid;
  v_guild public.guilds;
begin
  if v_me is null then
    return jsonb_build_object('ok', false, 'reason', 'Sign in first.');
  end if;
  select m.guild_id into v_guild_id from public.guild_members m where m.user_id = v_me;
  if v_guild_id is null then
    return jsonb_build_object('ok', false, 'reason', 'Not in a guild.');
  end if;
  select * into v_guild from public.guilds where id = v_guild_id for update;

  if found and v_guild.leader_id = v_me then
    if (select count(*) from public.guild_members m where m.guild_id = v_guild_id) > 1 then
      return jsonb_build_object(
        'ok', false,
        'reason', 'Transfer leadership or remove members before leaving.'
      );
    end if;
    -- Roster, requests, guests, hall, and goals cascade; profiles set null.
    delete from public.guilds where id = v_guild_id;
  else
    delete from public.guild_members where user_id = v_me;
  end if;
  update public.profiles set guild_id = null, updated_at = now() where user_id = v_me;
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.guild_leave() from public, anon;
grant execute on function public.guild_leave() to authenticated;

-- =============================================================================
-- Remove a member
-- =============================================================================

create or replace function public.guild_kick(p_guild_id uuid, p_target uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_guild public.guilds;
begin
  if v_me is null then
    return jsonb_build_object('ok', false, 'reason', 'Sign in first.');
  end if;
  select * into v_guild from public.guilds where id = p_guild_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'Guild not found.');
  end if;
  if v_guild.leader_id <> v_me then
    return jsonb_build_object('ok', false, 'reason', 'Only the leader can remove members.');
  end if;
  if p_target = v_guild.leader_id then
    return jsonb_build_object('ok', false, 'reason', 'Cannot remove the leader.');
  end if;
  delete from public.guild_members where guild_id = p_guild_id and user_id = p_target;
  update public.profiles set guild_id = null, updated_at = now()
   where user_id = p_target and guild_id = p_guild_id;
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.guild_kick(uuid, uuid) from public, anon;
grant execute on function public.guild_kick(uuid, uuid) to authenticated;

-- =============================================================================
-- Direct inserts now go through the functions above
-- =============================================================================

drop policy if exists "guilds insert own" on public.guilds;
drop policy if exists "guild members insert" on public.guild_members;
drop policy if exists "guild guests insert" on public.guild_guests;

notify pgrst, 'reload schema';
