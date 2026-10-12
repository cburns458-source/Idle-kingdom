-- Developer allowlist and audit log for privileged chat commands.
--
-- Tables are service_role only. Clients discover developer status through
-- is_developer(), which only answers for the signed-in JWT subject.

create table if not exists public.developer_accounts (
  user_id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  note text not null default ''
);

comment on table public.developer_accounts is
  'Allowlisted auth user ids for self-only developer game commands.';

alter table public.developer_accounts enable row level security;

revoke all on table public.developer_accounts from anon, authenticated;
grant all on table public.developer_accounts to service_role;

create table if not exists public.developer_audit_log (
  id bigserial primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  command text not null,
  args jsonb not null default '{}'::jsonb,
  ok boolean not null,
  reason text not null default '',
  created_at timestamptz not null default now()
);

comment on table public.developer_audit_log is
  'Outcome of each developer command attempt, including refusals.';

alter table public.developer_audit_log enable row level security;

revoke all on table public.developer_audit_log from anon, authenticated;
grant all on table public.developer_audit_log to service_role;

create index if not exists developer_audit_log_user_created_idx
  on public.developer_audit_log (user_id, created_at desc);

create or replace function public.is_developer()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.developer_accounts d
    where d.user_id = (select auth.uid())
  );
$$;

revoke all on function public.is_developer() from public, anon;
grant execute on function public.is_developer() to authenticated, service_role;

notify pgrst, 'reload schema';
