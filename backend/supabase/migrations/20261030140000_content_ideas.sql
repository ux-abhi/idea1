-- Content plan (2026-10-30): a week plan's ideas are kept as posts with status 'idea', each on its day, until the owner
-- writes, moves or removes them (they used to live only in the app's memory and were lost on quit).
alter table public.content_piece drop constraint content_piece_status_check;
alter table public.content_piece add constraint content_piece_status_check
  check (status in ('idea', 'drafted', 'approved', 'published', 'archived'));
