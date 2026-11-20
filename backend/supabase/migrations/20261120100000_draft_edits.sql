-- Draft quality (2026-11-20): how much the owner changes a draft before approving it is the clearest sign of how good
-- the AI's writing was. Each AI draft keeps its original text and the model that wrote it; on approval the app saves
-- the share of words the owner changed (0 = used as written, 1 = rewritten). Settings › AI shows it per model.

alter table public.content_piece
  add column ai_text text check (length(ai_text) <= 40000),
  add column ai_model text check (length(ai_model) <= 100),
  add column edited_share numeric(4, 3) check (edited_share between 0 and 1);
