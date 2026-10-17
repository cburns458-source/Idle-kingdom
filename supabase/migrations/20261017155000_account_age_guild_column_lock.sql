-- Lock guild motto and application message columns from under-13 readers.
-- TEST only; never apply to live from this PR.
--
-- 1. Refuse description writes when the caller is not chat_allowed.
--    Service-role / purge (auth.uid() is null) still work.
-- 2. Hosted create stores an empty motto, or refuses a non-empty one,
--    when the founder is not chat_allowed.
-- 3. Revoke column SELECT on guilds.description and
--    guild_applications.message from anon/authenticated. Serve those
--    fields through security-definer views that blank them when
--    chat_allowed(auth.uid()) is false.

create or replace function public.guilds_description_requires_chat()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.description is not distinct from old.description then
      return new;
    end if;
    -- Service-role and purge have no JWT user.
    if auth.uid() is null then
      return new;
    end if;
    if public.chat_allowed(auth.uid()) then
      return new;
    end if;
    raise exception 'Chat is not available for this account.'
      using errcode = '42501';
  end if;

  -- INSERT: empty motto is allowed without chat; a non-empty one is not.
  if auth.uid() is null then
    return new;
  end if;
  if public.chat_allowed(auth.uid())
     or btrim(coalesce(new.description, '')) = '' then
    return new;
  end if;
  raise exception 'Chat is not available for this account.'
    using errcode = '42501';
end;
$$;

drop trigger if exists guilds_description_requires_chat on public.guilds;
create trigger guilds_description_requires_chat
  before insert or update of description on public.guilds
  for each row
  execute function public.guilds_description_requires_chat();

comment on function public.guilds_description_requires_chat() is
  'Refuses guilds.description writes when the signed-in caller is not chat_allowed. Service-role and purge (no JWT) still pass.';

revoke all on function public.guilds_description_requires_chat() from public, anon, authenticated;

-- =============================================================================
-- Hosted create: empty motto, or refuse a non-empty one, when founder is
-- not chat_allowed. Check is on p_user_id — this RPC is service-role only.
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
  v_description text := left(btrim(coalesce(p_guild ->> 'description', '')), 500);
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
  if not public.chat_allowed(p_user_id) then
    if v_description <> '' then
      return jsonb_build_object(
        'ok', false,
        'reason', 'Chat is not available for this account.',
        'code', 'age_gate'
      );
    end if;
    v_description := '';
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
      v_description,
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
-- Column lock + security-definer views
-- =============================================================================

-- Table-level SELECT covers every column; a column REVOKE does not punch
-- through it. Replace the table grant with an explicit column list.
revoke select on public.guilds from anon, authenticated;
grant select (
  id, name, tag, emblem, leader_id, created_at, join_policy,
  rank_labels, rank_icon_theme, guest_auto_accept,
  skill_milestone_settings, permissions, banner
) on public.guilds to anon, authenticated;

revoke select on public.guild_applications from anon, authenticated;
grant select (
  id, guild_id, user_id, username, created_at, guest
) on public.guild_applications to anon, authenticated;

drop view if exists public.guilds_visible;
create view public.guilds_visible
with (security_invoker = false)
as
select
  g.id,
  g.name,
  g.tag,
  case
    when public.chat_allowed(auth.uid()) then g.description
    else ''::text
  end as description,
  g.emblem,
  g.leader_id,
  g.join_policy,
  g.rank_labels,
  g.rank_icon_theme,
  g.guest_auto_accept,
  g.created_at,
  g.skill_milestone_settings,
  g.permissions,
  g.banner
from public.guilds g;

comment on view public.guilds_visible is
  'Guild rows for signed-in clients. description is blank when the reader is not chat_allowed.';

grant select on public.guilds_visible to authenticated, service_role;

drop view if exists public.guild_applications_visible;
create view public.guild_applications_visible
with (security_invoker = false)
as
select
  a.id,
  a.guild_id,
  a.user_id,
  a.username,
  case
    when public.chat_allowed(auth.uid()) then a.message
    else ''::text
  end as message,
  a.created_at,
  a.guest
from public.guild_applications a
where (select auth.uid()) = a.user_id
   or public.is_guild_manager(a.guild_id);

comment on view public.guild_applications_visible is
  'Applications the caller may see (own row or guild manager). message is blank when the reader is not chat_allowed.';

grant select on public.guild_applications_visible to authenticated, service_role;

notify pgrst, 'reload schema';
