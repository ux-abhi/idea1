-- When someone pressed Send on the survey: the site then thanks a beta "yes" and tells the owner, once (2026-10-15).
alter table public.waitlist_answer add column finished_at timestamptz;
