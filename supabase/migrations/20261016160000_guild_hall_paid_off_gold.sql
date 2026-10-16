-- 20261016120000 copied paid gold from debt_remaining only. Halls with
-- debt_paid_off = true and null debt_remaining were skipped (coalesce treated
-- remaining as 1M) and stayed at gold_contributed = 0. Set those rows to the
-- 1M running total, the gold mark for room tier 5. Safe to re-run.

update public.guild_halls
   set gold_contributed = 1000000,
       gold_contributed_by = case
         when coalesce(gold_contributed_by, '{}'::jsonb) = '{}'::jsonb
         then coalesce(debt_paid_by, '{}'::jsonb)
         else gold_contributed_by
       end,
       debt_remaining = 0
 where debt_paid_off is true
   and gold_contributed < 1000000;
