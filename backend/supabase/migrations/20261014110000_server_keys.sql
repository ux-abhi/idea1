-- Keys and mail passwords added in the app (Settings › Connections) instead of the Supabase dashboard. Each value lives
-- encrypted in Vault; the app can add, replace or remove one but never read it back. A server has one owner (sign-ups
-- are off, §33), so keys belong to the server; functions read them with Edge Function secrets as the fallback.

-- Only the keys Blink's functions read; nothing else can be stored.
create domain public.server_key_name as text check (value in (
  'ANTHROPIC_API_KEY', 'ANTHROPIC_WORKSPACE_ID', 'GROQ_API_KEY', 'OPENROUTER_API_KEY', 'APIFY_TOKEN',
  'CLOUDFLARE_API_TOKEN', 'CLOUDFLARE_ACCOUNT_ID',
  'GMAIL_ADDRESS', 'GMAIL_APP_PASSWORD', 'ICLOUD_ADDRESS', 'ICLOUD_APP_PASSWORD',
  'UNI_ADDRESS', 'UNI_PASSWORD', 'UNI_IMAP_HOST', 'UNI_SMTP_HOST',
  'GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET'));

-- The server's owner: the caller is the one and only profile (a second account, if sign-ups were ever turned back on,
-- must never be able to point the mail settings at its own server and collect the owner's passwords).
create function public.is_server_owner() returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and (select count(*) from public.profile) = 1
     and exists (select 1 from public.profile where owner_id = auth.uid());
$$;
revoke all on function public.is_server_owner() from public, anon;
grant execute on function public.is_server_owner() to authenticated;

create table public.server_key (
  name        public.server_key_name primary key,
  secret_id   uuid not null,                         -- the vault.secrets row holding the value
  updated_at  timestamptz not null default now()
);
-- The owner sees which keys are saved (names only, never values); only the functions below write.
alter table public.server_key enable row level security;
create policy owner_reads on public.server_key for select to authenticated
  using ((select public.is_server_owner()));
revoke insert, update, delete on public.server_key from authenticated;

-- Adds or replaces one key. Only the server's owner (someone with a profile) may.
create function public.set_server_key(key_name text, key_value text) returns void
language plpgsql security definer set search_path = '' as $$
declare sid uuid; v text := btrim(key_value);
begin
  if not public.is_server_owner() then raise exception 'only the owner can change keys' using errcode = '42501'; end if;
  perform key_name::public.server_key_name;   -- unknown names fail here, before anything touches Vault
  if v = '' or length(v) > 4096 then raise exception 'a key is 1 to 4096 characters' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtext('blink-key:' || key_name));   -- two first saves at once: one waits
  select secret_id into sid from public.server_key where name = key_name;
  if sid is null then
    -- Reuse a secret left behind by a hand-deleted row, else make one (Vault names are unique).
    select id into sid from vault.secrets where name = 'blink-key:' || key_name;
    if sid is null then
      sid := vault.create_secret(v, 'blink-key:' || key_name, 'Added in Blink › Settings › Connections');
    else
      perform vault.update_secret(sid, v);
    end if;
    insert into public.server_key (name, secret_id) values (key_name, sid);
  else
    perform vault.update_secret(sid, v);
    update public.server_key set updated_at = now() where name = key_name;
  end if;
end $$;

-- Removes one key (the dashboard secret, if any, applies again).
create function public.remove_server_key(key_name text) returns void
language plpgsql security definer set search_path = '' as $$
declare sid uuid;
begin
  if not public.is_server_owner() then raise exception 'only the owner can change keys' using errcode = '42501'; end if;
  delete from public.server_key where name = key_name returning secret_id into sid;
  if sid is not null then delete from vault.secrets where id = sid; end if;
end $$;

-- Every saved key with its value, for the server's functions only.
create function public.server_keys() returns table (name text, value text)
language plpgsql stable security definer set search_path = '' as $$
begin
  return query select k.name::text, s.decrypted_secret::text from public.server_key k join vault.decrypted_secrets s on s.id = k.secret_id;
end $$;

revoke all on function public.set_server_key(text, text) from public, anon;
revoke all on function public.remove_server_key(text) from public, anon;
revoke all on function public.server_keys() from public, anon, authenticated;
grant execute on function public.set_server_key(text, text) to authenticated;
grant execute on function public.remove_server_key(text) to authenticated;
grant execute on function public.server_keys() to service_role;

-- Disconnecting Google (the google function revokes the token at Google first, then calls this): link and token go.
create function public.google_disconnect(owner uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare sid uuid;
begin
  delete from public.google_link where owner_id = owner returning token_secret into sid;
  if sid is not null then delete from vault.secrets where id = sid; end if;
end $$;
revoke all on function public.google_disconnect(uuid) from public, anon, authenticated;
grant execute on function public.google_disconnect(uuid) to service_role;
