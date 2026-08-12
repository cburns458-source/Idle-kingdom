-- Guild tab v2: tags, join policy, structured emblem, expanded ranks.

alter table public.guilds
  add column if not exists tag text,
  add column if not exists join_policy text not null default 'open',
  add column if not exists rank_labels jsonb not null default '{"leader":"Leader","officer":"Officer","veteran":"Veteran","member":"Member","recruit":"Recruit"}'::jsonb;

update public.guilds
set tag = upper(substr(regexp_replace(name, '[^a-zA-Z]', '', 'g'), 1, 4))
where tag is null or length(tag) < 2;

alter table public.guilds
  alter column tag set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'guilds_tag_unique'
  ) then
    alter table public.guilds add constraint guilds_tag_unique unique (tag);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'guilds_join_policy_check'
  ) then
    alter table public.guilds
      add constraint guilds_join_policy_check
      check (join_policy in ('open', 'closed'));
  end if;
end $$;

-- emblem was text; store JSON string {"color":"...","symbol":"..."} going forward.
update public.guilds
set emblem = json_build_object('color', '#5c4027', 'symbol', coalesce(nullif(emblem, ''), '⚔️'))::text
where emblem not like '{%';

alter table public.guild_members
  drop constraint if exists guild_members_role_check;

alter table public.guild_members
  add constraint guild_members_role_check
  check (role in ('leader', 'officer', 'veteran', 'member', 'recruit'));
