-- Money, first slice of Phase 7 (ARCHITECTURE §9.7, §16): spends the owner types in (the AI sorts them into categories)
-- and a monthly limit per category. Apple Pay, bank SMS and alert emails add rows to the same table later (source).

create table public.transaction (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users on delete cascade,
  amount      numeric(12, 2) not null check (amount > 0 and amount < 1000000),
  currency    text not null default 'EUR' check (currency ~ '^[A-Z]{3}$'),
  note        text not null default '' check (length(note) <= 300),
  category    text not null default 'other' check (category in
                ('food', 'groceries', 'transport', 'housing', 'bills', 'shopping', 'health', 'fun', 'travel', 'education', 'other')),
  spent_on    date not null default current_date,
  source      text not null default 'manual' check (source in ('manual', 'applepay', 'sms', 'email', 'simplefin')),
  dedupe_key  text check (length(dedupe_key) <= 200),
  rev         bigint not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table public.budget (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null default auth.uid() references auth.users on delete cascade,
  category       text not null check (category in
                   ('food', 'groceries', 'transport', 'housing', 'bills', 'shopping', 'health', 'fun', 'travel', 'education', 'other')),
  monthly_limit  numeric(12, 2) not null check (monthly_limit > 0 and monthly_limit < 1000000),
  rev            bigint not null default 0,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (owner_id, category)
);

do $$
declare t text;
begin
  foreach t in array array['transaction', 'budget'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy owner_only on public.%I for all to authenticated
                    using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()))', t);
    execute format('create trigger touch before insert or update on public.%I for each row execute function public.touch_row()', t);
    execute format('create index on public.%I (owner_id, rev)', t);
  end loop;
end $$;

create index on public.transaction (owner_id, spent_on desc);
-- Automatic capture (later) never adds the same spend twice.
create unique index transaction_dedupe on public.transaction (owner_id, dedupe_key) where dedupe_key is not null;
