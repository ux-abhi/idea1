-- The Blink waitlist (2026-10-13). Only the waitlist function writes here (service role); no app or visitor reads it.
-- Stored: the email, when they joined and agreed, and where from. Kept until launch plus 12 months or until removed.

create table public.waitlist (
  id           uuid primary key default gen_random_uuid(),
  email        text not null check (length(email) between 3 and 254 and email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  source       text not null default 'site' check (length(source) <= 40),
  consent_at   timestamptz not null default now(),   -- they ticked "Email me when Blink is ready"
  unsubscribe  uuid not null default gen_random_uuid() unique, -- for the link in every email we send
  created_at   timestamptz not null default now(),
  unique (email)
);

-- Row-level security on, with no policies: the public keys can't read or write; only the function's service role can.
alter table public.waitlist enable row level security;
revoke all on public.waitlist from anon, authenticated;
create index on public.waitlist (created_at);
