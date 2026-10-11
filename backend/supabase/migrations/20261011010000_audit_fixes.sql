-- Phase 0 audit fixes.

-- A client must not create a red action that is already approved or done (§36.5): guard inserts too.
create or replace function public.guard_action_update() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if current_user = 'authenticated' and new.risk = 'red' and new.status <> 'pending' then
      raise exception 'red actions are approved by a signed device challenge only';
    end if;
    return new;
  end if;
  if current_user = 'authenticated' and new.risk = 'red' and new.status <> old.status
     and new.status in ('approved', 'done') then
    raise exception 'red actions are approved by a signed device challenge only';
  end if;
  if new.risk <> old.risk or new.payload <> old.payload or new.payload_hash <> old.payload_hash then
    raise exception 'an action''s risk and payload cannot change after it is proposed';
  end if;
  return new;
end $$;

drop trigger guard on public.action;
create trigger guard before insert or update on public.action for each row execute function public.guard_action_update();

-- (owner_id, rev) already serves every owner_id lookup on synced tables; profile's owner_id is its primary key.
drop index public.profile_owner_id_idx, public.memory_fact_owner_id_idx, public.device_owner_id_idx,
  public.item_owner_id_idx, public.link_owner_id_idx, public.calendar_event_owner_id_idx,
  public.action_owner_id_idx, public.rule_owner_id_idx;
