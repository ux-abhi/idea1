-- Page and canvas as one Space (2026-11-21, ADR-0004 §2): a canvas card can show one of the page's tables (ref → the
-- table block) or one row of a table (ref → the row, label → its table block). The card only points; nothing is copied.

alter table public.space_node drop constraint space_node_kind_check;
alter table public.space_node add constraint space_node_kind_check
  check (kind in ('project', 'task', 'note', 'reminder', 'image', 'post', 'heading', 'section', 'link', 'block', 'card'));
