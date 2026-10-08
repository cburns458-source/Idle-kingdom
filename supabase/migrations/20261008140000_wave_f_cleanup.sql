-- Wave F: archive the retired Citadel message board and drop the unused
-- skills-privacy flag. Skills stay public. The live table still holds a
-- handful of posts; do not drop it.

alter table public.bazaar_posts rename to bazaar_posts_archive;

alter index if exists bazaar_posts_created_idx
  rename to bazaar_posts_archive_created_idx;
alter index if exists bazaar_posts_pkey
  rename to bazaar_posts_archive_pkey;

alter table public.bazaar_posts_archive
  rename constraint bazaar_posts_kind_check to bazaar_posts_archive_kind_check;
alter table public.bazaar_posts_archive
  rename constraint bazaar_posts_user_id_fkey to bazaar_posts_archive_user_id_fkey;

drop trigger if exists trim_bazaar_posts_trigger on public.bazaar_posts_archive;
drop function if exists public.trim_bazaar_posts();

revoke all on table public.bazaar_posts_archive from anon, authenticated, service_role;
grant select on table public.bazaar_posts_archive to service_role;

comment on table public.bazaar_posts_archive is
  'Retired Citadel message board. Read-only for service_role.';

alter table public.profiles drop column if exists privacy_public_skills;

notify pgrst, 'reload schema';
