-- Hall donate / pay debt now debit the hosted save in the game function.
-- The old RPCs only credited the ledger.
revoke all on function public.guild_pay_hall_debt(numeric) from public, anon, authenticated;
revoke all on function public.guild_donate_hall_item(text, numeric) from public, anon, authenticated;
