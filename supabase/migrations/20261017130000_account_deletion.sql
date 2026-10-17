-- ADM delete-account: 14-day grace, restore on login, scheduled purge.
--
-- Fixes FKs that block auth.users delete, keeps chat_reports (nulled) for a
-- year, and freezes trading/donations while a deletion is pending.

alter table public.profiles
  add column if not exists hidden_at timestamptz;

comment on column public.profiles.hidden_at is
  'Set while a 14-day deletion grace is pending. Public profile views omit the row.';

create table if not exists public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users (id) on delete set null,
  character_name text not null default '',
  requested_at timestamptz not null default now(),
  purge_after timestamptz not null,
  status text not null default 'pending',
  restored_at timestamptz,
  data_purged_at timestamptz,
  purged_at timestamptz,
  constraint account_deletion_status_check check (
    status in ('pending', 'restored', 'data_purged', 'purged')
  )
);

comment on table public.account_deletion_requests is
  'Grace-period deletion. user_id is nulled after auth.admin.deleteUser so the row remains.';

alter table public.account_deletion_requests enable row level security;

revoke all on table public.account_deletion_requests from public, anon, authenticated;
grant all on table public.account_deletion_requests to service_role;

create index if not exists account_deletion_requests_due_idx
  on public.account_deletion_requests (purge_after)
  where status = 'pending';

-- ---------------------------------------------------------------------------
-- Foreign keys that blocked or cascaded the wrong way
-- ---------------------------------------------------------------------------

alter table public.chat_reports
  add column if not exists retained_until timestamptz,
  add column if not exists reported_body text not null default '';

alter table public.chat_reports
  alter column reporter_id drop not null,
  alter column target_user_id drop not null;

alter table public.chat_reports drop constraint if exists chat_reports_reporter_id_fkey;
alter table public.chat_reports drop constraint if exists chat_reports_target_user_id_fkey;
alter table public.chat_reports
  add constraint chat_reports_reporter_id_fkey
    foreign key (reporter_id) references auth.users (id) on delete set null,
  add constraint chat_reports_target_user_id_fkey
    foreign key (target_user_id) references auth.users (id) on delete set null;

comment on column public.chat_reports.retained_until is
  'Nulled-user reports are kept until this instant, then the scheduled purge drops them.';

alter table public.developer_audit_log
  alter column user_id drop not null;

alter table public.developer_audit_log drop constraint if exists developer_audit_log_user_id_fkey;
alter table public.developer_audit_log
  add constraint developer_audit_log_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete set null;

-- guilds.leader_id stays NOT NULL; purge transfers or disbands first.
-- Re-assert the other listed FKs so hosted projects match the files.

alter table public.guilds drop constraint if exists guilds_leader_id_fkey;
alter table public.guilds
  add constraint guilds_leader_id_fkey
    foreign key (leader_id) references auth.users (id);

alter table public.guild_private_messages drop constraint if exists guild_private_messages_updated_by_fkey;
alter table public.guild_private_messages
  add constraint guild_private_messages_updated_by_fkey
    foreign key (updated_by) references auth.users (id) on delete set null;

alter table public.bazaar_fills drop constraint if exists bazaar_fills_buyer_id_fkey;
alter table public.bazaar_fills drop constraint if exists bazaar_fills_seller_id_fkey;
alter table public.bazaar_fills drop constraint if exists bazaar_fills_buy_order_id_fkey;
alter table public.bazaar_fills drop constraint if exists bazaar_fills_sell_order_id_fkey;
alter table public.bazaar_fills
  add constraint bazaar_fills_buyer_id_fkey
    foreign key (buyer_id) references auth.users (id) on delete set null,
  add constraint bazaar_fills_seller_id_fkey
    foreign key (seller_id) references auth.users (id) on delete set null,
  add constraint bazaar_fills_buy_order_id_fkey
    foreign key (buy_order_id) references public.bazaar_orders (id) on delete set null,
  add constraint bazaar_fills_sell_order_id_fkey
    foreign key (sell_order_id) references public.bazaar_orders (id) on delete set null;

alter table public.bazaar_collect drop constraint if exists bazaar_collect_order_id_fkey;
alter table public.bazaar_collect
  add constraint bazaar_collect_order_id_fkey
    foreign key (order_id) references public.bazaar_orders (id) on delete set null;

alter table public.profiles drop constraint if exists profiles_guild_id_fkey;
alter table public.profiles
  add constraint profiles_guild_id_fkey
    foreign key (guild_id) references public.guilds (id) on delete set null;

