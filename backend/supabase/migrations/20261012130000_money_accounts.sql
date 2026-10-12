-- Money accounts (owner, 2026-10-12): the owner's bank, savings, cash and card accounts with a balance they set by hand.
-- A spend can come off an account; the app shows balance − spends from it since balance_at, until the owner updates it.

create table public.money_account (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users on delete cascade,
  name        text not null check (length(trim(name)) between 1 and 60),
  kind        text not null default 'checking' check (kind in ('checking', 'savings', 'cash', 'card', 'other')),
  balance     numeric(14, 2) not null default 0 check (abs(balance) < 100000000000),
  balance_at  timestamptz not null default now(),   -- when the owner last set the balance
  currency    text not null default 'EUR' check (currency ~ '^[A-Z]{3}$'),
  is_default  boolean not null default false,       -- spends with no account named come off this one
  rev         bigint not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (owner_id, name)
);

alter table public.money_account enable row level security;
create policy owner_only on public.money_account for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create trigger touch before insert or update on public.money_account for each row execute function public.touch_row();
create index on public.money_account (owner_id, rev);
-- At most one default account per owner.
create unique index money_account_one_default on public.money_account (owner_id) where is_default;

alter table public.transaction add column account_id uuid references public.money_account on delete set null;
create index on public.transaction (account_id) where account_id is not null;

-- A spend may only come off one of the owner's own accounts.
create policy account_is_mine on public.transaction as restrictive for all to authenticated
  with check (account_id is null
              or exists (select 1 from public.money_account a where a.id = account_id and a.owner_id = (select auth.uid())));

-- Each account's balance now, added up in the database so it stays exact however many spends there are: what the owner
-- last set, minus spends from it entered since. security_invoker: row-level security applies as for the tables.
create view public.money_account_now with (security_invoker = true) as
select a.id, a.name, a.kind, a.balance, a.balance_at, a.is_default, a.created_at,
       coalesce((select sum(t.amount) from public.transaction t
                 where t.account_id = a.id and t.created_at > a.balance_at), 0) as spent_since
from public.money_account a;
