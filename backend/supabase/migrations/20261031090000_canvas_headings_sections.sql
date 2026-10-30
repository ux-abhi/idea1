-- Canvas (2026-10-31): headings (text straight on the canvas) and sections (a tinted area that groups cards). They
-- point at nothing; their text is kept on the node itself.
alter table public.space_node drop constraint space_node_kind_check;
alter table public.space_node add constraint space_node_kind_check
  check (kind in ('project', 'task', 'note', 'reminder', 'image', 'post', 'heading', 'section'));
alter table public.space_node add column label text check (label is null or length(label) <= 200);