alter table public.player_feedback
  alter column user_id drop not null;

alter table public.player_feedback drop constraint if exists player_feedback_user_id_fkey;
alter table public.player_feedback
  add constraint player_feedback_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete set null;

-- ---------------------------------------------------------------------------
-- Hide pending-deletion accounts from public views
-- ---------------------------------------------------------------------------

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
from public.profiles p
where p.hidden_at is null;

grant select on public.public_profiles to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Freeze + status
-- ---------------------------------------------------------------------------

create or replace function public.account_is_frozen(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.account_deletion_requests r
     where r.user_id = p_user
       and r.status = 'pending'
  );
$$;

revoke all on function public.account_is_frozen(uuid) from public, anon;
grant execute on function public.account_is_frozen(uuid) to authenticated, service_role;

create or replace function public.account_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := (select auth.uid());
  v_answered boolean;
  v_pending boolean := false;
  v_purge_at timestamptz;
begin
  if v_me is null then
    return jsonb_build_object(
      'ok', false,
      'reason', 'Sign in first.',
      'age_answered', false,
      'chat_allowed', false,
      'deletion_pending', false
    );
  end if;
  v_answered := exists (select 1 from public.account_age a where a.user_id = v_me);
  select true, r.purge_after
    into v_pending, v_purge_at
  from public.account_deletion_requests r
  where r.user_id = v_me
    and r.status = 'pending'
  limit 1;
  return jsonb_build_object(
    'ok', true,
    'age_answered', v_answered,
    'chat_allowed', public.chat_allowed(v_me) and not coalesce(v_pending, false),
    'deletion_pending', coalesce(v_pending, false),
    'deletion_purge_at', v_purge_at
  );
end;
$$;

create or replace function public.bazaar_refuse_if_account_frozen()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if public.account_is_frozen(new.user_id) then
    raise exception 'This account is scheduled for deletion.'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists bazaar_orders_refuse_frozen on public.bazaar_orders;
create trigger bazaar_orders_refuse_frozen
  before insert on public.bazaar_orders
  for each row
  execute function public.bazaar_refuse_if_account_frozen();

-- ---------------------------------------------------------------------------
-- Request / restore / guild hand-off / purge
-- ---------------------------------------------------------------------------

