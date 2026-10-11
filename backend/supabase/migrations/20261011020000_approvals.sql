-- Ask-First approvals (ARCHITECTURE §6, §36.5).

-- The server, not the client, decides what an approval covers: payload_hash = sha256(payload as stored).
create or replace function public.hash_action_payload() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.payload_hash := sha256(convert_to(new.payload::text, 'UTF8'));
  return new;
end $$;

create trigger hash_payload before insert on public.action
  for each row execute function public.hash_action_payload();

-- A client may enrol an approval key only on a device that has none, and only while no other device of
-- this owner has one. Otherwise a stolen session token could register its own key and sign red approvals.
-- shortcut: one enrolled device per owner; QR pairing (§36.5) adds signed enrolment for more devices.
create or replace function public.guard_approval_key() returns trigger
language plpgsql set search_path = '' as $$
begin
  if current_user <> 'authenticated' then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.approval_key is not distinct from old.approval_key then
    return new;
  end if;
  if new.approval_key is null then
    if tg_op = 'UPDATE' then
      raise exception 'an approval key cannot be removed by a client';
    end if;
    return new;
  end if;
  if (tg_op = 'UPDATE' and old.approval_key is not null)
     or exists (select 1 from public.device d
                where d.owner_id = new.owner_id and d.id <> new.id and d.approval_key is not null) then
    raise exception 'an approval key can only be enrolled once';
  end if;
  if octet_length(new.approval_key) <> 65 or get_byte(new.approval_key, 0) <> 4 then
    raise exception 'approval key must be an uncompressed P-256 public key';
  end if;
  return new;
end $$;

create trigger guard_key before insert or update on public.device
  for each row execute function public.guard_approval_key();
