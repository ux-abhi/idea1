-- Fixed monthly bills (2026-11-02): rent, phone, subscriptions, loans: the same amount on the same day every month.
-- On or after that day the app adds the month's spend itself (source 'bill', dedupe_key 'bill:<id>:<YYYY-MM>', so two
-- Macs never add it twice) and moves added_through on, so a bill spend the owner deletes is not added again.

create table public.fixed_bill (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null default auth.uid() references auth.users on delete cascade,
  note           text not null check (length(trim(note)) between 1 and 300),
  amount         numeric(12, 2) not null check (amount > 0 and amount < 1000000),
  category       text not null default 'bills' check (category in
                   ('food', 'groceries', 'transport', 'housing', 'bills', 'shopping', 'health', 'fun', 'travel', 'education', 'other')),
  account_id     uuid references public.money_account on delete set null,
  day            smallint not null check (day between 1 and 31),   -- 31 means the last day in shorter months
  paused         boolean not null default false,
  added_through  text check (added_through ~ '^\d{4}-\d{2}$'),     -- the last month whose spend was added, "2026-11"
  rev            bigint not null default 0,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

alter table public.fixed_bill enable row level security;
create policy owner_only on public.fixed_bill for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create trigger touch before insert or update on public.fixed_bill for each row execute function public.touch_row();
create index on public.fixed_bill (owner_id, rev);

-- A bill may only come off one of the owner's own accounts.
create policy account_is_mine on public.fixed_bill as restrictive for all to authenticated
  with check (account_id is null
              or exists (select 1 from public.money_account a where a.id = account_id and a.owner_id = (select auth.uid())));

alter table public.transaction drop constraint transaction_source_check;
alter table public.transaction add constraint transaction_source_check
  check (source in ('manual', 'applepay', 'sms', 'email', 'simplefin', 'bill'));
