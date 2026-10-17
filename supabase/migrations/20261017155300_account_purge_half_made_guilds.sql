-- Narrow hourly purge of half-made guilds (Vari approved).
-- TEST only; never apply to live from this PR.
--
-- Deletes a guild only when every one of these is true:
--   * no guild_members rows now
--   * never a leader row (no join/leave/rank_change log with role = 'leader')
--   * no guild_halls row
--   * no guild_achievements row
--   * created_at older than 1 hour
--
-- Do not use guilds.leader_id — create always writes that column, even when
-- the founder-as-leader insert later failed.

create or replace function public.account_purge_half_made_guilds()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from public.guilds g
   where g.created_at < timezone('utc', now()) - interval '1 hour'
     and not exists (
       select 1 from public.guild_members m where m.guild_id = g.id
     )
     and not exists (
       select 1
         from public.guild_log_entries e
        where e.guild_id = g.id
          and e.kind in ('join', 'leave', 'rank_change')
          and e.role = 'leader'
     )
     and not exists (
       select 1 from public.guild_halls h where h.guild_id = g.id
     )
     and not exists (
       select 1 from public.guild_achievements a where a.guild_id = g.id
     );
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

comment on function public.account_purge_half_made_guilds() is
  'Hourly cleanup. Deletes only half-made guilds: no members now, never a leader row, no hall, no achievements, older than 1 hour. Never uses guilds.leader_id.';

revoke all on function public.account_purge_half_made_guilds() from public, anon, authenticated;
grant execute on function public.account_purge_half_made_guilds() to postgres, service_role;

create or replace function public.account_purge_cron_tick()
returns void
language plpgsql
security definer
set search_path = public, vault, net, extensions
as $$
declare
  v_secret text;
  v_url text;
begin
  perform public.account_purge_half_made_guilds();

  select ds.decrypted_secret
    into v_secret
  from vault.decrypted_secrets ds
  where ds.name = 'purge_cron_secret'
  limit 1;

  select ds.decrypted_secret
    into v_url
  from vault.decrypted_secrets ds
  where ds.name = 'purge_cron_url'
  limit 1;

  if v_secret is null or length(btrim(v_secret)) = 0 then
    raise warning 'account_purge_cron_tick: vault secret purge_cron_secret is missing';
    return;
  end if;
  if v_url is null or length(btrim(v_url)) = 0 then
    raise warning 'account_purge_cron_tick: vault secret purge_cron_url is missing';
    return;
  end if;

  perform net.http_post(
    url := btrim(v_url),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-purge-secret', v_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
end;
$$;

comment on function public.account_purge_cron_tick() is
  'Hourly pg_cron tick. Purges half-made guilds, then POSTs purge-accounts using Vault secrets purge_cron_secret and purge_cron_url.';
