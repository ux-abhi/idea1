-- Habits (ARCHITECTURE §16, §36.2): a habit with its scheduled weekdays, and one answer per habit per day.

create table public.habit (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users on delete cascade,
  name        text not null check (length(trim(name)) > 0),
  -- Calendar weekdays it's scheduled on, 1 = Sunday … 7 = Saturday. Other days are rest days.
  weekdays    smallint[] not null default '{1,2,3,4,5,6,7}'
              check (cardinality(weekdays) > 0 and weekdays <@ '{1,2,3,4,5,6,7}'::smallint[]),
  archived_at timestamptz,
  rev         bigint not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- "day" is the habit day, which ends at the owner's wake time (computed on the device).
create table public.habit_log (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users on delete cascade,
  habit_id    uuid not null references public.habit on delete cascade,
  day         date not null,
  status      text not null check (status in ('done', 'not_today', 'skipped')),
  rev         bigint not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (habit_id, day)
);

do $$
declare t text;
begin
  foreach t in array array['habit', 'habit_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy owner_only on public.%I for all to authenticated
                    using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()))', t);
    execute format('create trigger touch before insert or update on public.%I for each row execute function public.touch_row()', t);
    execute format('create index on public.%I (owner_id, rev)', t);
  end loop;
end $$;

-- A log may only point at the owner's own habit (a foreign key alone would accept anyone's habit id).
create policy habit_is_mine on public.habit_log as restrictive for all to authenticated
  with check (exists (select 1 from public.habit h where h.id = habit_id and h.owner_id = (select auth.uid())));

create index on public.habit_log (habit_id, day);
