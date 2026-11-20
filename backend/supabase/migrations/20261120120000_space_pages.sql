-- Spaces (2026-11-20, ADR-0002): link cards on the canvas, and Page mode, a Space as a page of blocks.
--
-- A link card keeps its web address on the node (title in label). A page block holds only how it shows (a heading's
-- text, a timer's minutes, a link's address): the tasks, notes and posts a block lists stay where they are, linked to
-- the Space, so the page and the canvas show the same things and a Space's shape can later be saved as a template.

alter table public.space_node drop constraint space_node_kind_check;
alter table public.space_node add constraint space_node_kind_check
  check (kind in ('project', 'task', 'note', 'reminder', 'image', 'post', 'heading', 'section', 'link'));
alter table public.space_node add column url text check (url is null or (length(url) <= 2000 and url ~* '^https?://'));

create table public.space_block (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users on delete cascade,
  segment_id  uuid not null references public.segment on delete cascade,
  position    double precision not null default 0,
  kind        text not null check (kind in ('heading', 'text', 'tasks', 'content', 'note', 'link', 'image', 'timer', 'stopwatch')),
  data        jsonb not null default '{}' check (jsonb_typeof(data) = 'object' and octet_length(data::text) <= 20000),
  rev         bigint not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.space_block enable row level security;
create policy owner_only on public.space_block for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
-- A block may only go on a page of one of the owner's own Spaces.
create policy space_is_mine on public.space_block as restrictive for all to authenticated
  with check (exists (select 1 from public.segment s where s.id = segment_id and s.owner_id = (select auth.uid())));
create trigger touch before insert or update on public.space_block for each row execute function public.touch_row();
create index on public.space_block (segment_id, position);
create index on public.space_block (owner_id, rev);
