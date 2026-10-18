-- Next steps found in a mail (2026-10-18): up to 3 suggestions like "Interview Thu 15:00" or "Pay rent by the 20th" that
-- the owner can turn into a calendar event, reminder, task or note with one tap. Written only by the mail worker (the app
-- can't change them), short and checked there; the mail text itself is still never stored.
alter table public.email_msg add column actions jsonb not null default '[]'
  check (jsonb_typeof(actions) = 'array' and jsonb_array_length(actions) <= 3);
