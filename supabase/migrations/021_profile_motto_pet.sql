alter table public.profiles
  add column if not exists motto text;

alter table public.profiles
  add column if not exists pet_cosmetic_id text;

comment on column public.profiles.motto is
  'Published short motto under player art. Written on cloud save / ranking submit.';

comment on column public.profiles.pet_cosmetic_id is
  'Equipped pet cosmetic ID (CSLOT-0002). Written on cloud save / ranking submit.';
