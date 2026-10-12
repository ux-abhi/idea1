-- Run once on a new server, after the migrations (needs pg_cron, already enabled by mail_schedule.sql).
-- Every night at 03:30 UTC: remove rows past their retention (migrations/20261012150000_retention.sql),
-- and the scheduler's own run log older than 7 days.
select cron.schedule('blink-cleanup', '30 3 * * *', $$
  select public.remove_old_rows();
  delete from cron.job_run_details where end_time < now() - interval '7 days';
$$);
