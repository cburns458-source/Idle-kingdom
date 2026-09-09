alter table public.profiles
  add column if not exists username_renamed_at timestamptz null;

comment on column public.profiles.username_renamed_at is
  'When the public username last changed. Clients allow another rename after 7 days.';

create unique index if not exists profiles_username_lower_idx
  on public.profiles (lower(username));
