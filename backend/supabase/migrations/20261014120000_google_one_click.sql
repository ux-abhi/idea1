-- One-click Google (ARCHITECTURE §34): Blink ships one Google client of the Desktop type, so owners don't create a Google
-- app. The Mac gets Google's one-time code over 127.0.0.1 with PKCE; the owner's server exchanges it with that client
-- and keeps the token in Vault as before. The owner's own Web client ("own") keeps working for those who set one up.

-- The Desktop client's ID and secret (public by Google's design for installed apps), saved by the app like other keys.
alter domain public.server_key_name drop constraint server_key_name_check;
alter domain public.server_key_name add constraint server_key_name_check check (value in (
  'ANTHROPIC_API_KEY', 'ANTHROPIC_WORKSPACE_ID', 'GROQ_API_KEY', 'OPENROUTER_API_KEY', 'APIFY_TOKEN',
  'CLOUDFLARE_API_TOKEN', 'CLOUDFLARE_ACCOUNT_ID',
  'GMAIL_ADDRESS', 'GMAIL_APP_PASSWORD', 'ICLOUD_ADDRESS', 'ICLOUD_APP_PASSWORD',
  'UNI_ADDRESS', 'UNI_PASSWORD', 'UNI_IMAP_HOST', 'UNI_SMTP_HOST',
  'GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET', 'GOOGLE_DESKTOP_CLIENT_ID', 'GOOGLE_DESKTOP_CLIENT_SECRET'));

-- Which client made the token: refreshing it needs the same one.
alter table public.google_link add column client text not null default 'own' check (client in ('own', 'blink'));

drop function public.google_connect(uuid, text, text);
-- via defaults to 'own', so a function deployed before this migration (3 arguments) keeps working.
create function public.google_connect(owner uuid, account text, token text, via text default 'own') returns void
language plpgsql security definer set search_path = '' as $$
declare sid uuid;
begin
  if via not in ('own', 'blink') then raise exception 'unknown Google client' using errcode = '22023'; end if;
  select token_secret into sid from public.google_link where owner_id = owner;
  if sid is null then
    sid := vault.create_secret(token, 'google:' || owner::text, 'Google Calendar refresh token for Blink');
  else
    perform vault.update_secret(sid, token);
  end if;
  insert into public.google_link (owner_id, email, token_secret, client) values (owner, account, sid, via)
    on conflict (owner_id) do update set email = excluded.email, client = excluded.client, connected_at = now();
end $$;
revoke all on function public.google_connect(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.google_connect(uuid, text, text, text) to service_role;
