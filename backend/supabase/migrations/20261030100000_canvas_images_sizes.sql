-- Canvas (2026-10-30): stickies and images can be resized, a sticky's text can be made bigger, and an image can sit on
-- the canvas. An image node's ref is its file in the private `canvas` bucket, under the owner's own folder.
alter table public.space_node drop constraint space_node_kind_check;
alter table public.space_node add constraint space_node_kind_check check (kind in ('project', 'task', 'note', 'reminder', 'image'));
alter table public.space_node
  add column w          double precision check (w is null or w between 80 and 1600),
  add column h          double precision check (h is null or h between 60 and 1600),
  add column text_scale double precision check (text_scale is null or text_scale between 0.5 and 4);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('canvas', 'canvas', false, 5242880, array['image/jpeg'])
on conflict (id) do nothing;

-- Only the owner's own folder: <owner id>/<space id>/<file>.
create policy canvas_own_folder on storage.objects for all to authenticated
  using (bucket_id = 'canvas' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'canvas' and (storage.foldername(name))[1] = (select auth.uid())::text);
