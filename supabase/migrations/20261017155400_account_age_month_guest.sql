-- Guest requests are chat-only. Under-13 and frozen accounts cannot send
-- one, and an officer cannot accept one if the requester is gated now.
-- TEST only; never apply to live from this PR.
--
-- Regular apply with an empty message still works. Mottos and application
-- messages stay hidden from under-13s. Guild leadership still hands off
-- only when the 14-day purge runs.

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
  if not public.chat_allowed(v_me) then
    return jsonb_build_object(
      'ok', false,
      'reason', 'Chat is not available for this account.',
      'code', 'age_gate'
    );
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

  if p_accept and v_app.guest and not public.chat_allowed(v_app.user_id) then
    return jsonb_build_object(
      'ok', false,
      'reason', 'Chat is not available for this account.',
      'code', 'age_gate'
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

drop policy if exists "guild applications insert self" on public.guild_applications;
create policy "guild applications insert self"
  on public.guild_applications
  for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and (
      public.chat_allowed((select auth.uid()))
      or (
        guest is not true
        and btrim(coalesce(message, '')) = ''
      )
    )
  );

notify pgrst, 'reload schema';
