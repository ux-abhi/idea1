-- Income (2026-11-14): money coming in. `income` is money that came in (a one-time payment, or one month of a
-- recurring one); `income_plan` is a recurring one: the same amount on the same day each month, until an optional last
-- month. On or after that day the app adds the month's income itself (source 'plan', dedupe_key
-- 'income:<plan id>:<YYYY-MM>', so two Macs never add it twice), like fixed bills. Income adds to an account's balance.

create table public.income_plan (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null default auth.uid() references auth.users on delete cascade,
  note           text not null check (length(trim(note)) between 1 and 300),
  amount         numeric(12, 2) not null check (amount > 0 and amount < 10000000),
  account_id     uuid references public.money_account on delete set null,
  day            smallint not null check (day between 1 and 31),   -- 31 means the last day in shorter months
  paused         boolean not null default false,
  added_through  text check (added_through ~ '^\d{4}-\d{2}$'),     -- the last month whose income was added
  ends_month     text check (ends_month ~ '^\d{4}-\d{2}$'),        -- the last month it comes in; null: until stopped
  rev            bigint not null default 0,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create table public.income (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null default auth.uid() references auth.users on delete cascade,
  amount       numeric(12, 2) not null check (amount > 0 and amount < 10000000),
  note         text not null check (length(trim(note)) between 1 and 300),
  account_id   uuid references public.money_account on delete set null,
  received_on  date not null default current_date,
  source       text not null default 'manual' check (source in ('manual', 'plan')),
  plan_id      uuid references public.income_plan on delete set null,
  dedupe_key   text check (length(dedupe_key) <= 200),
  rev          bigint not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

do $$
declare t text;
begin
  foreach t in array array['income_plan', 'income'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy owner_only on public.%I for all to authenticated
                    using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()))', t);
    execute format('create trigger touch before insert or update on public.%I for each row execute function public.touch_row()', t);
    execute format('create index on public.%I (owner_id, rev)', t);
    -- Income may only go into one of the owner's own accounts.
    execute format('create policy account_is_mine on public.%I as restrictive for all to authenticated
                    with check (account_id is null
                                or exists (select 1 from public.money_account a where a.id = account_id and a.owner_id = (select auth.uid())))', t);
    execute format('create index on public.%I (account_id) where account_id is not null', t);
  end loop;
end $$;

create index on public.income (owner_id, received_on desc);
create index on public.income (plan_id) where plan_id is not null;
create unique index income_dedupe on public.income (owner_id, dedupe_key) where dedupe_key is not null;

-- Balances now add the income entered since the balance was set (a new last column, so the view is only extended).
create or replace view public.money_account_now with (security_invoker = true) as
select a.id, a.name, a.kind, a.balance, a.balance_at, a.is_default, a.created_at,
       coalesce((select sum(t.amount) from public.transaction t
                 where t.account_id = a.id and t.created_at >= a.balance_at), 0) as spent_since,
       coalesce((select sum(i.amount) from public.income i
                 where i.account_id = a.id and i.created_at >= a.balance_at), 0) as received_since
from public.money_account a;
