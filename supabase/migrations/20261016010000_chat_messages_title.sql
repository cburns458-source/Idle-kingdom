-- Chat lines carry the speaker's equipped title at send time so listing can
-- print it without a second lookup. Null when none is equipped. send-chat
-- writes this from the hosted save; a client-supplied title is ignored.

alter table public.chat_messages
  add column if not exists title text;

comment on column public.chat_messages.title is
  'Equipped title text at send time, derived from the sender''s hosted save. Null when none.';
