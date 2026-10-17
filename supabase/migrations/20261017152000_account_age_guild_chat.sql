-- Year-only birthdays count as 31 December. Under-13s cannot write a guild
-- motto or a guild application message (empty apply/guest requests still work).

create or replace function public.account_age_years(
  p_birth_year integer,
  p_birth_month integer,
  p_as_of date default (timezone('utc', now()))::date
)
returns integer
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_month integer;
  v_day integer;
  v_birthday date;
begin
  if p_birth_year is null then
    return null;
  end if;
  -- Missing month: treat as 31 Dec so a year-only answer cannot unlock chat
  -- before we know they have turned 13.
  v_month := coalesce(p_birth_month, 12);
  v_day := case when p_birth_month is null then 31 else 1 end;
  begin
    v_birthday := make_date(p_birth_year, v_month, v_day);
  exception
    when others then
      v_birthday := make_date(p_birth_year, 12, 31);
  end;
  return (extract(year from age(p_as_of, v_birthday)))::integer;
end;
$$;

create or replace function public.guild_set_motto(p_guild uuid, p_motto text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_clean text := left(btrim(coalesce(p_motto, '')), 160);
begin
  if v_me is null then
    return jsonb_build_object('ok', false, 'reason', 'Sign in first.');
  end if;
  if not public.chat_allowed(v_me) then
    return jsonb_build_object(
      'ok', false,
      'reason', 'Chat is not available for this account.',
      'code', 'age_gate'
    );
  end if;
  if p_guild is null then
    return jsonb_build_object('ok', false, 'reason', 'Missing guild.');
  end if;
  if not coalesce(public.is_guild_manager(p_guild), false) then
    return jsonb_build_object('ok', false, 'reason', 'Only the guild leader or an officer can edit the motto.');
  end if;
  update public.guilds
  set description = v_clean
  where id = p_guild;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'That guild could not be found.');
  end if;
  return jsonb_build_object('ok', true, 'motto', v_clean);
end;
$$;

revoke all on function public.guild_set_motto(uuid, text) from public, anon;
grant execute on function public.guild_set_motto(uuid, text) to authenticated, service_role;

drop policy if exists "guild applications insert self" on public.guild_applications;
create policy "guild applications insert self"
  on public.guild_applications
  for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and (
      public.chat_allowed((select auth.uid()))
      or btrim(coalesce(message, '')) = ''
    )
  );

notify pgrst, 'reload schema';
