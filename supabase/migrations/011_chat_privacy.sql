alter table public.profiles
  add column if not exists privacy_direct_messages text not null default 'public';

alter table public.profiles
  add column if not exists privacy_local_chat text not null default 'public';

comment on column public.profiles.privacy_direct_messages is
  'Who may send this account a private message: public, friends, or off.';

comment on column public.profiles.privacy_local_chat is
  'Who may see this account in local chat: public, friends, or off.';
