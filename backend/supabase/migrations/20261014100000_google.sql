-- Google Calendar for /meet (ARCHITECTURE §34, the first Google connection): the owner connects Google once, the server
-- keeps the refresh token in Vault, and it creates an event with a Meet link only for a red "meet.create" action the
-- owner signed with Touch ID (§36.5). The token never reaches a device.

-- Who is connected, for Settings. The server writes it; the owner can only read it.
create table public.google_link (
  owner_id      uuid primary key references auth.users on delete cascade,
  email         text not null check (length(email) <= 320),
  token_secret  uuid not null,                       -- the vault.secrets row holding the refresh token
  connected_at  timestamptz not null default now()
);
alter table public.google_link enable row level security;
create policy owner_reads on public.google_link for select to authenticated using (owner_id = (select auth.uid()));
revoke insert, update, delete on public.google_link from authenticated;

-- One-time sign-in states (10 minutes), so Google's answer can only connect the owner who started it. Server only.
create table public.google_oauth_state (
  state_hash  bytea primary key,
  owner_id    uuid not null references auth.users on delete cascade,
  expires_at  timestamptz not null
);
alter table public.google_oauth_state enable row level security;   -- no policy: no client reads or writes
revoke all on public.google_oauth_state from authenticated;

-- Saves (or replaces) the owner's refresh token in Vault and records the connection.
create function public.google_connect(owner uuid, account text, token text) returns void
language plpgsql security definer set search_path = '' as $$
declare sid uuid;
begin
  select token_secret into sid from public.google_link where owner_id = owner;
  if sid is null then
    sid := vault.create_secret(token, 'google:' || owner::text, 'Google Calendar refresh token for Blink');
  else
    perform vault.update_secret(sid, token);
  end if;
  insert into public.google_link (owner_id, email, token_secret) values (owner, account, sid)
    on conflict (owner_id) do update set email = excluded.email, connected_at = now();
end $$;

-- The owner's refresh token, or null when Google isn't connected. (plpgsql, so tests without Vault can still load it.)
create function public.google_token(owner uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
begin
  return (select s.decrypted_secret from vault.decrypted_secrets s
            join public.google_link l on l.token_secret = s.id
           where l.owner_id = owner);
end $$;

revoke all on function public.google_connect(uuid, text, text) from public, anon, authenticated;
revoke all on function public.google_token(uuid) from public, anon, authenticated;
grant execute on function public.google_connect(uuid, text, text) to service_role;
grant execute on function public.google_token(uuid) to service_role;

-- Inviting people is always red: approved only by a signed device challenge, never by a client status change.
alter table public.action add constraint meet_create_is_red check (kind <> 'meet.create' or risk = 'red');
