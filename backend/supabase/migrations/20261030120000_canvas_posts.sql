-- Canvas (2026-10-30): a post written for a Space sits on its canvas too; the node's ref is the content_piece id.
alter table public.space_node drop constraint space_node_kind_check;
alter table public.space_node add constraint space_node_kind_check
  check (kind in ('project', 'task', 'note', 'reminder', 'image', 'post'));
