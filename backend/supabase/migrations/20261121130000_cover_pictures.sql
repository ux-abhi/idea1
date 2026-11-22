-- A Space's cover can be the owner's own picture (2026-11-21): "file:<owner id>/<space id>/<file>" in the files bucket,
-- next to the named gradients. Only a picture in the owner's own folder is accepted.

alter table public.segment drop constraint segment_cover_check;
alter table public.segment add constraint segment_cover_check check (
  cover in ('aurora', 'ocean', 'sunset', 'forest', 'dusk', 'rose', 'mono')
  or (cover like 'file:%' and length(cover) <= 300 and split_part(substr(cover, 6), '/', 1) = owner_id::text and cover not like '%..%')
);
