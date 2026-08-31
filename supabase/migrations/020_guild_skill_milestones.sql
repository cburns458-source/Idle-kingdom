-- Guild skill milestone chat settings.
-- Existing guilds get the Launch defaults: levels 50/10, XP 125m/25m after 100.

alter table public.guilds
  add column if not exists skill_milestone_settings jsonb not null
    default '{"enabled":true,"levelStart":50,"levelStep":10,"xpStartMillion":125,"xpStepMillion":25}'::jsonb;

comment on column public.guilds.skill_milestone_settings is
  'Leader-tunable thresholds for guild chat skill milestone announcements.';

update public.guilds
set skill_milestone_settings =
  '{"enabled":true,"levelStart":50,"levelStep":10,"xpStartMillion":125,"xpStepMillion":25}'::jsonb
where skill_milestone_settings is null
   or skill_milestone_settings = '{}'::jsonb;
