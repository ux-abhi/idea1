-- Double opt-in (2026-10-13): a signup counts once the person clicks the link in the confirmation email. Unconfirmed
-- rows older than 30 days are removed by the function's own clean-up, so mistyped or fake addresses don't stay.
alter table public.waitlist add column confirm_token uuid not null default gen_random_uuid() unique;
alter table public.waitlist add column confirmed_at timestamptz;
