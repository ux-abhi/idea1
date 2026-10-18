-- When the confirm email was last sent again (2026-10-18): someone whose first email never arrived can join again and
-- get the links once more, at most once an hour.
alter table public.waitlist add column mailed_at timestamptz;
