-- Hourly purge-accounts via pg_cron + pg_net. The shared secret stays in
-- Vault (never the repo). The job no-ops until Conor creates the Vault
-- entries documented in docs/deployment.md.

create extension if not exists pg_net;
create extension if not exists pg_cron with schema pg_catalog;

grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

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
  'Hourly pg_cron tick. POSTs purge-accounts using Vault secrets purge_cron_secret and purge_cron_url.';

revoke all on function public.account_purge_cron_tick() from public, anon, authenticated;
grant execute on function public.account_purge_cron_tick() to postgres;

select cron.unschedule(jobid)
  from cron.job
 where jobname = 'purge-accounts-hourly';

select cron.schedule(
  'purge-accounts-hourly',
  '0 * * * *',
  $$select public.account_purge_cron_tick()$$
);
