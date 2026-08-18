-- Chat lines carry the speaker's guild tag and rank at send time, so global
-- and local rooms can print [TAG] Name and guild rooms can print the rank mark
-- without a second lookup. Guests of a guild are allowed to speak there.

alter table public.chat_messages
  add column if not exists guild_tag text,
  add column if not exists rank_label text,
  add column if not exists rank_icon text,
  add column if not exists guest boolean not null default false;

comment on column public.chat_messages.guild_tag is
  'Member guild tag at send time, shown as [TAG] in global and local rooms.';
comment on column public.chat_messages.rank_label is
  'Guild rank name at send time, shown only in that guild''s room.';
comment on column public.chat_messages.rank_icon is
  'Guild rank mark at send time, shown only in that guild''s room.';
comment on column public.chat_messages.guest is
  'True when the speaker was a guest of the guild room, not a member.';
