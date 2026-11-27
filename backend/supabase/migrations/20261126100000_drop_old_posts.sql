-- Posts are cards in a Content table now (ADR-0004 §6); the owner checked the move and asked for the old drafts to go.
drop table if exists public.content_piece;
