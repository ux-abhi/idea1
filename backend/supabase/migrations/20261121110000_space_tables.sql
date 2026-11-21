-- Spaces as the place where material lives (2026-11-21, ADR-0002/0003): a table block (columns in the block, rows here)
-- and a file block (a document or picture in the owner's files bucket). A bulk mail can take its contacts from a
-- Space's table, filtered by a tag, and each contact remembers its row so the mail's status shows back in the table.

alter table public.space_block drop constraint space_block_kind_check;
alter table public.space_block add constraint space_block_kind_check
  check (kind in ('heading', 'text', 'tasks', 'content', 'note', 'link', 'image', 'timer', 'stopwatch', 'table', 'file'));

create table public.space_table_row (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users on delete cascade,
  block_id    uuid not null references public.space_block on delete cascade,
  position    double precision not null default 0,
  -- column id → text; the columns themselves (name, type) are in the block's data.
  cells       jsonb not null default '{}' check (jsonb_typeof(cells) = 'object' and octet_length(cells::text) <= 8000),
  rev         bigint not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.space_table_row enable row level security;
create policy owner_only on public.space_table_row for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
-- A row may only go into one of the owner's own table blocks.
create policy block_is_mine on public.space_table_row as restrictive for all to authenticated
  with check (exists (select 1 from public.space_block b where b.id = block_id and b.owner_id = (select auth.uid()) and b.kind = 'table'));
create trigger touch before insert or update on public.space_table_row for each row execute function public.touch_row();
create index on public.space_table_row (block_id, position);
create index on public.space_table_row (owner_id, rev);

-- A bulk mail made from a Space's table: which table, and which tag picks the rows ('' for all of them).
alter table public.mail_campaign
  add column table_block uuid references public.space_block on delete set null,
  add column tag text not null default '' check (length(tag) <= 60);
alter table public.mail_recipient add column row_id uuid references public.space_table_row on delete set null;
create index on public.mail_recipient (row_id) where row_id is not null;
-- The table must be one of the owner's own blocks; a contact's row one of the owner's own rows.
create policy table_is_mine on public.mail_campaign as restrictive for all to authenticated
  with check (table_block is null
              or exists (select 1 from public.space_block b where b.id = table_block and b.owner_id = (select auth.uid())));
create policy row_is_mine on public.mail_recipient as restrictive for all to authenticated
  with check (row_id is null
              or exists (select 1 from public.space_table_row r where r.id = row_id and r.owner_id = (select auth.uid())));
