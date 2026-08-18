-- Total Level and Total XP are one board now, so a row carries two numbers:
-- value is the level it ranks by, value_secondary the experience shown under it.
-- Rows written before this migration read back as zero experience until the
-- client submits its next ranking update.

alter table public.leaderboard_snapshots
  add column if not exists value_secondary numeric not null default 0;

comment on column public.leaderboard_snapshots.value_secondary is
  'The second number a combined board shows, and the tie-break on value. Zero on single-value boards.';

-- The pacifist board writes a zero for anyone who has raised Combat, which the
-- client reads as "not on this board". Nothing to create: it is another
-- board_key in the same table.
delete from public.leaderboard_snapshots where board_key = 'total_experience';
