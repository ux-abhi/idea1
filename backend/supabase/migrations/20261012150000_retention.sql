-- Keep the server light (owner, 2026-10-12): rows that only matter for a while are removed by a daily job
-- (setup/cleanup_schedule.sql). Notes, tasks, habits, spends, accounts, budgets, posts and drafts are never touched.
--   · mail summaries: handled or newsletters after 30 days, everything else after 90 (the mail stays in the mailbox)
--   · finished Ask-First cards (Activity): after 180 days; pending and approved (e.g. a scheduled send) never
--   · app events: after 30 days
--   · AI usage rows: after 400 days (the spend cap only reads the last 24 hours; Settings shows recent usage)
create or replace function public.remove_old_rows() returns jsonb
language plpgsql set search_path = '' as $$
declare mail int; actions int; events int; usage int;
begin
  delete from public.email_msg
   where (status = 'done' or triage = 'newsletter') and created_at < now() - interval '30 days'
      or created_at < now() - interval '90 days';
  get diagnostics mail = row_count;
  delete from public.action where status in ('done', 'undone', 'expired', 'declined', 'failed') and created_at < now() - interval '180 days';
  get diagnostics actions = row_count;
  delete from public.blink_event where at < now() - interval '30 days';
  get diagnostics events = row_count;
  delete from public.model_usage where at < now() - interval '400 days';
  get diagnostics usage = row_count;
  return jsonb_build_object('mail', mail, 'actions', actions, 'events', events, 'usage', usage);
end $$;

-- Maintenance only: the nightly job runs it as the database owner; a signed-in app can never call it.
revoke all on function public.remove_old_rows() from public, anon, authenticated;
