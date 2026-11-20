-- Weekly goals (2026-11-20, Habits & Goals): what the owner wants to get done this week, set with "Plan my week".
-- A goal is a counter the owner ticks by hand ("Create 5 posts", target 5) or a single check (target 1). Nothing counts
-- automatically. A goal may be linked to a Space, like tasks and notes.

create table public.weekly_goal (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users on delete cascade,
  week_start  date not null check (extract(isodow from week_start) = 1),   -- the Monday the week starts on
  title       text not null check (length(trim(title)) between 1 and 200),
  target      smallint not null default 1 check (target between 1 and 100),
  done_count  smallint not null default 0 check (done_count between 0 and 100),
  segment_id  uuid references public.segment on delete set null,
  position    smallint not null default 0,
  rev         bigint not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  check (done_count <= target)
);

alter table public.weekly_goal enable row level security;
create policy owner_only on public.weekly_goal for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
-- A goal may only be linked to one of the owner's own Spaces.
create policy space_is_mine on public.weekly_goal as restrictive for all to authenticated
  with check (segment_id is null
              or exists (select 1 from public.segment s where s.id = segment_id and s.owner_id = (select auth.uid())));
create trigger touch before insert or update on public.weekly_goal for each row execute function public.touch_row();
create index on public.weekly_goal (owner_id, week_start);
create index on public.weekly_goal (owner_id, rev);
create index on public.weekly_goal (segment_id) where segment_id is not null;
