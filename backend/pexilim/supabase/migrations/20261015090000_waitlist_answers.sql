-- Five quick questions for people on the waitlist (2026-10-15), all optional: what slips through the cracks in their day,
-- what they use today, the Blink feature they'd use first, what they'd pay, and whether they'd beta test. Answered on the
-- site (survey.html) with the code from their confirm link; only the waitlist function (service role) reads or writes.
-- Leaving the waitlist deletes the answers too.
create table public.waitlist_answer (
  waitlist_id    uuid primary key references public.waitlist on delete cascade,
  slips          text[] not null default '{}',
  uses           text[] not null default '{}',
  first_feature  text,
  pay            text,
  beta           text check (beta in ('yes', 'maybe')),
  notch          boolean,
  note           text check (length(note) <= 1000),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
alter table public.waitlist_answer enable row level security;   -- no policies: the public keys can't read or write
revoke all on public.waitlist_answer from anon, authenticated;

-- The one email asking for answers: sent once, a few days after someone confirms, only if they haven't answered.
alter table public.waitlist add column followup_at timestamptz;
