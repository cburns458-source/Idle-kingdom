-- Motto, name color, and pet cosmetic are added by 018 / 021. A project that
-- applied those files without reloading PostgREST still answers as if the
-- columns do not exist, so ranking publishes while other accounts see a blank
-- motto and an uncolored chat name. Re-add the columns (no-op when present)
-- and refresh the schema cache.

alter table public.profiles
  add column if not exists name_color text;

alter table public.profiles
  add column if not exists motto text;

alter table public.profiles
  add column if not exists pet_cosmetic_id text;

notify pgrst, 'reload schema';
