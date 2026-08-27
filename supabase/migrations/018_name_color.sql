alter table public.profiles
  add column if not exists name_color text;

comment on column public.profiles.name_color is
  'Published chat name hex (#RRGGBB). Written on a ranking submit.';
