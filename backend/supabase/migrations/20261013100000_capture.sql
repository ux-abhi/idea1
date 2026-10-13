-- Spend capture (2026-10-13): Apple Pay taps arrive from the owner's iPhone Shortcuts automation, receipts from the mail
-- worker. A capture token is a private link key for one device: the app makes it, shows it once, and stores only its
-- SHA-256 here, so the server never holds the token itself. The capture function finds the owner by that hash.

create table public.capture_token (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null default auth.uid() references auth.users on delete cascade,
  name          text not null default 'iPhone' check (length(trim(name)) between 1 and 60),
  token_hash    bytea not null unique check (length(token_hash) = 32),
  created_at    timestamptz not null default now(),
  last_used_at  timestamptz
);

alter table public.capture_token enable row level security;
-- The app adds, lists and removes its own; it never changes one (a lost token is removed and made again).
create policy owner_reads on public.capture_token for select to authenticated using (owner_id = (select auth.uid()));
create policy owner_adds on public.capture_token for insert to authenticated with check (owner_id = (select auth.uid()));
create policy owner_removes on public.capture_token for delete to authenticated using (owner_id = (select auth.uid()));
revoke update on public.capture_token from authenticated, anon;
create index on public.capture_token (owner_id);

-- Where a captured spend came from (the merchant as the payment named it), for the owner to check.
alter table public.transaction add column merchant text check (length(merchant) <= 200);
