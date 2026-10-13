-- Mail sorted later (2026-10-14): when the AI is down, a batch is stored unsorted; the next check fetches those messages
-- again and sorts them. Existing rows count as sorted.
alter table public.email_msg add column sorted boolean not null default true;
create index on public.email_msg (owner_id, account, created_at) where not sorted;
