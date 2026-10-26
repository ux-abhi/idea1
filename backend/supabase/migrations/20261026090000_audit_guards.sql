-- Audit fixes (2026-10-26).

-- 1. An action's kind is fixed once proposed, like its risk and payload. Otherwise an approved red card (a meeting)
--    could be renamed to mail.send after Touch ID, and the outbox would send its payload as mail.
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
  if new.kind <> old.kind or new.risk <> old.risk or new.payload <> old.payload or new.payload_hash <> old.payload_hash then
    raise exception 'an action''s kind, risk and payload cannot change after it is proposed';
  end if;
  return new;
end $$;

-- 2. Revoking a device is one-way for a client: a stolen session can't trust a revoked device again.
-- shortcut: the revoked device keeps the approval key slot, so re-enrolling needs service-role SQL; QR pairing (§36.5) lifts this.
create or replace function public.guard_device_revoke() returns trigger
language plpgsql set search_path = '' as $$
begin
  if current_user = 'authenticated' and old.revoked_at is not null and new.revoked_at is distinct from old.revoked_at then
    raise exception 'a revoked device stays revoked';
  end if;
  return new;
end $$;

create trigger guard_revoke before update on public.device
  for each row execute function public.guard_device_revoke();

-- 3. (Before applying to a live server: `select count(*) from public.profile` must be 1, or the owner's check-in fails.)
--    One owner per server: a second login (if sign-ups were ever left open) can't add a profile, which would switch
--    off the owner's mail, Google and keys, all of which expect exactly one profile.
create or replace function public.guard_one_profile() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.profile where owner_id <> new.owner_id) then
    raise exception 'this server already has an owner';
  end if;
  return new;
end $$;
revoke execute on function public.guard_one_profile() from public, anon, authenticated;

create trigger one_profile before insert on public.profile
  for each row execute function public.guard_one_profile();