create or replace function public.account_handoff_or_disband_guild(p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_guild public.guilds%rowtype;
  v_next uuid;
  v_members integer;
begin
  select * into v_guild from public.guilds g where g.leader_id = p_user;
  if not found then
    delete from public.guild_members m where m.user_id = p_user;
    delete from public.guild_guests g where g.user_id = p_user;
    delete from public.guild_applications a where a.user_id = p_user;
    return jsonb_build_object('ok', true, 'action', 'none');
  end if;

  select count(*) into v_members
  from public.guild_members m
  where m.guild_id = v_guild.id;

  if v_members <= 1 then
    delete from public.guilds g where g.id = v_guild.id;
    return jsonb_build_object('ok', true, 'action', 'disbanded', 'guild_id', v_guild.id);
  end if;

  select m.user_id into v_next
  from public.guild_members m
  where m.guild_id = v_guild.id
    and m.user_id <> p_user
  order by
    case m.role
      when 'officer' then 0
      when 'veteran' then 1
      when 'member' then 2
      else 3
    end,
    m.joined_at asc,
    m.user_id asc
  limit 1;

  if v_next is null then
    delete from public.guilds g where g.id = v_guild.id;
    return jsonb_build_object('ok', true, 'action', 'disbanded', 'guild_id', v_guild.id);
  end if;

  update public.guilds
     set leader_id = v_next
   where id = v_guild.id;

  update public.guild_members
     set role = 'leader'
   where guild_id = v_guild.id
     and user_id = v_next;

  delete from public.guild_members m where m.user_id = p_user;
  delete from public.guild_guests g where g.user_id = p_user;
  delete from public.guild_applications a where a.user_id = p_user;

  if to_regclass('public.guild_log_entries') is not null then
    insert into public.guild_log_entries (guild_id, kind, actor_user_id, actor_username, target_user_id, message)
    values (
      v_guild.id,
      'rank_change',
      v_next,
      'Deleted player',
      p_user,
      'Leadership passed from a deleted player.'
    );
  end if;

  return jsonb_build_object('ok', true, 'action', 'transferred', 'guild_id', v_guild.id, 'leader_id', v_next);
end;
$$;

revoke all on function public.account_handoff_or_disband_guild(uuid) from public, anon, authenticated;
grant execute on function public.account_handoff_or_disband_guild(uuid) to service_role;

create or replace function public.account_request_deletion(
  p_user uuid,
  p_character_name text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := btrim(coalesce(p_character_name, ''));
  v_username text;
  v_save_name text;
  v_order record;
  v_id uuid;
  v_purge timestamptz := timezone('utc', now()) + interval '14 days';
begin
  if p_user is null then
    return jsonb_build_object('ok', false, 'reason', 'Sign in first.');
  end if;
  if exists (select 1 from public.developer_accounts d where d.user_id = p_user) then
    return jsonb_build_object('ok', false, 'reason', 'Staff accounts cannot be deleted this way.');
  end if;
  if exists (
    select 1 from public.account_deletion_requests r
    where r.user_id = p_user and r.status = 'pending'
  ) then
    select r.id, r.purge_after into v_id, v_purge
    from public.account_deletion_requests r
    where r.user_id = p_user and r.status = 'pending'
    limit 1;
    return jsonb_build_object('ok', true, 'id', v_id, 'purge_after', v_purge, 'already', true);
  end if;

  select p.username into v_username from public.profiles p where p.user_id = p_user;
  select s.payload ->> 'characterName' into v_save_name
  from public.player_saves s
  where s.user_id = p_user;

  if v_name = ''
     or (
       lower(v_name) is distinct from lower(coalesce(v_username, ''))
       and lower(v_name) is distinct from lower(coalesce(v_save_name, ''))
     )
  then
    return jsonb_build_object('ok', false, 'reason', 'Type your character name to confirm.');
  end if;

  insert into public.account_deletion_requests (user_id, character_name, purge_after)
  values (p_user, v_name, v_purge)
  returning id into v_id;

  update public.profiles
     set hidden_at = now()
   where user_id = p_user;

  delete from public.activity_presence where user_id = p_user;

  for v_order in
    select o.id from public.bazaar_orders o
    where o.user_id = p_user and o.status = 'open'
  loop
    perform public.bazaar_cancel_order(p_user, v_order.id);
  end loop;

  return jsonb_build_object('ok', true, 'id', v_id, 'purge_after', v_purge);
end;
$$;

revoke all on function public.account_request_deletion(uuid, text) from public, anon, authenticated;
grant execute on function public.account_request_deletion(uuid, text) to service_role;

create or replace function public.account_restore(p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_user is null then
    return jsonb_build_object('ok', false, 'reason', 'Sign in first.');
  end if;
  if not exists (
    select 1 from public.account_deletion_requests r
    where r.user_id = p_user and r.status = 'pending'
  ) then
    return jsonb_build_object('ok', false, 'reason', 'This account is not waiting to be deleted.');
  end if;
  if exists (
    select 1 from public.account_deletion_requests r
    where r.user_id = p_user
      and r.status = 'pending'
      and r.purge_after <= timezone('utc', now())
  ) then
    return jsonb_build_object('ok', false, 'reason', 'This account is being deleted.');
  end if;

  update public.account_deletion_requests
     set status = 'restored',
         restored_at = now()
   where user_id = p_user
     and status = 'pending';

  update public.profiles
     set hidden_at = null
   where user_id = p_user;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.account_restore(uuid) from public, anon, authenticated;
grant execute on function public.account_restore(uuid) to service_role;

create or replace function public.account_purge_data(p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_feedback jsonb := '[]'::jsonb;
  v_order record;
begin
  if p_user is null then
    return jsonb_build_object('ok', true, 'already', true);
  end if;

  perform public.account_handoff_or_disband_guild(p_user);

  for v_order in
    select o.id from public.bazaar_orders o
    where o.user_id = p_user and o.status = 'open'
  loop
    perform public.bazaar_cancel_order(p_user, v_order.id);
  end loop;

  delete from public.chat_messages where user_id = p_user;

  update public.chat_reports
     set reporter_id = case when reporter_id = p_user then null else reporter_id end,
         target_user_id = case when target_user_id = p_user then null else target_user_id end,
         retained_until = coalesce(retained_until, timezone('utc', now()) + interval '1 year')
   where reporter_id = p_user or target_user_id = p_user;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', f.id,
        'discord_message_id', f.discord_message_id,
        'discord_thread_id', f.discord_thread_id
      )
    ),
    '[]'::jsonb
  )
    into v_feedback
  from public.player_feedback f
  where f.user_id = p_user
    and f.discord_message_id is not null;

  update public.player_feedback
     set user_id = null,
         username = 'Deleted player',
         context = coalesce(context, '{}'::jsonb) || jsonb_build_object('anonymised', true)
   where user_id = p_user;

  delete from public.leaderboard_snapshots where user_id = p_user;
  delete from public.activity_presence where user_id = p_user;
  delete from public.friend_requests
   where from_user_id = p_user or to_user_id = p_user;
  delete from public.friendships
   where user_a = p_user or user_b = p_user;
  delete from public.player_blocks
   where user_id = p_user or blocked_user_id = p_user;
  delete from public.player_mutes
   where user_id = p_user or muted_user_id = p_user;

  if to_regclass('public.ranked_pvp_results') is not null then
    delete from public.ranked_pvp_results where user_id = p_user;
    update public.ranked_pvp_results set opponent_id = null where opponent_id = p_user;
  end if;
  if to_regclass('public.mass_participants') is not null then
    delete from public.mass_participants where user_id = p_user;
  end if;
  if to_regclass('public.guild_log_entries') is not null then
    update public.guild_log_entries
       set actor_user_id = null
     where actor_user_id = p_user;
    update public.guild_log_entries
       set target_user_id = null
     where target_user_id = p_user;
  end if;

  update public.account_deletion_requests
     set status = 'data_purged',
         data_purged_at = now()
   where user_id = p_user
     and status in ('pending', 'data_purged');

  return jsonb_build_object('ok', true, 'feedback', v_feedback);
end;
$$;

revoke all on function public.account_purge_data(uuid) from public, anon, authenticated;
grant execute on function public.account_purge_data(uuid) to service_role;

create or replace function public.account_list_due_purges(p_limit integer default 20)
returns table (
  request_id uuid,
  user_id uuid,
  status text,
  data_purged boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    r.id,
    r.user_id,
    r.status,
    r.data_purged_at is not null
  from public.account_deletion_requests r
  where r.status in ('pending', 'data_purged')
    and r.user_id is not null
    and (r.status = 'data_purged' or r.purge_after <= timezone('utc', now()))
  order by r.purge_after asc
  limit greatest(1, least(coalesce(p_limit, 20), 50));
$$;

revoke all on function public.account_list_due_purges(integer) from public, anon, authenticated;
grant execute on function public.account_list_due_purges(integer) to service_role;

create or replace function public.account_mark_purged(p_request uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.account_deletion_requests
     set status = 'purged',
         purged_at = now(),
         user_id = null
   where id = p_request;
$$;

revoke all on function public.account_mark_purged(uuid) from public, anon, authenticated;
grant execute on function public.account_mark_purged(uuid) to service_role;

create or replace function public.account_drop_expired_reports()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from public.chat_reports
   where retained_until is not null
     and retained_until <= timezone('utc', now())
     and reporter_id is null
     and target_user_id is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.account_drop_expired_reports() from public, anon, authenticated;
grant execute on function public.account_drop_expired_reports() to service_role;

-- Keep the reported text even after the users are nulled.
create or replace function public.report_player(p_target uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_reason text := btrim(coalesce(p_reason, ''));
  v_recent int;
  v_body text := '';
begin
  if v_me is null then
    raise exception 'Sign in first.';
  end if;
  if p_target is null or p_target = v_me then
    return jsonb_build_object('ok', false, 'reason', 'You cannot report yourself.');
  end if;
  if not exists (select 1 from public.profiles where user_id = p_target) then
    return jsonb_build_object('ok', false, 'reason', 'That player was not found.');
  end if;
  if v_reason in ('Spam', 'Harassment', 'Inappropriate name', 'Other') then
    null;
  elsif left(v_reason, 6) = 'Other:' and char_length(v_reason) <= 280 then
    null;
  else
    return jsonb_build_object('ok', false, 'reason', 'Choose a reason.');
  end if;

  select count(*)
    into v_recent
    from public.chat_reports
   where reporter_id = v_me
     and created_at > now() - interval '1 day';
  if v_recent >= 10 then
    return jsonb_build_object('ok', false, 'reason', 'You have sent enough reports today.');
  end if;

  select left(m.body, 500) into v_body
    from public.chat_messages m
   where m.user_id = p_target
   order by m.created_at desc
   limit 1;

  insert into public.chat_reports (
    reporter_id, target_user_id, reason, reported_body, retained_until
  )
  values (
    v_me,
    p_target,
    v_reason,
    coalesce(v_body, ''),
    timezone('utc', now()) + interval '1 year'
  );
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.report_player(uuid, text) from public, anon;
grant execute on function public.report_player(uuid, text) to authenticated, service_role;

notify pgrst, 'reload schema';
