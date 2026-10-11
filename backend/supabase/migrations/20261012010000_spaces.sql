-- Spaces (ARCHITECTURE §35; "segment" internally, "Space" on screen, §36.2 word list). Project template first.
-- Tasks and notes join a space through item.segment_id; deleting a space keeps its items.

create table public.segment (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users on delete cascade,
  -- Templates are data (§35.3); only Project exists so far.
  template    text not null default 'project' check (template in ('project')),
  title       text not null check (length(trim(title)) between 1 and 200),
  goal        text not null default '' check (length(goal) <= 2000),
  status      text not null default 'active' check (status in ('active', 'paused', 'done', 'archived')),
  due_at      timestamptz,
  -- An Apple system colour by name (the app never uses hex).
  color       text not null default 'blue'
              check (color in ('blue', 'purple', 'pink', 'red', 'orange', 'yellow', 'green', 'mint', 'teal', 'cyan', 'indigo', 'brown', 'gray')),
  icon        text not null default 'folder' check (length(icon) between 1 and 64),
  rev         bigint not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.segment enable row level security;
create policy owner_only on public.segment for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create trigger touch before insert or update on public.segment for each row execute function public.touch_row();
create index on public.segment (owner_id, rev);

alter table public.item add column segment_id uuid references public.segment on delete set null;
create index on public.item (segment_id);

-- An item may only join the owner's own space (a foreign key alone would accept anyone's space id).
create policy segment_is_mine on public.item as restrictive for all to authenticated
  with check (segment_id is null
              or exists (select 1 from public.segment s where s.id = segment_id and s.owner_id = (select auth.uid())));
