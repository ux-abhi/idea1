-- Spaces as project workspaces (2026-10-22): a cover, the Space's own board columns, and for each task its column and a
-- start date (for the timeline). Covers are named gradients drawn by the app; images come later.
alter table public.segment add column cover text not null default 'aurora'
  check (cover in ('aurora', 'ocean', 'sunset', 'forest', 'dusk', 'rose', 'mono'));
alter table public.segment add column columns jsonb not null default '["To do", "Doing", "Done"]'
  check (jsonb_typeof(columns) = 'array' and jsonb_array_length(columns) between 2 and 8);
alter table public.item add column stage text check (stage is null or length(stage) between 1 and 60);
alter table public.item add column start_at timestamptz;
