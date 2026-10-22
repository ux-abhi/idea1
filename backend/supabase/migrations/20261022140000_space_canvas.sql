-- A Space as a canvas (2026-10-22): its project, tasks, notes (stickies) and reminders as nodes the owner places and
-- links freely. A node only points at the real thing (an item id, or an Apple Reminders id kept on the Mac), so the
-- task on the canvas is the same task everywhere in Blink; deleting a Space removes its canvas, never its items.
create table public.space_node (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users on delete cascade,
  segment_id  uuid not null references public.segment on delete cascade,
  kind        text not null check (kind in ('project', 'task', 'note', 'reminder')),
  ref         text check (ref is null or length(ref) between 1 and 200),
  x           double precision not null default 0 check (x between -20000 and 20000),
  y           double precision not null default 0 check (y between -20000 and 20000),
  color       text not null default 'yellow'
              check (color in ('blue', 'purple', 'pink', 'red', 'orange', 'yellow', 'green', 'mint', 'teal', 'indigo', 'gray')),
  rev         bigint not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (segment_id, kind, ref)
);
create table public.space_edge (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users on delete cascade,
  segment_id  uuid not null references public.segment on delete cascade,
  from_node   uuid not null references public.space_node on delete cascade,
  to_node     uuid not null references public.space_node on delete cascade,
  created_at  timestamptz not null default now(),
  unique (from_node, to_node),
  check (from_node <> to_node)
);
alter table public.space_node enable row level security;
alter table public.space_edge enable row level security;
create policy owner_only on public.space_node for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy owner_only on public.space_edge for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
-- Only in the owner's own Space, and edges only between the owner's own nodes of that Space.
create policy segment_is_mine on public.space_node as restrictive for all to authenticated
  with check (exists (select 1 from public.segment s where s.id = segment_id and s.owner_id = (select auth.uid())));
create policy nodes_are_mine on public.space_edge as restrictive for all to authenticated
  with check (exists (select 1 from public.space_node n where n.id = from_node and n.owner_id = (select auth.uid()) and n.segment_id = space_edge.segment_id)
              and exists (select 1 from public.space_node n where n.id = to_node and n.owner_id = (select auth.uid()) and n.segment_id = space_edge.segment_id));
create trigger touch before insert or update on public.space_node for each row execute function public.touch_row();
create index on public.space_node (segment_id);
-- One project node per Space (`unique` above lets nulls repeat, and the project's ref is null).
create unique index space_node_one_project on public.space_node (segment_id) where kind = 'project';
create index on public.space_edge (segment_id);
