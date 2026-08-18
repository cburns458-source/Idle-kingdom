-- Rank names stay on the guild; chat only needs the rank mark.

alter table public.chat_messages
  drop column if exists rank_label;
