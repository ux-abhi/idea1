-- "Must be mine" checks: a foreign key alone accepts another owner's row id, so these rows may only point at the
-- caller's own items and devices (same pattern as habit_log.habit_id and item.segment_id).
create policy items_are_mine on public.link as restrictive for all to authenticated
  with check (exists (select 1 from public.item i where i.id = from_item and i.owner_id = (select auth.uid()))
              and exists (select 1 from public.item i where i.id = to_item and i.owner_id = (select auth.uid())));

create policy device_is_mine on public.calendar_event as restrictive for all to authenticated
  with check (snapshot_device is null
              or exists (select 1 from public.device d where d.id = snapshot_device and d.owner_id = (select auth.uid())));

create policy device_is_mine on public.action as restrictive for all to authenticated
  with check (decided_by_device is null
              or exists (select 1 from public.device d where d.id = decided_by_device and d.owner_id = (select auth.uid())));
