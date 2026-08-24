alter table public.profiles
  add column if not exists privacy_public_gear boolean not null default true;

alter table public.profiles
  add column if not exists equipment_json jsonb not null default '[]'::jsonb;

comment on column public.profiles.privacy_public_gear is
  'When true, other players may open this account''s equipped gear from the profile.';

comment on column public.profiles.equipment_json is
  'Published equipped slots for public profiles. Cloud saves stay self-only.';
